import SwiftUI

struct EdgeDashboardView: View {
    @Bindable var store: DashboardStore
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.openWindow) private var openWindow
    @State private var isDrawerVisible = false
    @State private var drawerHideTask: Task<Void, Never>?
    var isPreview = false

    var body: some View {
        GeometryReader { proxy in
            let tiles = store.enabledTiles
            let spacing = max(8, proxy.size.height * 0.025)
            let padding = max(12, proxy.size.height * 0.045)
            let availableWidth = max(1, proxy.size.width - padding * 2 - spacing * CGFloat(max(tiles.count - 1, 0)))
            let availableHeight = max(1, proxy.size.height - padding * 2)
            let totalWeight = max(tiles.reduce(CGFloat(0)) { $0 + $1.size.widthWeight }, 1)
            let unitWidth = availableWidth / totalWeight

            ZStack(alignment: .bottom) {
                HStack(spacing: spacing) {
                    ForEach(tiles) { tile in
                        WidgetTileView(tile: tile, store: store)
                            .frame(width: max(120, unitWidth * tile.size.widthWeight), height: availableHeight)
                    }
                }
                .padding(padding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)

                if isDrawerVisible {
                    EdgeHUDView(store: store) {
                        openSettings()
                    }
                    .padding(.bottom, padding * 0.55)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(80)
                }

                if store.currentPages.count > 1 {
                    EdgePageSwitcherView(store: store)
                        .padding(.leading, padding * 0.55)
                        .padding(.bottom, padding * 0.55)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .zIndex(45)
                }

                // Require the focused tile to actually be visible: disabling a focused
                // widget (via any path) must not leave stray focus chevrons (bug #26).
                if let focusedID = store.focusedTileID,
                   store.allVisibleTiles.contains(where: { $0.id == focusedID }),
                   store.allVisibleTiles.count > 1 {
                    EdgeFocusChevronsView(store: store)
                        .padding(.horizontal, padding * 0.55)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .zIndex(46)
                }

                if !isPreview {
                    EdgeDrawerRevealStrip(
                        isDrawerVisible: isDrawerVisible,
                        reveal: { showDrawerTemporarily(duration: .seconds(5)) },
                        hide: { hideDrawer() }
                    )
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(isDrawerVisible ? 30 : 70)
                }

                if store.isMuteOverlayVisible {
                    EdgeMuteOverlayView {
                        store.setMuteOverlay(false)
                    }
                    .transition(.scale(scale: 1.04).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.88), value: store.isMuteOverlayVisible)
            .background {
                ZStack {
                    DashboardBackground()
                    EdgeMotionBackdropView(preferences: store.motionBackdropPreferences)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
            .environment(\.colorScheme, store.appearanceMode.resolvedColorScheme(system: systemColorScheme))
            .simultaneousGesture(drawerGesture(screenHeight: proxy.size.height))
            .onChange(of: store.selectedPreset) {
                showDrawerTemporarily()
            }
            .onChange(of: store.actionStatus) {
                if store.actionStatus.localizedCaseInsensitiveContains("layout loaded") {
                    showDrawerTemporarily()
                }
            }
            .onDisappear {
                drawerHideTask?.cancel()
            }
        }
    }

    private func openSettings() {
        openWindow(id: "widget-settings")
        store.placeSettingsWindowOnMainDisplaySoon()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func drawerGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                if value.startLocation.y > screenHeight - 96, value.translation.height < -24 {
                    showDrawerTemporarily(duration: .seconds(5))
                } else if isDrawerVisible, value.translation.height > 24 {
                    hideDrawer()
                }
            }
    }

    private func showDrawerTemporarily(duration: Duration = .seconds(3)) {
        guard !isPreview else { return }
        drawerHideTask?.cancel()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            isDrawerVisible = true
        }

        drawerHideTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            hideDrawer()
        }
    }

    private func hideDrawer() {
        drawerHideTask?.cancel()
        drawerHideTask = nil
        withAnimation(.easeOut(duration: 0.18)) {
            isDrawerVisible = false
        }
    }
}

