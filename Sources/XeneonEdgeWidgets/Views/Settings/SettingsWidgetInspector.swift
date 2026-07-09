import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case basic
    case content
    case layout
    case advanced

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

struct SettingsWidgetInspector: View {
    @Bindable var store: DashboardStore
    @State private var tab: InspectorTab = .basic
    @State private var isRemoveConfirmationPresented = false

    var body: some View {
        SettingsCard(padding: 16) {
            if let selectedID = store.selectedWidgetID,
               let index = store.tiles.firstIndex(where: { $0.id == selectedID }) {
                let tile = store.tiles[index]

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        SettingsIconBadge(symbolName: tile.kind.symbolName, tint: tile.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.displayTitle)
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                            Text(tile.kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Picker("Inspector", selection: $tab) {
                        ForEach(InspectorTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    Group {
                        switch tab {
                        case .basic:
                            WidgetBasicInspector(tile: store.tileBinding(id: tile.id, snapshot: tile), store: store)
                        case .content:
                            WidgetContentInspector(tile: store.tileBinding(id: tile.id, snapshot: tile), store: store)
                        case .layout:
                            WidgetLayoutInspector(tile: tile, store: store)
                        case .advanced:
                            WidgetAdvancedInspector(tile: store.tileBinding(id: tile.id, snapshot: tile), store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    HStack {
                        Button {
                            store.undoDeleteWidget()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!store.canUndoDeleteWidget)

                        Spacer()

                        Button(role: .destructive) {
                            isRemoveConfirmationPresented = true
                        } label: {
                            Label("Remove from Page", systemImage: "trash")
                        }
                        .confirmationDialog("Remove \(tile.displayTitle)?", isPresented: $isRemoveConfirmationPresented) {
                            Button("Remove from Page", role: .destructive) {
                                store.removeTile(tile)
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No widget selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Select a widget from the list to edit its settings.")
                )
                .frame(minHeight: 320)
            }
        }
    }
}

private struct WidgetBasicInspector: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(symbolName: "textformat", tint: tile.accentColor, title: "Name") {
                TextField("Widget name", text: $tile.title)
                    .frame(width: 230)
                    .onChange(of: tile.title) {
                        store.persist()
                    }
            }
            SettingsDivider()
            SettingsRow(symbolName: "eye", tint: tile.accentColor, title: "Show on Edge") {
                Toggle("", isOn: $tile.isEnabled)
                    .labelsHidden()
                    .onChange(of: tile.isEnabled) {
                        // This binding writes directly to the tile, bypassing toggleWidget,
                        // so clear the Edge focus here too when hiding the focused widget (bug #26).
                        if !tile.isEnabled, store.focusedTileID == tile.id {
                            store.focusedTileID = nil
                        }
                        store.persist()
                    }
            }
            SettingsDivider()
            SettingsRow(symbolName: "rectangle.resize", tint: tile.accentColor, title: "Size") {
                Picker("Size", selection: $tile.size) {
                    ForEach(WidgetSize.allCases) { size in
                        Text(size.rawValue.capitalized).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .onChange(of: tile.size) {
                    store.persist()
                }
            }
            SettingsDivider()
            // Accent uses a STACKED layout, not a SettingsRow: the swatch row +
            // custom picker + hex is ~300pt wide and, placed beside a title, starved
            // it into a one-character-per-line column. Title on top, swatches below.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    SettingsIconBadge(symbolName: "paintpalette", tint: tile.accentColor)
                    Text("Accent")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
                }
                AccentField(tile: $tile, store: store)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

private struct AccentField: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore
    @State private var rememberedCustomHex = "7C5CFF"

    private var customColor: Binding<Color> {
        Binding {
            Color(hexRGB: tile.customAccentHex ?? rememberedCustomHex) ?? .purple
        } set: { color in
            if let hex = color.hexRGBString {
                rememberedCustomHex = hex
                tile.setCustomAccentColor(color)
                store.persist()
            }
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            ForEach(WidgetAccent.allCases) { accent in
                Button {
                    if let hex = tile.customAccentHex {
                        rememberedCustomHex = hex
                    }
                    tile.accent = accent
                    tile.customAccentHex = nil
                    store.persist()
                } label: {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle()
                                .stroke(tile.customAccentHex == nil && tile.accent == accent ? Color.primary : Color.secondary.opacity(0.25), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .help(accent.rawValue.capitalized)
            }

            Divider()
                .frame(height: 24)

            ColorPicker("Custom accent", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tile.customAccentHex == nil ? Color.secondary.opacity(0.20) : Color.primary, lineWidth: 2)
                        .allowsHitTesting(false)
                }

            Text("#\(tile.customAccentHex ?? rememberedCustomHex)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
        }
        .onAppear {
            if let hex = tile.customAccentHex {
                rememberedCustomHex = hex
            }
        }
    }
}

private struct WidgetContentInspector: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(spacing: 0) {
            switch tile.kind {
            case .clock:
                SettingsRow(symbolName: "cloud.sun", tint: tile.accentColor, title: "Show Full-Day Forecast", subtitle: "Adds the wider day forecast to the Clock widget.") {
                    Toggle("", isOn: forecastBinding)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(symbolName: "24.circle", tint: tile.accentColor, title: "24-hour time", subtitle: "Show the clock in 24-hour format instead of AM/PM.") {
                    Toggle("", isOn: Binding(
                        get: { store.uses24HourTime },
                        set: { store.setUses24HourTime($0) }
                    ))
                    .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(symbolName: "calendar.day.timeline.left", tint: tile.accentColor, title: "Forecast range", subtitle: "Show the day's hourly forecast or the 7-day outlook.") {
                    Picker("Forecast range", selection: Binding(
                        get: { store.forecastRange },
                        set: { store.setForecastRange($0) }
                    )) {
                        ForEach(ForecastRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                SettingsDivider()
                SettingsRow(symbolName: "thermometer.medium", tint: tile.accentColor, title: "Weather units", subtitle: "Uses your current Weather service settings.") {
                    StatusPill(title: "Auto", tint: .secondary)
                }
                SettingsDivider()
                ClockCalendarInspector(accent: tile.accentColor, store: store)
            case .web:
                WebContentInspector(tile: $tile, store: store)
            case .note:
                SettingsRow(symbolName: "text.alignleft", tint: tile.accentColor, title: "Note text", subtitle: "Shared with Note widgets in this profile.") {
                    TextField("Note", text: $store.noteText)
                        .frame(width: 260)
                        .onChange(of: store.noteText) {
                            store.persist()
                        }
                }
            case .launcher:
                SettingsRow(symbolName: "square.grid.2x2", tint: tile.accentColor, title: "Launcher contents", subtitle: "Edit apps on the Launcher page.") {
                    Button {
                        store.settingsSection = .apps
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(store.launchers.count) apps")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tile.accentColor)
                    .help("Open Launcher")
                }
            case .system:
                SettingsRow(symbolName: "cpu", tint: tile.accentColor, title: "System stats", subtitle: "CPU, memory, network, disk, and battery are read automatically.") {
                    StatusPill(title: "Live", tint: .green)
                }
                SettingsDivider()
                SettingsRow(symbolName: "textformat.size", tint: tile.accentColor, title: "Text size", subtitle: "Scale the text in this System widget for readability on the Edge.") {
                    HStack(spacing: 10) {
                        Text("\(Int((tile.textScale * 100).rounded()))%")
                            .font(.body.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { tile.textScale },
                                set: { tile.textScale = $0; store.persist() }
                            ),
                            in: 0.8...1.4,
                            step: 0.05
                        )
                        .frame(width: 150)
                    }
                }
            case .power:
                SettingsRow(symbolName: "battery.100percent", tint: tile.accentColor, title: "Device batteries", subtitle: "External device batteries are merged into the System widget.") {
                    StatusPill(title: "\(store.stats.deviceBatteries.count) found", tint: .green)
                }
            }
        }
    }

    private var forecastBinding: Binding<Bool> {
        Binding {
            store.showsFullDayForecast
        } set: { _ in
            store.toggleFullDayForecast()
        }
    }
}

private struct ClockCalendarInspector: View {
    let accent: Color
    @Bindable var store: DashboardStore
    @State private var clientID: String = ""
    @State private var showAdvanced = false

    private var needsClientID: Bool {
        store.effectiveCalendarClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(
                symbolName: store.calendarConnected ? "checkmark.icloud.fill" : "calendar.badge.plus",
                tint: accent,
                title: "Google Calendar",
                subtitle: store.calendarConnected ? store.calendarStatus : "Sign in to show your calendar in the Clock widget."
            ) {
                HStack(spacing: 10) {
                    if store.calendarConnected {
                        StatusPill(title: "Connected", tint: .green)
                        Button {
                            store.disconnectGoogleCalendar()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            store.connectGoogleCalendar()
                        } label: {
                            Label("Connect", systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(needsClientID)
                    }
                }
            }

            if !store.calendarConnected && needsClientID {
                Text("Google sign-in isn’t set up yet. Add a Client ID under Advanced below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if store.calendarConnected {
                SettingsDivider()

                SettingsRow(
                    symbolName: "list.bullet.rectangle",
                    tint: accent,
                    title: "Calendars",
                    subtitle: "Choose which calendars appear in the Clock agenda."
                ) {
                    Button {
                        store.refreshAvailableCalendars()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if store.availableCalendars.isEmpty {
                    Text("No calendars loaded yet. Tap Refresh to fetch your Google calendars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 11)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.availableCalendars) { calendar in
                            CalendarSelectRow(
                                calendar: calendar,
                                accent: accent,
                                isSelected: store.selectedCalendarIDs.contains(calendar.id)
                            ) {
                                store.toggleCalendarSelected(calendar.id)
                            }
                        }
                    }
                }
            }

            SettingsDivider()

            DisclosureGroup(isExpanded: $showAdvanced) {
                SettingsRow(
                    symbolName: "key.horizontal",
                    tint: accent,
                    title: "Google OAuth Client ID",
                    subtitle: "Required to connect (unless your build bundles one). Create an iOS-type OAuth client in Google Cloud and paste its ID — the README walks through it."
                ) {
                    TextField("xxxxx.apps.googleusercontent.com", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onChange(of: clientID) {
                            store.setCalendarClientID(clientID)
                        }
                }
            } label: {
                Label("Advanced", systemImage: "gearshape")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .onAppear {
            clientID = store.calendarClientID
        }
    }
}

private struct CalendarSelectRow: View {
    let calendar: GoogleCalendarInfo
    let accent: Color
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hexRGB: calendar.colorHex ?? "") ?? accent)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(calendar.accountSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 18)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// URL field that edits a local draft and commits on Enter or focus loss.
/// Writing through to the store per keystroke made the live WKWebView navigate
/// to every partial URL ("youtu", "youtub", ...) while typing — on heavy sites
/// like YouTube that burst of main-thread WebKit work beachballed the app.
private struct CommittedURLField: View {
    let placeholder: String
    @Binding var urlString: String
    let onCommit: () -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .focused($isFocused)
            .onAppear { draft = urlString }
            .onChange(of: urlString) {
                // External updates (YouTube mode buttons, profile switch)
                // always win over an in-progress edit; commit() writes the
                // same value back, so this is a no-op on our own commits.
                draft = urlString
            }
            .onSubmit { commit() }
            .onChange(of: isFocused) {
                if !isFocused { commit() }
            }
    }

    private func commit() {
        guard draft != urlString else { return }
        urlString = draft
        onCommit()
    }
}

private struct WebContentInspector: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        if let web = Binding($tile.web) {
            SettingsRow(symbolName: "globe", tint: tile.accentColor, title: "Site") {
                CommittedURLField(placeholder: "Website", urlString: web.urlString) {
                    store.persist()
                }
                .frame(width: 300)
            }
            SettingsDivider()
            SettingsRow(symbolName: "plus.magnifyingglass", tint: tile.accentColor, title: "Page Scale") {
                HStack {
                    Slider(value: web.zoom, in: 0.45...1.35, step: 0.05)
                        .frame(width: 180)
                    Text("\(Int(web.wrappedValue.zoom * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .onChange(of: web.wrappedValue.zoom) {
                    store.persist()
                }
            }
            if isYouTubeURL(web.wrappedValue.urlString) {
                SettingsDivider()
                SettingsRow(symbolName: "play.rectangle", tint: tile.accentColor, title: "YouTube mode", subtitle: "Pick the touch layout that works best on the Edge.") {
                    HStack {
                        Button("Web") {
                            applyStandardYouTube(to: web)
                        }
                        Button("Mobile") {
                            applyMobileYouTube(to: web)
                        }
                        Button("TV Sign-In") {
                            applyYouTubeTV(to: web)
                        }
                    }
                }
            }
        }
    }

    private func isYouTubeURL(_ rawValue: String) -> Bool {
        let lowercasedValue = rawValue.lowercased()
        return lowercasedValue.contains("youtube.com") || lowercasedValue.contains("youtu.be")
    }

    private func applyYouTubeTV(to web: Binding<WebTileConfig>) {
        web.wrappedValue.title = "YouTube TV"
        web.wrappedValue.urlString = "https://www.youtube.com/tv"
        web.wrappedValue.zoom = 0.86
        tile.title = "YouTube TV"
        store.persist()
        store.reloadWebTile(tile)
    }

    private func applyStandardYouTube(to web: Binding<WebTileConfig>) {
        web.wrappedValue.title = "YouTube"
        web.wrappedValue.urlString = "https://www.youtube.com"
        web.wrappedValue.zoom = 0.7
        tile.title = "YouTube"
        store.persist()
        store.reloadWebTile(tile)
    }

    private func applyMobileYouTube(to web: Binding<WebTileConfig>) {
        web.wrappedValue.title = "YouTube Mobile"
        web.wrappedValue.urlString = "https://m.youtube.com"
        web.wrappedValue.zoom = 0.78
        tile.title = "YouTube Mobile"
        store.persist()
        store.reloadWebTile(tile)
    }
}

private struct WidgetLayoutInspector: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(symbolName: "arrow.left.arrow.right", tint: tile.accentColor, title: "Reorder") {
                HStack {
                    Button {
                        store.moveWidget(tile, offset: -1)
                    } label: {
                        Label("Move left", systemImage: "chevron.left")
                    }
                    Button {
                        store.moveWidget(tile, offset: 1)
                    } label: {
                        Label("Move right", systemImage: "chevron.right")
                    }
                }
            }
            SettingsDivider()
            SettingsRow(symbolName: "arrow.up.left.and.arrow.down.right", tint: tile.accentColor, title: "Show Only This Widget", subtitle: "Temporarily focus this widget full screen on the Edge.") {
                Toggle("", isOn: focusBinding)
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(symbolName: "eye.slash", tint: tile.accentColor, title: "Disable Widget", subtitle: "Keeps the widget on this page but hides it from the Edge.") {
                Button {
                    store.closeWidget(tile)
                } label: {
                    Label("Disable", systemImage: "eye.slash")
                }
            }
        }
    }

    private var focusBinding: Binding<Bool> {
        Binding {
            store.focusedTileID == tile.id
        } set: { _ in
            store.focusTile(tile)
        }
    }
}

struct WidgetAdvancedInspector: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(spacing: 0) {
            if let web = Binding($tile.web) {
                SettingsRow(symbolName: "link", tint: .gray, title: "Raw web address") {
                    CommittedURLField(placeholder: "URL", urlString: web.urlString) {
                        store.persist()
                    }
                    .frame(width: 300)
                }
                SettingsDivider()
                SettingsRow(symbolName: "clock.arrow.circlepath", tint: .gray, title: "Reload interval") {
                    TextField("Seconds", value: web.reloadInterval, format: .number)
                        .frame(width: 110)
                        .onChange(of: web.wrappedValue.reloadInterval) {
                            store.persist()
                        }
                }
                SettingsDivider()
                SettingsRow(symbolName: "desktopcomputer", tint: .gray, title: "Desktop user agent") {
                    Toggle("", isOn: web.usesDesktopUserAgent)
                        .labelsHidden()
                        .onChange(of: web.wrappedValue.usesDesktopUserAgent) {
                            store.persist()
                            store.reloadWebTile(tile)
                        }
                }
                SettingsDivider()
                SettingsRow(symbolName: "textformat.size", tint: .gray, title: "Readable CSS") {
                    Toggle("", isOn: web.injectsReadableCSS)
                        .labelsHidden()
                        .onChange(of: web.wrappedValue.injectsReadableCSS) {
                            store.persist()
                            store.reloadWebTile(tile)
                        }
                }
            } else {
                SettingsRow(symbolName: "info.circle", tint: .gray, title: "No advanced fields", subtitle: "This widget only has the basic options above.") {
                    EmptyView()
                }
            }
        }
    }
}
