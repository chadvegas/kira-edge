import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

struct DeletedWidget: Equatable {
    var tile: WidgetTile
    var index: Int
    var preset: DashboardPreset
    var pageID: DashboardPage.ID
}

/// Thrown by DashboardStore.importProfile(from:) when the picked file doesn't
/// look like a profile export. DashboardProfile's tolerant decoder turns ANY
/// JSON object into an all-defaults profile, so without this check a wrong
/// .json pick would silently wipe the dashboard and persist the wipe.
struct ProfileImportError: LocalizedError {
    var errorDescription: String? { "Not a XENEON Edge profile export" }
}

@MainActor
@Observable
final class DashboardStore {
    var edgeMode = false
    var isPinned = true
    var currentTime = Date()
    var noteText = "Ready"
    var selectedWidgetID: WidgetTile.ID?
    var focusedTileID: WidgetTile.ID?
    // Selected section in the Widget Settings window. Held here (not as view @State) so
    // deep inspector rows can navigate between sections, e.g. Content → Apps & Launcher.
    var settingsSection: ControlSection? = .overview
    var isEditingWidgets = false
    var selectedPreset: DashboardPreset = .command
    var appearanceMode: EdgeAppearanceMode = .dark
    var showsFullDayForecast = false
    var uses24HourTime = false
    /// When on, widgets mask personal data (device owner names, IP addresses,
    /// calendar event titles) so the dashboard is safe to screenshot or share.
    var privacyMode = false
    var forecastRange: ForecastRange = .day
    var motionBackdropMode: MotionBackdropMode = .sakura
    var motionTileMaterial: MotionTileMaterial = .frosted
    var motionSpeed = 1.0
    var motionIntensity = 1.0
    var motionIsPaused = false
    var calendarClientID = ""
    var selectedCalendarIDs: [String] = []
    var calendarConnected = false
    var availableCalendars: [GoogleCalendarInfo] = []
    var calendarEvents: [CalendarEventItem] = []
    var calendarStatus = "Calendar not connected"
    var screenStatus = "XENEON not checked"
    var actionStatus = "Ready"
    /// Session-only mute indicator overlay; intentionally NOT persisted.
    var isMuteOverlayVisible = false
    var automationMeetingEnabled = false
    var automationMeetingLeadMinutes = 5
    var automationMeetingPreset: DashboardPreset = .work
    /// Mirrors SMAppService.mainApp registration; synced from the real status.
    var launchAtLoginEnabled = false
    var webReloadTokens: [UUID: Int] = [:]
    var stats = SystemSnapshot.empty
    var weather = WeatherSnapshot.empty
    var pagesByPreset: [DashboardPreset.RawValue: [DashboardPage]]
    var selectedPageIndexByPreset: [DashboardPreset.RawValue: Int]
    var tiles: [WidgetTile]
    var launchers: [LauncherItem]
    var installedApplications: [InstalledApplication] = []
    var lastDeletedWidget: DeletedWidget?

    @ObservationIgnored private let defaultsKey: String

    @ObservationIgnored weak var dashboardWindow: NSWindow?
    @ObservationIgnored weak var settingsWindow: NSWindow?
    // nonisolated(unsafe) so the nonisolated deinit can cancel them without
    // MainActor.assumeIsolated (which traps if the store deallocates off-main).
    // Task.cancel() is thread-safe; all other access stays on the main actor.
    @ObservationIgnored nonisolated(unsafe) private var tickerTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var statsTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var weatherTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var calendarTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var automationTask: Task<Void, Never>?
    @ObservationIgnored private var dashboardWindowObservers: [NSObjectProtocol] = []
    /// Monotonically increasing token bumped on every refreshCalendarEvents()
    /// launch. A slower earlier fetch can finish after a newer state change
    /// (deselection/disconnect/overlapping fetch); the completion only assigns
    /// calendarEvents when its captured generation still matches, preventing a
    /// stale result from clobbering newer state. Main-actor isolated.
    @ObservationIgnored private var calendarEventsGeneration = 0
    /// Event IDs the meeting automation has already acted on, so each event
    /// triggers a preset switch at most once. Pruned against the current event
    /// list when it grows past 200 entries. Main-actor isolated, not persisted.
    @ObservationIgnored private var handledAutomationEventIDs: Set<String> = []
    /// True from the moment we ask AppKit to toggle native fullscreen until the
    /// matching didEnter/didExitFullScreen notification fires. The styleMask bit
    /// only flips at the END of the ~0.5s animation, so this flag guards the
    /// transition window against overlapping toggles and frame mutations.
    @ObservationIgnored private var isTogglingFullScreen = false