struct EdgeDrawerRevealStrip: View {
    let isDrawerVisible: Bool
    let reveal: () -> Void
    let hide: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if !isDrawerVisible {
                EdgeDrawerHotZone(onReveal: reveal, onHide: hide)
                    .frame(width: 142, height: 72)
                    .contentShape(Rectangle())
            }

            Button {
                if isDrawerVisible {
                    hide()
                } else {
                    reveal()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isDrawerVisible ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .black))
                    Text(isDrawerVisible ? "Hide" : "Menu")
                        .font(EdgeTheme.bodyFont(size: 10, weight: .heavy))
                }
                .foregroundStyle(EdgeTheme.overlayText)
                .frame(width: isDrawerVisible ? 62 : 66, height: 24)
                .background(EdgeTheme.overlayFill, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 7)
        }
        .frame(width: 154, height: 76, alignment: .bottom)
        .contentShape(Rectangle())
    }
}

struct EdgeMuteOverlayView: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.36, green: 0.02, blue: 0.05)
                .opacity(0.92)

            VStack(spacing: 14) {
                HStack(spacing: 34) {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 108, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)

                    Text("MUTED")
                        .font(EdgeTheme.displayFont(size: 120, weight: .heavy))
                        .tracking(6)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
                }

                Text("Tap anywhere to dismiss")
                    .font(EdgeTheme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }
}

struct EdgeFocusChevronsView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        HStack {
            EdgeFloatingCircleButton(symbolName: "chevron.left", helpText: "Previous focused widget") {
                store.focusPreviousWidget()
            }

            Spacer()

            EdgeFloatingCircleButton(symbolName: "chevron.right", helpText: "Next focused widget") {
                store.focusNextWidget()
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(true)
    }
}

struct EdgePageSwitcherView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        HStack(spacing: 7) {
            EdgeMiniPillButton(symbolName: "chevron.left", helpText: "Previous page") {
                store.selectPreviousPage()
            }

            Text("\(store.currentPageIndex + 1)/\(store.currentPages.count)")
                .font(EdgeTheme.bodyFont(size: 11, weight: .black))
                .monospacedDigit()
                .foregroundStyle(EdgeTheme.overlayText)
                .frame(minWidth: 38)

            EdgeMiniPillButton(symbolName: "chevron.right", helpText: "Next page") {
                store.selectNextPage()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(EdgeTheme.overlayFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 12, y: 4)
    }
}

struct EdgeFloatingCircleButton: View {
    let symbolName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .black))
                .frame(width: 48, height: 62)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(EdgeTheme.overlayText)
        .background(EdgeTheme.overlayFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 16, y: 6)
        .help(helpText)
    }
}

struct EdgeMiniPillButton: View {
    let symbolName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .black))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(EdgeTheme.overlayText)
        .background(EdgeTheme.overlaySubtleFill, in: Circle())
        .help(helpText)
    }
}

struct DashboardBackground: View {
    var body: some View {
        GeometryReader { proxy in
            EdgeTheme.background
            LinearGradient(
                colors: [
                    EdgeTheme.backgroundBandA,
                    EdgeTheme.backgroundBandB,
                    EdgeTheme.backgroundBandC
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            RadialGradient(
                colors: [Color(nsColor: NSColor(hex: 0xFF9DBB, alpha: 0.24)), .clear],
                center: UnitPoint(x: 0.11, y: -0.10),
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.46
            )
            .blendMode(.screen)
            RadialGradient(
                colors: [Color(nsColor: NSColor(hex: 0x7CD7FF, alpha: 0.20)), .clear],
                center: UnitPoint(x: 0.93, y: 1.12),
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.48
            )
            .blendMode(.screen)
            RadialGradient(
                colors: [Color(nsColor: NSColor(hex: 0xC4A8FF, alpha: 0.10)), .clear],
                center: .center,
                startRadius: 0,
                endRadius: max(proxy.size.width, proxy.size.height) * 0.56
            )
            .blendMode(.screen)
            HStack(spacing: 0) {
                Color.white.opacity(0.045)
                Color.clear
                Color.black.opacity(0.055)
            }
        }
        .ignoresSafeArea()
    }
}

struct WidgetTileView: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    IconChip(symbolName: tile.kind.symbolName, accent: tile.accentColor)

                    Text(tile.displayTitle.uppercased())
                        .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                        .tracking(1.65)
                        .foregroundStyle(EdgeTheme.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if store.isEditingWidgets {
                        TileControlsView(tile: tile, store: store)
                    } else if store.focusedTileID == tile.id {
                        FocusedTileHeaderControls(tile: tile, store: store)
                    } else if tile.kind == .web {
                        WebTileHeaderControls(tile: tile, store: store)
                    }
                }
                .frame(minHeight: 38)
                .zIndex(10)

                Group {
                    switch tile.kind {
                    case .clock:
                        ClockWidgetView(
                            date: store.currentTime,
                            weather: store.weather,
                            showsFullDayForecast: store.showsFullDayForecast,
                            use24Hour: store.uses24HourTime,
                            forecastRange: store.forecastRange,
                            accent: tile.accentColor,
                            events: store.calendarEvents,
                            calendarConnected: store.calendarConnected,
                            toggleForecast: { store.toggleFullDayForecast() },
                            setForecastRange: { store.setForecastRange($0) }
                        )
                    case .system:
                        SystemWidgetView(snapshot: store.stats, accent: tile.accentColor)
                    case .power:
                        PowerWidgetView(snapshot: store.stats, accent: tile.accentColor)
                    case .launcher:
                        LauncherWidgetView(items: store.launchers, accent: tile.accentColor) { item in
                            store.openLauncher(item)
                        }
                    case .note:
                        NoteWidgetView(text: store.noteText, accent: tile.accentColor)
                    case .web:
                        if let config = tile.web {
                            WebWidgetView(
                                tile: tile,
                                config: config,
                                reloadToken: store.webReloadTokens[tile.id, default: 0]
                            )
                        }
                    }
                }
                .opacity(store.isEditingWidgets ? 0.74 : 1)
                .zIndex(1)
            }
            .padding(EdgeTheme.tilePadding)
            .foregroundStyle(EdgeTheme.primaryText)
        }
        .background {
            tileSurface
        }
        .overlay {
            RoundedRectangle(cornerRadius: EdgeTheme.tileRadius, style: .continuous)
                .stroke(tileBorderColor, lineWidth: tileBorderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: EdgeTheme.tileRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(tileTapGesture, including: tileGestureMask)
        .contextMenu {
            TileContextMenuItems(tile: tile, store: store) {
                openSettings()
            }
        }
    }

    private var tileBorderColor: Color {
        if store.focusedTileID == tile.id {
            return tile.accentColor.opacity(0.95)
        }

        if store.isEditingWidgets {
            return tile.accentColor.opacity(0.78)
        }

        if store.selectedWidgetID == tile.id {
            return tile.accentColor.opacity(0.60)
        }

        return EdgeTheme.stroke
    }

    private var tileBorderWidth: CGFloat {
        store.focusedTileID == tile.id || store.selectedWidgetID == tile.id || store.isEditingWidgets ? 2 : 1
    }

    private var tileShadowAccentOpacity: Double {
        if store.focusedTileID == tile.id { return 0.58 }
        if store.selectedWidgetID == tile.id || store.isEditingWidgets { return 0.34 }
        return 0.18
    }

    private var tileShadowAccentRadius: CGFloat {
        store.focusedTileID == tile.id ? 36 : 20
    }

    @ViewBuilder
    private var tileSurface: some View {
        let shape = RoundedRectangle(cornerRadius: EdgeTheme.tileRadius, style: .continuous)

        ZStack {
            if store.motionTileMaterial == .frosted {
                shape
                    .fill(.ultraThinMaterial)
                shape
                    .fill(EdgeTheme.cardFill(accent: tile.accentColor))
                    .opacity(0.64)
            } else {
                shape
                    .fill(EdgeTheme.cardFill(accent: tile.accentColor))
            }
        }
        .overlay(alignment: .top) {
            shape
                .stroke(.white.opacity(store.motionTileMaterial == .frosted ? 0.22 : 0.15), lineWidth: 1)
                .blendMode(.screen)
                .mask(alignment: .top) {
                    Rectangle()
                        .frame(height: 1)
                }
        }
        .overlay {
            if store.motionTileMaterial == .frosted {
                shape
                    .stroke(.white.opacity(0.05), lineWidth: 1)
                    .blendMode(.screen)
            }
        }
        .shadow(color: Color(nsColor: NSColor(hex: 0x190837, alpha: 0.70)), radius: 38, x: 0, y: 18)
        .shadow(color: tile.accentColor.opacity(tileShadowAccentOpacity), radius: tileShadowAccentRadius, x: 0, y: 10)
    }

    private var tileTapGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 3),
            TapGesture(count: 2)
        )
        .onEnded { value in
            switch value {
            case .first:
                openSettings()
            case .second:
                store.toggleFocusFromEdge(tile)
            }
        }
    }

    private var tileGestureMask: GestureMask {
        store.isEditingWidgets || tile.kind == .web ? .none : .gesture
    }

    private func openSettings() {
        store.selectWidget(tile)
        openWindow(id: "widget-settings")
        store.placeSettingsWindowOnMainDisplaySoon()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct IconChip: View {
    let symbolName: String
    let accent: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(EdgeTheme.accentGlyph)
            .frame(width: 32, height: 32)
            .background(EdgeTheme.accentFill(accent), in: RoundedRectangle(cornerRadius: EdgeTheme.iconChipRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EdgeTheme.iconChipRadius, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.55), radius: 13, x: 0, y: 5)
    }
}