    init(defaultsKey: String = "dashboardProfile.v2") {
        self.defaultsKey = defaultsKey
        // Placeholder values so all stored properties are initialized before
        // apply(profile:) runs; it immediately overwrites them from the profile.
        pagesByPreset = [:]
        selectedPageIndexByPreset = [:]
        tiles = []
        launchers = []
        apply(profile: Self.loadProfile(defaultsKey: defaultsKey))
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Applies a decoded profile to live store state. Shared single code path
    /// for the initial load in init, resetProfile(), and importProfile(from:).
    private func apply(profile: DashboardProfile) {
        let preset = DashboardPreset(rawValue: profile.selectedPreset) ?? .command
        let pages = Self.normalizedPagesByPreset(from: profile, selectedPreset: preset)
        let indexes = Self.normalizedPageIndexes(profile.selectedPageIndexByPreset, pagesByPreset: pages)

        noteText = profile.noteText
        isPinned = profile.isPinned
        launchers = profile.launchers
        selectedPreset = preset
        pagesByPreset = pages
        selectedPageIndexByPreset = indexes
        tiles = Self.activeTiles(
            preset: preset,
            pagesByPreset: pages,
            selectedPageIndexByPreset: indexes
        )
        appearanceMode = EdgeAppearanceMode(rawValue: profile.appearanceMode ?? "") ?? .dark
        showsFullDayForecast = profile.showsFullDayForecast ?? false
        uses24HourTime = profile.uses24HourTime ?? false
        privacyMode = profile.privacyMode ?? false
        forecastRange = ForecastRange(rawValue: profile.forecastRange ?? "") ?? .day
        motionBackdropMode = MotionBackdropMode(rawValue: profile.motionBackdropMode ?? "") ?? MotionBackdropPreferences.default.mode
        motionTileMaterial = MotionTileMaterial(rawValue: profile.motionTileMaterial ?? "") ?? MotionBackdropPreferences.default.tileMaterial
        motionSpeed = Self.clampedMotionSpeed(profile.motionSpeed ?? MotionBackdropPreferences.default.speed)
        motionIntensity = Self.clampedMotionIntensity(profile.motionIntensity ?? MotionBackdropPreferences.default.intensity)
        motionIsPaused = profile.motionIsPaused ?? MotionBackdropPreferences.default.isPaused
        calendarClientID = profile.googleCalendarClientID ?? ""
        selectedCalendarIDs = profile.selectedCalendarIDs ?? []
        calendarConnected = GoogleAuthService.shared.isConnected
        availableCalendars = []
        calendarEvents = []
        calendarStatus = calendarConnected ? "Calendar connected" : "Calendar not connected"
        automationMeetingEnabled = profile.automationMeetingEnabled ?? false
        automationMeetingLeadMinutes = Self.clampedAutomationLeadMinutes(profile.automationMeetingLeadMinutes ?? 5)
        automationMeetingPreset = DashboardPreset(rawValue: profile.automationMeetingPreset ?? "") ?? .work
        focusedTileID = nil
        selectedWidgetID = nil
        lastDeletedWidget = nil
    }

    var enabledTiles: [WidgetTile] {
        let visible = tiles.filter(\.isEnabled)
        if let focusedTileID, let focused = visible.first(where: { $0.id == focusedTileID }) {
            return [focused]
        }
        return visible
    }

    var allVisibleTiles: [WidgetTile] {
        tiles.filter(\.isEnabled)
    }

    /// A crash-proof binding to a tile. Positional bindings ($store.tiles[index])
    /// trap with index-out-of-range when `tiles` shrinks while an inspector view
    /// still holds the binding — SwiftUI appearance actions (onAppear/onDisappear)
    /// can read it mid-teardown after a page/profile switch or widget removal.
    /// Reads look the tile up by id, falling back to the snapshot taken at body
    /// time when it's gone; writes silently no-op once the tile no longer exists.
    func tileBinding(id: WidgetTile.ID, snapshot: WidgetTile) -> Binding<WidgetTile> {
        Binding(
            get: { [weak self] in
                self?.tiles.first(where: { $0.id == id }) ?? snapshot
            },
            set: { [weak self] newValue in
                guard let self, let index = self.tiles.firstIndex(where: { $0.id == id }) else { return }
                self.tiles[index] = newValue
            }
        )
    }

    var selectedTile: WidgetTile? {
        guard let selectedWidgetID else { return nil }
        return tiles.first { $0.id == selectedWidgetID }
    }

    var activePresetTitle: String {
        selectedPreset.title
    }

    var currentPages: [DashboardPage] {
        pagesByPreset[selectedPreset.rawValue] ?? Self.defaultPages(for: selectedPreset)
    }

    var currentPageIndex: Int {
        normalizedSelectedPageIndex(for: selectedPreset)
    }

    var currentPageTitle: String {
        let pages = currentPages
        guard pages.indices.contains(currentPageIndex) else { return "Page 1" }
        return pages[currentPageIndex].title
    }

    var canUndoDeleteWidget: Bool {
        lastDeletedWidget != nil
    }

    var motionBackdropPreferences: MotionBackdropPreferences {
        MotionBackdropPreferences(
            mode: motionBackdropMode,
            tileMaterial: motionTileMaterial,
            speed: motionSpeed,
            intensity: motionIntensity,
            isPaused: motionIsPaused
        )
    }

    func start() {
        guard tickerTask == nil else { return }

        screenStatus = ScreenResolver.targetDescription()

        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.currentTime = Date()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                let next = await SystemStatsReader.snapshot()
                await MainActor.run {
                    self?.stats = next
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }

        weatherTask = Task { [weak self] in
            while !Task.isCancelled {
                let next = await WeatherService.snapshot()
                await MainActor.run {
                    self?.weather = next
                }
                try? await Task.sleep(for: .seconds(600))
            }
        }

        calendarTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self, self.calendarConnected else { return }
                    self.refreshCalendarEvents()
                }
                try? await Task.sleep(for: .seconds(600))
            }
        }

        automationTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.runMeetingAutomationCheck()
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }

        refreshInstalledApplications()
        BLEBatteryScanner.shared.start()
    }

    func stop() {
        tickerTask?.cancel()
        statsTask?.cancel()
        weatherTask?.cancel()
        calendarTask?.cancel()
        automationTask?.cancel()
        tickerTask = nil
        statsTask = nil
        weatherTask = nil
        calendarTask = nil
        automationTask = nil
    }

    deinit {
        // deinit is nonisolated and may run off the main thread (e.g. when the store
        // is released from a background executor, as happens in tests). MainActor.assumeIsolated
        // would trap off-main, so cancel the background tasks directly — Task.cancel() is
        // thread-safe and the object is being destroyed, so nilling them is unnecessary.
        tickerTask?.cancel()
        statsTask?.cancel()
        weatherTask?.cancel()
        calendarTask?.cancel()
        automationTask?.cancel()
    }

    func attachWindow(_ window: NSWindow) {
        guard dashboardWindow !== window else { return }
        dashboardWindow = window
        observeDashboardWindow(window)
        edgeMode = true
        configureWindow()
        placeDashboardWindowOnEdgeSoon()
    }

    func attachSettingsWindow(_ window: NSWindow) {
        guard settingsWindow !== window else { return }
        settingsWindow = window
        configureSettingsWindow()
        moveSettingsToMainDisplay()
    }

    func configureWindow() {
        guard let window = dashboardWindow else { return }
        window.title = "Kira Edge"

        if edgeMode {
            let isNativeFullScreen = window.styleMask.contains(.fullScreen)
            if !window.styleMask.contains(.fullScreen) {
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            }
            window.isMovableByWindowBackground = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.hasShadow = false
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
            window.standardWindowButton(.closeButton)?.isHidden = isNativeFullScreen
            window.standardWindowButton(.miniaturizeButton)?.isHidden = isNativeFullScreen
            window.standardWindowButton(.zoomButton)?.isHidden = isNativeFullScreen
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        } else {
            if window.styleMask.contains(.fullScreen) {
                isTogglingFullScreen = true
                window.toggleFullScreen(nil)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(750))
                    configureWindow()
                }
                return
            }

            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isMovableByWindowBackground = true
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.hasShadow = true
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
            window.standardWindowButton(.closeButton)?.isHidden = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isHidden = false
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }

    func configureSettingsWindow() {
        guard let window = settingsWindow else { return }
        window.title = "Widget Settings"
        window.isMovableByWindowBackground = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        window.styleMask.remove(.fullSizeContentView)
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }

    private func observeDashboardWindow(_ window: NSWindow) {
        for observer in dashboardWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        dashboardWindowObservers.removeAll()

        let notifications: [Notification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        dashboardWindowObservers = notifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isTogglingFullScreen = false
                    self?.configureWindow()
                }
            }
        }
    }

    func placeSettingsWindowOnMainDisplaySoon() {
        Task { @MainActor in
            moveSettingsToMainDisplay()
            try? await Task.sleep(for: .milliseconds(180))
            moveSettingsToMainDisplay()
        }
    }

    func placeDashboardWindowOnEdgeSoon(activate: Bool = false) {
        Task { @MainActor in
            moveDashboardToEdge(activate: activate, enterFullScreen: false)
            try? await Task.sleep(for: .milliseconds(220))
            moveDashboardToEdge(activate: activate, enterFullScreen: false)
            try? await Task.sleep(for: .milliseconds(260))
            enterDashboardNativeFullScreen()
        }
    }

    func moveSettingsToMainDisplay() {
        guard let window = settingsWindow else { return }
        configureSettingsWindow()

        guard let screen = ScreenResolver.primaryWorkScreen() else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let visible = screen.visibleFrame
        let maxWidth = max(720, visible.width - 80)
        let maxHeight = max(520, visible.height - 80)
        let size = NSSize(
            width: min(max(window.frame.width, 980), maxWidth),
            height: min(max(window.frame.height, 660), maxHeight)
        )
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )

        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func moveToEdge() {
        moveDashboardToEdge(activate: true, enterFullScreen: true)
    }

    @discardableResult
    private func moveDashboardToEdge(activate: Bool, enterFullScreen: Bool) -> Bool {
        guard let window = dashboardWindow else { return false }
        guard let screen = ScreenResolver.xeneonScreen() else {
            screenStatus = "XENEON EDGE display not found"
            return false
        }

        edgeMode = true
        focusedTileID = nil

        // Never rewrite styleMask or force a windowed frame while AppKit owns the
        // window for fullscreen (already fullscreen, or a toggle is animating).
        // Doing so corrupts/aborts the transition and produces missized geometry.
        let isFullScreenOwned = window.styleMask.contains(.fullScreen) || isTogglingFullScreen
        if !isFullScreenOwned {
            configureWindow()
            window.setFrame(screen.frame, display: true, animate: false)
        }
        if activate {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFront(nil)
        }
        screenStatus = "On \(screen.localizedName)"
        if enterFullScreen {
            enterDashboardNativeFullScreen()
        }
        return true
    }

    func exitEdgeMode() {
        guard let window = dashboardWindow else { return }
        if window.styleMask.contains(.fullScreen) {
            isTogglingFullScreen = true
            window.toggleFullScreen(nil)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                moveDashboardToControlsWindow()
            }
            return
        }

        moveDashboardToControlsWindow()
    }

    private func enterDashboardNativeFullScreen() {
        guard edgeMode, let window = dashboardWindow else { return }
        // The styleMask bit only flips at the end of the enter animation, so it
        // is not enough on its own: also bail while a previous toggle is still
        // animating, otherwise a second toggleFullScreen queues an EXIT.
        guard !isTogglingFullScreen else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        guard ScreenResolver.window(window, isOn: ScreenResolver.xeneonScreen()) else { return }

        window.collectionBehavior = [.fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isTogglingFullScreen = true
        window.toggleFullScreen(nil)
    }

    private func moveDashboardToControlsWindow() {
        guard let window = dashboardWindow else { return }
        edgeMode = false
        focusedTileID = nil
        configureWindow()

        let preferredSize = NSSize(width: 1240, height: 760)
        guard let screen = ScreenResolver.primaryWorkScreen() else {
            window.setContentSize(preferredSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let visible = screen.visibleFrame
        let size = NSSize(
            width: min(preferredSize.width, max(720, visible.width - 80)),
            height: min(preferredSize.height, max(520, visible.height - 80))
        )
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectPage(at index: Int) {
        let pages = normalizedPages(for: selectedPreset)
        guard pages.indices.contains(index) else { return }

        commitTilesToActivePage()
        selectedPageIndexByPreset[selectedPreset.rawValue] = index
        tiles = pages[index].tiles
        selectedWidgetID = nil
        focusedTileID = nil
        actionStatus = "\(selectedPreset.title) \(pages[index].title)"
        persist()
    }

    func addPage() {
        commitTilesToActivePage()
        var pages = normalizedPages(for: selectedPreset)
        let nextNumber = pages.count + 1
        let page = DashboardPage(title: "Page \(nextNumber)", tiles: [])
        pages.append(page)
        pagesByPreset[selectedPreset.rawValue] = pages
        selectedPageIndexByPreset[selectedPreset.rawValue] = pages.count - 1
        tiles = []
        selectedWidgetID = nil
        focusedTileID = nil
        actionStatus = "Added \(page.title)"
        persist()
    }

    func duplicateCurrentPage() {
        commitTilesToActivePage()
        var pages = normalizedPages(for: selectedPreset)
        let index = normalizedSelectedPageIndex(for: selectedPreset)
        guard pages.indices.contains(index) else { return }

        let source = pages[index]
        let duplicatedTiles = source.tiles.map { tile in
            var copy = tile
            copy.id = UUID()
            return copy
        }
        let page = DashboardPage(title: "\(source.title) Copy", tiles: duplicatedTiles)
        pages.insert(page, at: index + 1)
        pagesByPreset[selectedPreset.rawValue] = pages
        selectedPageIndexByPreset[selectedPreset.rawValue] = index + 1
        tiles = page.tiles
        selectedWidgetID = nil
        focusedTileID = nil
        actionStatus = "Duplicated \(source.title)"
        persist()
    }

    func removeCurrentPage() {
        var pages = normalizedPages(for: selectedPreset)
        guard pages.count > 1 else {
            actionStatus = "Keep at least one page"
            return
        }

        let index = normalizedSelectedPageIndex(for: selectedPreset)
        let removed = pages.remove(at: index)
        let nextIndex = min(index, pages.count - 1)
        pagesByPreset[selectedPreset.rawValue] = pages
        selectedPageIndexByPreset[selectedPreset.rawValue] = nextIndex
        tiles = pages[nextIndex].tiles
        selectedWidgetID = nil
        focusedTileID = nil
        lastDeletedWidget = nil
        actionStatus = "Removed \(removed.title)"
        persist()
    }

    func selectNextPage() {
        let pages = currentPages
        guard pages.count > 1 else { return }
        selectPage(at: (currentPageIndex + 1) % pages.count)
    }

    func selectPreviousPage() {
        let pages = currentPages
        guard pages.count > 1 else { return }
        selectPage(at: (currentPageIndex - 1 + pages.count) % pages.count)
    }

    func toggleWidget(_ tile: WidgetTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index].isEnabled.toggle()
        // Disabling the focused tile must clear focus, mirroring closeWidget(_:),
        // otherwise focus chevrons keep showing for a tile that is no longer visible.
        if !tiles[index].isEnabled {
            if focusedTileID == tile.id {
                focusedTileID = nil
            }
            if selectedWidgetID == tile.id {
                selectedWidgetID = nil
            }
        }
        persist()
    }

    func selectWidget(_ tile: WidgetTile) {
        selectedWidgetID = tile.id
    }

    func closeWidget(_ tile: WidgetTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index].isEnabled = false
        if focusedTileID == tile.id {
            focusedTileID = nil
        }
        if selectedWidgetID == tile.id {
            selectedWidgetID = nil
        }
        actionStatus = "Closed \(tile.displayTitle)"
        persist()
    }

    func moveWidget(_ tile: WidgetTile, offset: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let newIndex = max(0, min(tiles.count - 1, index + offset))
        guard newIndex != index else { return }
        let item = tiles.remove(at: index)
        tiles.insert(item, at: newIndex)
        actionStatus = "Moved \(tile.displayTitle)"
        persist()
    }

    func resizeWidget(_ tile: WidgetTile, delta: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let sizes = WidgetSize.allCases
        guard let current = sizes.firstIndex(of: tiles[index].size) else { return }
        let next = max(0, min(sizes.count - 1, current + delta))
        tiles[index].size = sizes[next]
        actionStatus = "\(tile.displayTitle) size: \(sizes[next].rawValue.capitalized)"
        persist()
    }

    func cycleAccent(_ tile: WidgetTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let accents = WidgetAccent.allCases
        guard let current = accents.firstIndex(of: tiles[index].accent) else { return }
        tiles[index].accent = accents[(current + 1) % accents.count]
        persist()
    }

    func moveTile(from source: IndexSet, to destination: Int) {
        tiles.move(fromOffsets: source, toOffset: destination)
        actionStatus = "Reordered widgets"
        persist()
    }

    func moveTile(id sourceID: WidgetTile.ID, before targetID: WidgetTile.ID) {
        guard sourceID != targetID else { return }
        guard let sourceIndex = tiles.firstIndex(where: { $0.id == sourceID }) else { return }
        guard let targetIndex = tiles.firstIndex(where: { $0.id == targetID }) else { return }

        let item = tiles.remove(at: sourceIndex)
        let adjustedTarget = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
        tiles.insert(item, at: adjustedTarget)
        actionStatus = "Reordered widgets"
        persist()
    }

    func moveTileToEnd(id sourceID: WidgetTile.ID) {
        guard let sourceIndex = tiles.firstIndex(where: { $0.id == sourceID }) else { return }
        let item = tiles.remove(at: sourceIndex)
        tiles.append(item)
        actionStatus = "Reordered widgets"
        persist()
    }

    func openLauncher(_ item: LauncherItem) {
        LauncherService.openApplication(named: item.appName)
        actionStatus = "Opened \(item.title)"
    }

    func focusTile(_ tile: WidgetTile) {
        focusedTileID = focusedTileID == tile.id ? nil : tile.id
    }

    func focusNextWidget() {
        focusWidget(offset: 1)
    }

    func focusPreviousWidget() {
        focusWidget(offset: -1)
    }

    func clearFocus() {
        focusedTileID = nil
        actionStatus = "Showing all widgets"
    }

    func reloadWebTile(_ tile: WidgetTile) {
        webReloadTokens[tile.id, default: 0] += 1
        actionStatus = "Reloaded \(tile.displayTitle)"
    }

    func reloadAllWebTiles() {
        let webTiles = tiles.filter { $0.kind == .web }
        guard !webTiles.isEmpty else {
            actionStatus = "No web widgets to reload"
            return
        }

        for tile in webTiles {
            webReloadTokens[tile.id, default: 0] += 1
        }
        actionStatus = "Reloaded \(webTiles.count) web widgets"
    }

    func openWebTileExternally(_ tile: WidgetTile) {
        guard let url = tile.web?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func updateTile(_ tile: WidgetTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index] = tile
        persist()
    }

    func removeTile(_ tile: WidgetTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let currentPage = normalizedPages(for: selectedPreset)[normalizedSelectedPageIndex(for: selectedPreset)]
        lastDeletedWidget = DeletedWidget(
            tile: tile,
            index: index,
            preset: selectedPreset,
            pageID: currentPage.id
        )
        tiles.remove(at: index)
        if focusedTileID == tile.id {
            focusedTileID = nil
        }
        if selectedWidgetID == tile.id {
            selectedWidgetID = nil
        }
        actionStatus = "Deleted \(tile.displayTitle)"
        persist()
    }

    func undoDeleteWidget() {
        guard let deleted = lastDeletedWidget else {
            actionStatus = "Nothing to undo"
            return
        }

        commitTilesToActivePage()
        var pages = normalizedPages(for: deleted.preset)
        guard let pageIndex = pages.firstIndex(where: { $0.id == deleted.pageID }) else {
            lastDeletedWidget = nil
            actionStatus = "Deleted page is gone"
            return
        }

        let insertIndex = min(max(deleted.index, 0), pages[pageIndex].tiles.count)
        pages[pageIndex].tiles.insert(deleted.tile, at: insertIndex)
        pagesByPreset[deleted.preset.rawValue] = pages
        lastDeletedWidget = nil

        if deleted.preset == selectedPreset && pageIndex == normalizedSelectedPageIndex(for: selectedPreset) {
            tiles = pages[pageIndex].tiles
            selectedWidgetID = deleted.tile.id
        }

        actionStatus = "Restored \(deleted.tile.displayTitle)"
        persist()
    }

    func addTile(_ tile: WidgetTile) {
        tiles.append(tile)
        selectedWidgetID = tile.id
        actionStatus = "Added \(tile.displayTitle)"
        persist()
    }

    func addWebTile(title: String, urlString: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanURL.isEmpty else {
            actionStatus = "Add a title and URL first"
            return
        }

        tiles.append(
            WidgetTile(
                kind: .web,
                title: cleanTitle,
                size: .wide,
                accent: .cyan,
                web: WebTileConfig(title: cleanTitle, urlString: cleanURL)
            )
        )
        actionStatus = "Added \(cleanTitle)"
        persist()
    }

    func applyPreset(_ preset: DashboardPreset) {
        commitTilesToActivePage()
        selectedPreset = preset
        focusedTileID = nil
        selectedWidgetID = nil
        let pages = normalizedPages(for: preset)
        let pageIndex = normalizedSelectedPageIndex(for: preset)
        tiles = pages[pageIndex].tiles
        actionStatus = "\(preset.title) \(pages[pageIndex].title) loaded"
        persist()
    }

    func applyNextPreset() {
        let presets = DashboardPreset.allCases
        guard let index = presets.firstIndex(of: selectedPreset) else {
            applyPreset(.command)
            return
        }

        applyPreset(presets[(index + 1) % presets.count])
    }

    func setAppearanceMode(_ mode: EdgeAppearanceMode) {
        appearanceMode = mode
        actionStatus = "\(mode.title) mode"
        persist()
    }

    func setMotionBackdropMode(_ mode: MotionBackdropMode) {
        motionBackdropMode = mode
        actionStatus = mode.title
        persist()
    }

    func setMotionTileMaterial(_ material: MotionTileMaterial) {
        motionTileMaterial = material
        actionStatus = "\(material.title) tiles"
        persist()
    }

    func setMotionSpeed(_ speed: Double) {
        motionSpeed = Self.clampedMotionSpeed(speed)
        persist()
    }

    func setMotionIntensity(_ intensity: Double) {
        motionIntensity = Self.clampedMotionIntensity(intensity)
        persist()
    }

    func setMotionPaused(_ isPaused: Bool) {
        motionIsPaused = isPaused
        actionStatus = isPaused ? "Motion paused" : "Motion live"
        persist()
    }

    func toggleFullDayForecast() {
        showsFullDayForecast.toggle()
        actionStatus = showsFullDayForecast ? "Full forecast" : "Compact weather"
        persist()
    }

    func setUses24HourTime(_ value: Bool) {
        uses24HourTime = value
        persist()
    }

    func setPrivacyMode(_ value: Bool) {
        privacyMode = value
        persist()
    }

    func setForecastRange(_ range: ForecastRange) {
        forecastRange = range
        persist()
    }

    func resetProfile() {
        apply(profile: Self.defaultProfile())
        actionStatus = "Profile reset"
        persist()
    }

    // MARK: - Profile export / import

    /// The full current state as a shareable, pretty-printed JSON profile.
    func exportProfileData() throws -> Data {
        commitTilesToActivePage()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(currentProfile())
    }

    /// Decodes a profile (the tolerant custom Codable degrades junk fields to
    /// defaults) and applies it through the same path as init/resetProfile.
    /// Because that decoder accepts ANY JSON object, the payload is validated
    /// first so a wrong file pick throws instead of wiping the dashboard.
    func importProfile(from data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["selectedPreset"] != nil
        else {
            throw ProfileImportError()
        }
        let profile = try JSONDecoder().decode(DashboardProfile.self, from: data)
        let hasPageContent = profile.pagesByPreset?.values.contains(where: { !$0.isEmpty }) ?? false
        guard !profile.tiles.isEmpty || hasPageContent else {
            throw ProfileImportError()
        }
        apply(profile: profile)
        actionStatus = "Profile imported"
        persist()
        // apply() cleared availableCalendars/calendarEvents and the 600s
        // calendar loop may be mid-sleep; refresh now (which chains into
        // refreshCalendarEvents) so calendar widgets, the inspector checklist,
        // and meeting automation resume immediately.
        if calendarConnected {
            refreshAvailableCalendars()
        }
    }

    // MARK: - Mute overlay

    func setMuteOverlay(_ visible: Bool) {
        isMuteOverlayVisible = visible
        actionStatus = visible ? "Muted" : "Unmuted"
    }

    func toggleMuteOverlay() {
        setMuteOverlay(!isMuteOverlayVisible)
    }

    // MARK: - Meeting automation

    func setAutomationMeetingEnabled(_ enabled: Bool) {
        automationMeetingEnabled = enabled
        actionStatus = enabled ? "Meeting automation on" : "Meeting automation off"
        persist()
    }

    func setAutomationMeetingLeadMinutes(_ minutes: Int) {
        automationMeetingLeadMinutes = Self.clampedAutomationLeadMinutes(minutes)
        persist()
    }

    func setAutomationMeetingPreset(_ preset: DashboardPreset) {
        automationMeetingPreset = preset
        persist()
    }

    /// One tick of the meeting automation: when enabled and the calendar is
    /// connected, find the first not-yet-handled timed event starting within
    /// the lead window (tolerating starts up to 60s in the past so a tick just
    /// after the start time still catches it) and switch to the meeting preset.
    private func runMeetingAutomationCheck() {
        guard automationMeetingEnabled, calendarConnected else { return }

        let now = Date()
        let windowEnd = now.addingTimeInterval(TimeInterval(automationMeetingLeadMinutes * 60))
        guard let event = calendarEvents.first(where: { event in
            !event.isAllDay
                && event.start > now.addingTimeInterval(-60)
                && event.start <= windowEnd
                && !handledAutomationEventIDs.contains(event.id)
        }) else { return }

        handledAutomationEventIDs.insert(event.id)
        if handledAutomationEventIDs.count > 200 {
            // Keep only ids for events still in the fetched window (which
            // includes the one just handled); everything older is stale.
            handledAutomationEventIDs.formIntersection(Set(calendarEvents.map(\.id)))
        }

        if selectedPreset != automationMeetingPreset {
            applyPreset(automationMeetingPreset)
            actionStatus = "Meeting soon — switched to \(automationMeetingPreset.title)"
        }
    }

    private static func clampedAutomationLeadMinutes(_ value: Int) -> Int {
        min(max(value, 1), 30)
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            actionStatus = launchAtLoginEnabled ? "Launch at login on" : "Launch at login off"
        } catch {
            // Reflect the real registration state, not the requested one.
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            actionStatus = "Launch at login failed: \(error.localizedDescription)"
        }
    }

    func addLauncher(title: String, appName: String, symbolName: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSymbol = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty, !cleanApp.isEmpty else {
            actionStatus = "Add a launcher title and app"
            return
        }

        launchers.append(
            LauncherItem(
                title: cleanTitle,
                appName: cleanApp,
                symbolName: cleanSymbol.isEmpty ? "app" : cleanSymbol
            )
        )
        actionStatus = "Added \(cleanTitle)"
        persist()
    }

    func removeLauncher(_ item: LauncherItem) {
        guard let index = launchers.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = launchers.remove(at: index)
        actionStatus = "Removed \(removed.title)"
        persist()
    }

    func moveLauncher(_ item: LauncherItem, offset: Int) {
        guard let index = launchers.firstIndex(where: { $0.id == item.id }) else { return }
        let newIndex = max(0, min(launchers.count - 1, index + offset))
        guard newIndex != index else { return }

        let launcher = launchers.remove(at: index)
        launchers.insert(launcher, at: newIndex)
        actionStatus = "Moved \(launcher.title)"
        persist()
    }

    func moveLauncher(id sourceID: LauncherItem.ID, before targetID: LauncherItem.ID) {
        guard sourceID != targetID else { return }
        guard let sourceIndex = launchers.firstIndex(where: { $0.id == sourceID }) else { return }
        guard let targetIndex = launchers.firstIndex(where: { $0.id == targetID }) else { return }

        let item = launchers.remove(at: sourceIndex)
        let adjustedTarget = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
        launchers.insert(item, at: adjustedTarget)
        actionStatus = "Reordered launcher"
        persist()
    }

    func moveLauncherToEnd(id sourceID: LauncherItem.ID) {
        guard let sourceIndex = launchers.firstIndex(where: { $0.id == sourceID }) else { return }
        let item = launchers.remove(at: sourceIndex)
        launchers.append(item)
        actionStatus = "Reordered launcher"
        persist()
    }

    func refreshInstalledApplications() {
        Task { [weak self] in
            let apps = await Task.detached(priority: .utility) {
                LauncherService.installedApplications()
            }.value
            await MainActor.run {
                self?.installedApplications = apps
            }
        }
    }

    // MARK: - Google Calendar

    func setCalendarClientID(_ clientID: String) {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != calendarClientID else { return }
        calendarClientID = trimmed
        persist()
    }

    /// The Client ID to use for sign-in: a per-user custom one if set, else the
    /// app-bundled default so end users can connect with one click.
    var effectiveCalendarClientID: String {
        calendarClientID.isEmpty ? GoogleAuthService.bundledClientID : calendarClientID
    }

    func connectGoogleCalendar() {
        let clientID = effectiveCalendarClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            calendarStatus = "Add a Google OAuth Client ID in Advanced first"
            return
        }

        calendarStatus = "Connecting to Google…"
        let anchor = settingsWindow
        Task { [weak self] in
            do {
                try await GoogleAuthService.shared.connect(clientID: clientID, presentationAnchor: anchor)
                await MainActor.run {
                    guard let self else { return }
                    self.calendarConnected = true
                    self.calendarStatus = "Calendar connected"
                }
                self?.refreshAvailableCalendars()
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.calendarConnected = GoogleAuthService.shared.isConnected
                    self.calendarStatus = "Connect failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func disconnectGoogleCalendar() {
        GoogleAuthService.shared.disconnect()
        calendarConnected = false
        availableCalendars = []
        calendarEvents = []
        calendarStatus = "Calendar not connected"
    }

    func refreshAvailableCalendars() {
        guard calendarConnected else { return }
        Task { [weak self] in
            do {
                let token = try await GoogleAuthService.shared.validAccessToken()
                let calendars = try await GoogleCalendarService.listCalendars(accessToken: token)
                await MainActor.run {
                    guard let self else { return }
                    self.availableCalendars = calendars
                    self.calendarStatus = "\(calendars.count) calendars available"
                }
                self?.refreshCalendarEvents()
            } catch {
                await MainActor.run {
                    self?.calendarStatus = "Calendar load failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleCalendarSelected(_ id: String) {
        if let index = selectedCalendarIDs.firstIndex(of: id) {
            selectedCalendarIDs.remove(at: index)
        } else {
            selectedCalendarIDs.append(id)
        }
        persist()
        refreshCalendarEvents()
    }

    func refreshCalendarEvents() {
        // Bump the generation first so any in-flight fetch from a previous call
        // is invalidated and cannot clobber the state we set below or the result
        // of a newer fetch.
        calendarEventsGeneration &+= 1
        let generation = calendarEventsGeneration

        guard calendarConnected, !selectedCalendarIDs.isEmpty else {
            calendarEvents = []
            return
        }

        let calendarIDs = selectedCalendarIDs
        // Fetch from the start of today out ~5 weeks so the month grid can
        // show event dots for the whole visible grid, not just the next week.
        let from = Calendar.current.startOfDay(for: Date())
        let to = from.addingTimeInterval(35 * 24 * 60 * 60)
        Task { [weak self] in
            do {
                let token = try await GoogleAuthService.shared.validAccessToken()
                let events = try await GoogleCalendarService.events(
                    accessToken: token,
                    calendarIDs: calendarIDs,
                    from: from,
                    to: to
                )
                await MainActor.run {
                    guard let self else { return }
                    // Ignore a stale result: a newer refresh (or a deselection/
                    // disconnect) has happened since this fetch launched, or the
                    // calendar is no longer connected/selected.
                    guard self.calendarEventsGeneration == generation,
                          self.calendarConnected,
                          !self.selectedCalendarIDs.isEmpty else { return }
                    self.calendarEvents = events
                }
            } catch {
                await MainActor.run {
                    self?.calendarStatus = "Events load failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func persist() {
        commitTilesToActivePage()
        guard let data = try? JSONEncoder().encode(currentProfile()) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// Snapshot of the live store state as a DashboardProfile. Shared by
    /// persist() and exportProfileData(); callers that need the active page's
    /// tiles reflected must call commitTilesToActivePage() first.
    private func currentProfile() -> DashboardProfile {
        DashboardProfile(
            noteText: noteText,
            isPinned: isPinned,
            tiles: tiles,
            launchers: launchers,
            selectedPreset: selectedPreset.rawValue,
            pagesByPreset: pagesByPreset,
            selectedPageIndexByPreset: selectedPageIndexByPreset,
            appearanceMode: appearanceMode.rawValue,
            showsFullDayForecast: showsFullDayForecast,
            motionBackdropMode: motionBackdropMode.rawValue,
            motionTileMaterial: motionTileMaterial.rawValue,
            motionSpeed: motionSpeed,
            motionIntensity: motionIntensity,
            motionIsPaused: motionIsPaused,
            googleCalendarClientID: calendarClientID.isEmpty ? nil : calendarClientID,
            selectedCalendarIDs: selectedCalendarIDs.isEmpty ? nil : selectedCalendarIDs,
            uses24HourTime: uses24HourTime,
            forecastRange: forecastRange.rawValue,
            automationMeetingEnabled: automationMeetingEnabled,
            automationMeetingLeadMinutes: automationMeetingLeadMinutes,
            automationMeetingPreset: automationMeetingPreset.rawValue,
            privacyMode: privacyMode
        )
    }

    private static func loadProfile(defaultsKey: String) -> DashboardProfile {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let profile = try? JSONDecoder().decode(DashboardProfile.self, from: data),
            Self.hasSavedLayout(profile)
        else {
            return defaultProfile()
        }

        return profile
    }

    private static func defaultProfile() -> DashboardProfile {
        DashboardProfile(
            noteText: "Ready",
            isPinned: true,
            tiles: commandTiles(),
            launchers: [
                LauncherItem(title: "Finder", appName: "Finder", symbolName: "folder"),
                LauncherItem(title: "Music", appName: "Music", symbolName: "music.note"),
                LauncherItem(title: "Safari", appName: "Safari", symbolName: "safari"),
                LauncherItem(title: "Codex", appName: "Codex", symbolName: "terminal")
            ],
            selectedPreset: DashboardPreset.command.rawValue,
            pagesByPreset: defaultPagesByPreset(),
            selectedPageIndexByPreset: DashboardPreset.allCases.reduce(into: [:]) { indexes, preset in
                indexes[preset.rawValue] = 0
            },
            appearanceMode: EdgeAppearanceMode.dark.rawValue,
            showsFullDayForecast: false,
            motionBackdropMode: MotionBackdropPreferences.default.mode.rawValue,
            motionTileMaterial: MotionBackdropPreferences.default.tileMaterial.rawValue,
            motionSpeed: MotionBackdropPreferences.default.speed,
            motionIntensity: MotionBackdropPreferences.default.intensity,
            motionIsPaused: MotionBackdropPreferences.default.isPaused
        )
    }

    private func focusWidget(offset: Int) {
        let visible = allVisibleTiles
        guard !visible.isEmpty else {
            focusedTileID = nil
            return
        }

        let currentIndex = focusedTileID.flatMap { focusedID in
            visible.firstIndex { $0.id == focusedID }
        } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (currentIndex + offset + visible.count) % visible.count
        focusedTileID = visible[nextIndex].id
        actionStatus = "Focused \(visible[nextIndex].displayTitle)"
    }

    private func normalizedPages(for preset: DashboardPreset) -> [DashboardPage] {
        let pages = pagesByPreset[preset.rawValue] ?? Self.defaultPages(for: preset)
        return pages.isEmpty ? Self.defaultPages(for: preset) : pages
    }

    private func normalizedSelectedPageIndex(for preset: DashboardPreset) -> Int {
        let pages = normalizedPages(for: preset)
        let index = selectedPageIndexByPreset[preset.rawValue] ?? 0
        return min(max(index, 0), max(pages.count - 1, 0))
    }

    private func commitTilesToActivePage() {
        var pages = normalizedPages(for: selectedPreset)
        let index = normalizedSelectedPageIndex(for: selectedPreset)
        guard pages.indices.contains(index) else { return }

        pages[index].tiles = tiles
        pagesByPreset[selectedPreset.rawValue] = pages
        selectedPageIndexByPreset[selectedPreset.rawValue] = index
    }

    private static func hasSavedLayout(_ profile: DashboardProfile) -> Bool {
        if !profile.tiles.isEmpty { return true }
        return profile.pagesByPreset?.values.contains { !$0.isEmpty } == true
    }

    private static func normalizedPagesByPreset(
        from profile: DashboardProfile,
        selectedPreset: DashboardPreset
    ) -> [DashboardPreset.RawValue: [DashboardPage]] {
        var pagesByPreset = defaultPagesByPreset()

        if let savedPages = profile.pagesByPreset {
            for preset in DashboardPreset.allCases {
                if let pages = savedPages[preset.rawValue], !pages.isEmpty {
                    pagesByPreset[preset.rawValue] = normalizedTitles(for: pages)
                }
            }
        } else if !profile.tiles.isEmpty {
            pagesByPreset[selectedPreset.rawValue] = [
                DashboardPage(title: "Page 1", tiles: profile.tiles)
            ]
        }

        return pagesByPreset
    }

    private static func normalizedPageIndexes(
        _ savedIndexes: [DashboardPreset.RawValue: Int]?,
        pagesByPreset: [DashboardPreset.RawValue: [DashboardPage]]
    ) -> [DashboardPreset.RawValue: Int] {
        DashboardPreset.allCases.reduce(into: [:]) { indexes, preset in
            let pages = pagesByPreset[preset.rawValue] ?? defaultPages(for: preset)
            let savedIndex = savedIndexes?[preset.rawValue] ?? 0
            indexes[preset.rawValue] = min(max(savedIndex, 0), max(pages.count - 1, 0))
        }
    }

    private static func activeTiles(
        preset: DashboardPreset,
        pagesByPreset: [DashboardPreset.RawValue: [DashboardPage]],
        selectedPageIndexByPreset: [DashboardPreset.RawValue: Int]
    ) -> [WidgetTile] {
        let pages = pagesByPreset[preset.rawValue] ?? defaultPages(for: preset)
        let index = min(
            max(selectedPageIndexByPreset[preset.rawValue] ?? 0, 0),
            max(pages.count - 1, 0)
        )
        guard pages.indices.contains(index) else { return [] }
        return pages[index].tiles
    }

    private static func defaultPagesByPreset() -> [DashboardPreset.RawValue: [DashboardPage]] {
        DashboardPreset.allCases.reduce(into: [:]) { pagesByPreset, preset in
            pagesByPreset[preset.rawValue] = defaultPages(for: preset)
        }
    }

    private static func defaultPages(for preset: DashboardPreset) -> [DashboardPage] {
        [DashboardPage(title: "Page 1", tiles: defaultTiles(for: preset))]
    }

    private static func normalizedTitles(for pages: [DashboardPage]) -> [DashboardPage] {
        pages.enumerated().map { index, page in
            var page = page
            if page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                page.title = "Page \(index + 1)"
            }
            return page
        }
    }

    private static func defaultTiles(for preset: DashboardPreset) -> [WidgetTile] {
        switch preset {
        case .command:
            commandTiles()
        case .media:
            mediaTiles()
        case .work:
            workTiles()
        case .streaming:
            streamingTiles()
        case .aiOps:
            aiOpsTiles()
        case .home:
            homeTiles()
        }
    }

    private static func clampedMotionSpeed(_ value: Double) -> Double {
        min(max(value, 0.3), 2.0)
    }

    private static func clampedMotionIntensity(_ value: Double) -> Double {
        min(max(value, 0.4), 1.4)
    }

    private static func commandTiles() -> [WidgetTile] {
        [
            WidgetTile(kind: .clock, size: .standard, accent: .coral),
            WidgetTile(kind: .system, size: .wide, accent: .cyan),
            WidgetTile(
                kind: .web,
                title: "Home",
                size: .wide,
                accent: .green,
                web: WebTileConfig(title: "Home", urlString: "https://www.google.com", zoom: 0.75)
            ),
            WidgetTile(kind: .launcher, size: .wide, accent: .amber),
            WidgetTile(kind: .note, size: .standard, accent: .violet)
        ]
    }

    private static func mediaTiles() -> [WidgetTile] {
        [
            WidgetTile(
                kind: .web,
                title: "YouTube Mobile",
                size: .wide,
                accent: .coral,
                web: WebTileConfig(title: "YouTube Mobile", urlString: "https://m.youtube.com", zoom: 0.78)
            ),
            WidgetTile(
                kind: .web,
                title: "Plex",
                size: .wide,
                accent: .amber,
                web: WebTileConfig(title: "Plex", urlString: "https://app.plex.tv", zoom: 0.75)
            ),
            WidgetTile(kind: .system, size: .standard, accent: .green),
            WidgetTile(kind: .launcher, size: .standard, accent: .violet)
        ]
    }

    private static func workTiles() -> [WidgetTile] {
        [
            WidgetTile(
                kind: .web,
                title: "ChatGPT",
                size: .wide,
                accent: .green,
                web: WebTileConfig(title: "ChatGPT", urlString: "https://chatgpt.com", zoom: 0.75)
            ),
            WidgetTile(
                kind: .web,
                title: "Calendar",
                size: .wide,
                accent: .cyan,
                web: WebTileConfig(title: "Calendar", urlString: "https://calendar.google.com", zoom: 0.72)
            ),
            WidgetTile(kind: .launcher, size: .standard, accent: .amber),
            WidgetTile(kind: .system, size: .standard, accent: .violet)
        ]
    }

    private static func streamingTiles() -> [WidgetTile] {
        [
            WidgetTile(
                kind: .web,
                title: "YouTube Studio",
                size: .wide,
                accent: .coral,
                web: WebTileConfig(title: "YouTube Studio", urlString: "https://studio.youtube.com", zoom: 0.68)
            ),
            WidgetTile(
                kind: .web,
                title: "Live Chat",
                size: .wide,
                accent: .violet,
                web: WebTileConfig(title: "Live Chat", urlString: "https://www.youtube.com/live_chat", zoom: 0.72)
            ),
            WidgetTile(kind: .system, size: .compact, accent: .amber),
            WidgetTile(kind: .launcher, size: .standard, accent: .cyan)
        ]
    }

    private static func aiOpsTiles() -> [WidgetTile] {
        [
            WidgetTile(
                kind: .web,
                title: "ChatGPT",
                size: .wide,
                accent: .green,
                web: WebTileConfig(title: "ChatGPT", urlString: "https://chatgpt.com", zoom: 0.72)
            ),
            WidgetTile(
                kind: .web,
                title: "GitHub",
                size: .wide,
                accent: .violet,
                web: WebTileConfig(title: "GitHub", urlString: "https://github.com", zoom: 0.72)
            ),
            WidgetTile(kind: .launcher, size: .standard, accent: .cyan),
            WidgetTile(kind: .system, size: .wide, accent: .amber),
            WidgetTile(kind: .note, size: .standard, accent: .coral)
        ]
    }

    private static func homeTiles() -> [WidgetTile] {
        [
            WidgetTile(
                kind: .web,
                title: "Home Assistant",
                size: .wide,
                accent: .cyan,
                web: WebTileConfig(title: "Home Assistant", urlString: "https://home-assistant.io", zoom: 0.72)
            ),
            WidgetTile(
                kind: .web,
                title: "Weather",
                size: .wide,
                accent: .green,
                web: WebTileConfig(title: "Weather", urlString: "https://weather.com", zoom: 0.68)
            ),
            WidgetTile(
                kind: .web,
                title: "Calendar",
                size: .wide,
                accent: .violet,
                web: WebTileConfig(title: "Calendar", urlString: "https://calendar.google.com", zoom: 0.7)
            ),
            WidgetTile(kind: .clock, size: .standard, accent: .coral),
            WidgetTile(kind: .launcher, size: .standard, accent: .amber)
        ]
    }
}