private struct HeaderMetaPill: View {
    let symbolName: String
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.65), radius: 6)
            Text(text)
                .font(EdgeTheme.bodyFont(size: 10, weight: .black))
                .tracking(0.8)
        }
        .foregroundStyle(EdgeTheme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(accent.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct WebTileHeaderControls: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                HeaderMetaPill(symbolName: "circle.fill", text: "LIVE", accent: tile.accentColor)

                EdgeTileControlGroup {
                    EdgeTileControlButton(symbolName: "arrow.clockwise", helpText: "Reload web widget") {
                        store.reloadWebTile(tile)
                    }

                    EdgeTileControlButton(symbolName: "safari", helpText: "Open in browser") {
                        store.openWebTileExternallyFromEdge(tile)
                    }
                }
            }

            EdgeTileControlGroup {
                EdgeTileControlButton(symbolName: "arrow.clockwise", helpText: "Reload web widget") {
                    store.reloadWebTile(tile)
                }

                EdgeTileControlButton(symbolName: "safari", helpText: "Open in browser") {
                    store.openWebTileExternallyFromEdge(tile)
                }
            }
        }
    }
}

struct EdgeHUDView: View {
    @Bindable var store: DashboardStore
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            EdgeHUDStatusView(
                symbolName: statusSymbolName,
                title: statusTitle,
                detail: statusDetail,
                accent: statusAccent
            )

            EdgeHUDButton(
                symbolName: store.isPinned ? "lock.fill" : "lock.open.fill",
                isActive: store.isPinned,
                helpText: store.isPinned ? "Unlock dashboard pin" : "Lock dashboard pin"
            ) {
                store.togglePinnedFromEdge()
            }

            EdgeHUDButton(
                symbolName: store.isEditingWidgets ? "checkmark.circle.fill" : "slider.horizontal.3",
                isActive: store.isEditingWidgets,
                helpText: store.isEditingWidgets ? "Lock widget layout" : "Edit widget layout"
            ) {
                store.toggleEditingFromEdge()
            }

            EdgeHUDButton(
                symbolName: "gearshape",
                isActive: false,
                helpText: "Open widget settings"
            ) {
                openSettings()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(EdgeTheme.overlayText)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(store.isEditingWidgets ? Color.black.opacity(0.72) : EdgeTheme.overlayFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var focusedTile: WidgetTile? {
        guard let focusedTileID = store.focusedTileID else { return nil }
        return store.allVisibleTiles.first { $0.id == focusedTileID }
    }

    private var statusSymbolName: String {
        if store.isEditingWidgets {
            return "hand.point.up.left.fill"
        }

        if focusedTile != nil {
            return "scope"
        }

        return store.isPinned ? "lock.fill" : "lock.open.fill"
    }

    private var statusTitle: String {
        if store.isEditingWidgets {
            return "Editing"
        }

        if focusedTile != nil {
            return "Focused"
        }

        return store.isPinned ? "Locked" : "Unlocked"
    }

    private var statusDetail: String {
        if let focusedTile {
            return focusedTile.displayTitle
        }

        if store.isEditingWidgets {
            return "\(store.allVisibleTiles.count) tiles - \(store.actionStatus)"
        }

        return store.actionStatus
    }

    private var statusAccent: Color {
        if let focusedTile {
            return focusedTile.accentColor
        }

        return store.isEditingWidgets ? Color(red: 0.12, green: 0.72, blue: 0.88) : EdgeTheme.overlaySecondaryText
    }
}

struct TileControlsView: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                controlGroups
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    controlGroups
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: 256)
        }
        .zIndex(12)
    }

    @ViewBuilder
    private var controlGroups: some View {
        EdgeTileControlGroup {
            EdgeTileControlButton(symbolName: "chevron.left", helpText: "Move left") {
                store.moveWidget(tile, offset: -1)
            }

            EdgeTileControlButton(symbolName: "chevron.right", helpText: "Move right") {
                store.moveWidget(tile, offset: 1)
            }

            EdgeTileControlButton(symbolName: "minus.magnifyingglass", helpText: "Narrow") {
                store.resizeWidget(tile, delta: -1)
            }

            EdgeTileControlButton(symbolName: "plus.magnifyingglass", helpText: "Widen") {
                store.resizeWidget(tile, delta: 1)
            }
        }

        if tile.kind == .web {
            EdgeTileControlGroup {
                EdgeTileControlButton(symbolName: "arrow.clockwise", helpText: "Reload") {
                    store.reloadWebTile(tile)
                }

                EdgeTileControlButton(symbolName: "safari", helpText: "Open in browser") {
                    store.openWebTileExternallyFromEdge(tile)
                }
            }
        }

        EdgeTileControlGroup {
            EdgeTileControlButton(
                symbolName: store.focusedTileID == tile.id ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                helpText: store.focusedTileID == tile.id ? "Show all widgets" : "Focus tile"
            ) {
                store.toggleFocusFromEdge(tile)
            }

            EdgeTileControlButton(symbolName: "paintpalette", helpText: "Cycle accent") {
                store.cycleAccentFromEdge(tile)
            }

            EdgeTileControlButton(symbolName: "info.circle", helpText: "Widget settings") {
                openSettings()
            }

            EdgeTileControlButton(
                symbolName: "xmark.circle",
                helpText: "Close widget",
                role: .destructive,
                isDestructive: true
            ) {
                store.closeWidget(tile)
            }
        }
    }

    private func openSettings() {
        store.selectWidget(tile)
        openWindow(id: "widget-settings")
        store.placeSettingsWindowOnMainDisplaySoon()
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FocusedTileBadge: View {
    let accent: Color

    var body: some View {
        Text("FOCUS")
            .font(EdgeTheme.bodyFont(size: 10, weight: .black))
            .tracking(1.1)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(accent)
            .background(accent.opacity(0.16), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(accent.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.35), radius: 8)
    }
}

struct FocusedTileHeaderControls: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        HStack(spacing: 5) {
            EdgeTileControlGroup {
                EdgeTileControlButton(symbolName: "chevron.left", helpText: "Previous widget") {
                    store.focusPreviousWidget()
                }

                EdgeTileControlButton(symbolName: "chevron.right", helpText: "Next widget") {
                    store.focusNextWidget()
                }
            }

            FocusedTileBadge(accent: tile.accentColor)

            EdgeTileControlGroup {
                EdgeTileControlButton(symbolName: "arrow.down.right.and.arrow.up.left", helpText: "Show all widgets") {
                    store.clearFocus()
                }

                EdgeTileControlButton(
                    symbolName: "xmark.circle",
                    helpText: "Close widget",
                    role: .destructive,
                    isDestructive: true
                ) {
                    store.closeWidget(tile)
                }
            }
        }
    }
}

struct EdgeHUDStatusView: View {
    let symbolName: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(EdgeTheme.bodyFont(size: 9, weight: .black))
                    .foregroundStyle(EdgeTheme.overlayTertiaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(EdgeTheme.bodyFont(size: 11, weight: .bold))
                    .foregroundStyle(EdgeTheme.overlayText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(minWidth: 112, maxWidth: 244, alignment: .leading)
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(accent.opacity(0.16), in: Capsule())
        .overlay {
            Capsule()
                .stroke(accent.opacity(0.25), lineWidth: 1)
        }
    }
}

struct EdgeHUDButton: View {
    let symbolName: String
    let isActive: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? EdgeTheme.overlayText : EdgeTheme.overlaySecondaryText)
        .background(isActive ? .white.opacity(0.20) : EdgeTheme.overlaySubtleFill, in: Circle())
        .overlay {
            Circle()
                .stroke(isActive ? .white.opacity(0.28) : EdgeTheme.stroke, lineWidth: 1)
        }
        .help(helpText)
    }
}

struct EdgeTileControlGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(3)
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

struct EdgeTileControlButton: View {
    let symbolName: String
    let helpText: String
    var role: ButtonRole?
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDestructive ? Color(red: 1.0, green: 0.42, blue: 0.38) : EdgeTheme.overlayText)
        .background(EdgeTheme.overlaySubtleFill, in: Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .help(helpText)
    }
}

struct TileContextMenuItems: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore
    let openSettings: () -> Void

    @ViewBuilder
    var body: some View {
        Button {
            store.toggleFocusFromEdge(tile)
        } label: {
            Label(store.focusedTileID == tile.id ? "Show All Widgets" : "Focus", systemImage: store.focusedTileID == tile.id ? "arrow.down.right.and.arrow.up.left" : "scope")
        }

        Button {
            openSettings()
        } label: {
            Label("Edit Settings", systemImage: "slider.horizontal.3")
        }

        Button {
            store.cycleAccentFromEdge(tile)
        } label: {
            Label("Accent", systemImage: "paintpalette")
        }

        if tile.kind == .web {
            Divider()

            Button {
                store.reloadWebTile(tile)
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }

            Button {
                store.openWebTileExternallyFromEdge(tile)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }

        Divider()

        Button(role: .destructive) {
            store.closeWidget(tile)
        } label: {
            Label("Close", systemImage: "xmark.circle")
        }
    }
}

private extension DashboardStore {
    func toggleFocusFromEdge(_ tile: WidgetTile) {
        focusTile(tile)
        actionStatus = focusedTileID == tile.id ? "Focused \(tile.displayTitle)" : "Showing all widgets"
    }

    func cycleAccentFromEdge(_ tile: WidgetTile) {
        cycleAccent(tile)
        actionStatus = "Accent changed for \(tile.displayTitle)"
    }

    func openWebTileExternallyFromEdge(_ tile: WidgetTile) {
        openWebTileExternally(tile)
        actionStatus = "Opened \(tile.displayTitle)"
    }

    func togglePinnedFromEdge() {
        isPinned.toggle()
        configureWindow()
        persist()
        actionStatus = isPinned ? "Dashboard locked" : "Dashboard unlocked"
    }

    func toggleEditingFromEdge() {
        isEditingWidgets.toggle()
        actionStatus = isEditingWidgets ? "Editing widgets" : "Widgets locked"
    }
}
