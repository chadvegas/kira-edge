import SwiftUI

struct WidgetEditorView: View {
    @Bindable var store: DashboardStore
    @State private var newWebTitle = "YouTube"
    @State private var newWebURL = "https://www.youtube.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Runtime")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            WidgetGalleryView(store: store)

            ProfilePageControlsView(store: store)

            AddTileControlsView(
                store: store,
                newWebTitle: $newWebTitle,
                newWebURL: $newWebURL
            )

            LauncherEditorPanelView(store: store)

            HStack(alignment: .top, spacing: 16) {
                WidgetListPanel(store: store)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)

                SelectedWidgetInspectorView(store: store)
                    .frame(minWidth: 360, maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button {
                    store.resetProfile()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Text(store.actionStatus)
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(24)
    }
}

private struct LauncherEditorPanelView: View {
    @Bindable var store: DashboardStore
    @State private var newTitle = "Messages"
    @State private var newAppName = "Messages"
    @State private var newSymbolName = "message"

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                if store.launchers.isEmpty {
                    ContentUnavailableView(
                        "No Apps In Launcher",
                        systemImage: "square.grid.2x2",
                        description: Text("Add an app to populate the Apps widget.")
                    )
                    .frame(minHeight: 94)
                } else {
                    VStack(spacing: 8) {
                        ForEach($store.launchers) { $item in
                            LauncherEditorRow(
                                item: $item,
                                store: store,
                                canMoveUp: store.launchers.first?.id != item.id,
                                canMoveDown: store.launchers.last?.id != item.id
                            )
                        }
                    }
                }

                Divider()

                if !store.installedApplications.isEmpty {
                    HStack(spacing: 10) {
                        Picker("Choose App", selection: $newAppName) {
                            ForEach(store.installedApplications) { app in
                                Text(app.displayName).tag(app.appName)
                            }
                        }
                        .onChange(of: newAppName) {
                            if let app = store.installedApplications.first(where: { $0.appName == newAppName }) {
                                newTitle = app.displayName
                            }
                        }

                        Button {
                            store.refreshInstalledApplications()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Title", text: $newTitle)
                        .frame(minWidth: 120)
                    TextField("Application", text: $newAppName)
                        .frame(minWidth: 180)
                    TextField("SF Symbol", text: $newSymbolName)
                        .frame(minWidth: 130)

                    Button {
                        store.addLauncher(title: newTitle, appName: newAppName, symbolName: newSymbolName)
                    } label: {
                        Label("Add App", systemImage: "plus")
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Apps Widget", systemImage: "square.grid.2x2")
                    .font(.headline)

                Spacer()

                Text("\(store.launchers.count) apps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.regular)
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(.quaternary.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LauncherEditorRow: View {
    @Binding var item: LauncherItem
    @Bindable var store: DashboardStore
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.symbolName.isEmpty ? "app" : item.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            TextField("Title", text: $item.title)
                .frame(minWidth: 120)
                .onChange(of: item.title) {
                    store.persist()
                }

            if store.installedApplications.isEmpty {
                TextField("Application", text: $item.appName)
                    .frame(minWidth: 170)
                    .onChange(of: item.appName) {
                        store.persist()
                    }
            } else {
                Picker("Application", selection: $item.appName) {
                    if !store.installedApplications.contains(where: { $0.appName == item.appName }) {
                        Text(item.appName).tag(item.appName)
                    }
                    ForEach(store.installedApplications) { app in
                        Text(app.displayName).tag(app.appName)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 170)
                .onChange(of: item.appName) {
                    if let app = store.installedApplications.first(where: { $0.appName == item.appName }), item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        item.title = app.displayName
                    }
                    store.persist()
                }
            }

            TextField("SF Symbol", text: $item.symbolName)
                .frame(minWidth: 120)
                .onChange(of: item.symbolName) {
                    store.persist()
                }

            Button {
                store.openLauncher(item)
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Launch \(item.title)")

            Button {
                store.moveLauncher(item, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            .help("Move up")

            Button {
                store.moveLauncher(item, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            .help("Move down")

            Button(role: .destructive) {
                store.removeLauncher(item)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Remove \(item.title)")
        }
    }
}

private struct AddTileControlsView: View {
    @Bindable var store: DashboardStore
    @Binding var newWebTitle: String
    @Binding var newWebURL: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label("Site", systemImage: "globe")
                    .font(.headline)
                    .frame(width: 84, alignment: .leading)

                TextField("Title", text: $newWebTitle)
                    .frame(minWidth: 120)
                TextField("URL", text: $newWebURL)
                    .frame(minWidth: 220)

                Button {
                    store.addWebTile(title: newWebTitle, urlString: newWebURL)
                } label: {
                    Label("Add Web Tile", systemImage: "plus")
                }
            }
        }
        .controlSize(.regular)
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(.quaternary.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WidgetListPanel: View {
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Widgets", systemImage: "square.grid.3x3")
                    .font(.headline)

                Spacer()

                Button {
                    store.undoDeleteWidget()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)
                .disabled(!store.canUndoDeleteWidget)
                .help("Restore the last deleted widget")

                Text("\(store.tiles.filter(\.isEnabled).count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.tiles) { tile in
                        WidgetListRow(
                            tile: tile,
                            isSelected: store.selectedWidgetID == tile.id,
                            select: {
                                store.selectWidget(tile)
                            },
                            delete: {
                                store.removeTile(tile)
                            }
                        )
                        .draggable(tile.id.uuidString) {
                            Label(tile.displayTitle, systemImage: tile.kind.symbolName)
                                .padding(8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard
                                let rawID = items.first,
                                let sourceID = UUID(uuidString: rawID)
                            else {
                                return false
                            }

                            store.moveTile(id: sourceID, before: tile.id)
                            return true
                        }
                    }

                    if store.tiles.isEmpty {
                        ContentUnavailableView(
                            "No Widgets On This Page",
                            systemImage: "rectangle.dashed",
                            description: Text("Add widgets from the gallery or site/app controls.")
                        )
                        .frame(minHeight: 180)
                    }
                }
                .padding(8)
                .dropDestination(for: String.self) { items, _ in
                    guard
                        let rawID = items.first,
                        let sourceID = UUID(uuidString: rawID)
                    else {
                        return false
                    }

                    store.moveTileToEnd(id: sourceID)
                    return true
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

private struct WidgetListRow: View {
    let tile: WidgetTile
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .help("Drag to reorder")

            Image(systemName: tile.kind.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tile.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(tile.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !tile.isEnabled {
                Text("Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(tile.accentColor)
            }

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .background(Color.red.opacity(0.10), in: Circle())
            .help("Delete \(tile.displayTitle) from this page")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(isSelected ? tile.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? tile.accentColor.opacity(0.50) : Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }

    private var detail: String {
        switch tile.kind {
        case .web:
            tile.web?.urlString ?? "Web"
        default:
            "\(tile.kind.title) / \(tile.size.rawValue.capitalized)"
        }
    }
}

struct SelectedWidgetInspectorView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        ScrollView {
            if
                let selectedID = store.selectedWidgetID,
                let index = store.tiles.firstIndex(where: { $0.id == selectedID })
            {
                let tile = store.tiles[index]

                VStack(alignment: .leading, spacing: 14) {
                    InspectorHeader(tile: tile)

                    Divider()

                    TileInspectorControls(tile: store.tileBinding(id: tile.id, snapshot: tile), store: store)

                    Divider()

                    HStack(spacing: 10) {
                        Button {
                            store.moveWidget(tile, offset: -1)
                        } label: {
                            Label("Left", systemImage: "chevron.left")
                        }

                        Button {
                            store.moveWidget(tile, offset: 1)
                        } label: {
                            Label("Right", systemImage: "chevron.right")
                        }

                        Button {
                            store.focusTile(tile)
                        } label: {
                            Label(
                                store.focusedTileID == tile.id ? "Unfocus" : "Focus",
                                systemImage: store.focusedTileID == tile.id ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                            )
                        }

                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.closeWidget(tile)
                        } label: {
                            Label("Hide Widget", systemImage: "eye.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            store.removeTile(tile)
                        } label: {
                            Label("Delete Widget", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        store.undoDeleteWidget()
                    } label: {
                        Label("Undo Delete", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.canUndoDeleteWidget)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "No Widget Selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Tap a widget info button, triple tap a widget, or select a row.")
                )
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InspectorHeader: View {
    let tile: WidgetTile

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tile.kind.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tile.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(tile.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(tile.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct TileInspectorControls: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enabled", isOn: $tile.isEnabled)
                .onChange(of: tile.isEnabled) {
                    store.persist()
                }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Size")
                        .foregroundStyle(.secondary)

                    Picker("Size", selection: $tile.size) {
                        ForEach(WidgetSize.allCases) { size in
                            Text(size.rawValue.capitalized).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .onChange(of: tile.size) {
                        store.persist()
                    }
                }

                GridRow {
                    Text("Accent")
                        .foregroundStyle(.secondary)

                    AccentColorEditor(tile: $tile, store: store)
                }
            }

            if tile.kind == .web {
                WebTileEditor(tile: $tile, store: store)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AccentColorEditor: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    private var customColor: Binding<Color> {
        Binding {
            tile.accentColor
        } set: { color in
            tile.setCustomAccentColor(color)
            store.persist()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(WidgetAccent.allCases) { accent in
                    Button {
                        tile.accent = accent
                        tile.customAccentHex = nil
                        store.persist()
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .stroke(tile.customAccentHex == nil && tile.accent == accent ? Color.primary : Color.secondary.opacity(0.22), lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(accent.rawValue.capitalized)
                }

                Divider()
                    .frame(height: 24)

                ColorPicker("Custom", selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .help("Pick a custom widget accent color")

                if tile.customAccentHex != nil {
                    Button {
                        tile.customAccentHex = nil
                        store.persist()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Use the preset accent color")
                }
            }

            Text(tile.customAccentHex.map { "#\($0)" } ?? tile.accent.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct WebTileEditor: View {
    @Binding var tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        if let web = Binding($tile.web) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("URL")
                        .foregroundStyle(.secondary)
                    TextField("URL", text: web.urlString)
                        .onChange(of: web.wrappedValue.urlString) {
                            tile.title = web.wrappedValue.title
                            store.persist()
                        }
                }
                GridRow {
                    Text("Zoom")
                        .foregroundStyle(.secondary)
                    Slider(value: web.zoom, in: 0.45...1.35, step: 0.05)
                        .onChange(of: web.wrappedValue.zoom) {
                            store.persist()
                        }
                }
                GridRow {
                    Text("Title")
                        .foregroundStyle(.secondary)
                    TextField("Title", text: web.title)
                        .onChange(of: web.wrappedValue.title) {
                            tile.title = web.wrappedValue.title
                            store.persist()
                        }
                }
            }
            .font(.callout)
            .padding(.leading, 36)

            if isYouTubeURL(web.wrappedValue.urlString) {
                HStack(spacing: 8) {
                    Button {
                        applyYouTubeTV(to: web)
                    } label: {
                        Label("Use TV Sign-In", systemImage: "tv")
                    }

                    Button {
                        applyStandardYouTube(to: web)
                    } label: {
                        Label("Use Web YouTube", systemImage: "play.rectangle")
                    }

                    Button {
                        applyMobileYouTube(to: web)
                    } label: {
                        Label("Use Mobile YouTube", systemImage: "iphone")
                    }

                    Button {
                        openYouTubeActivation()
                    } label: {
                        Label("Activate Code", systemImage: "qrcode")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 36)
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

    private func openYouTubeActivation() {
        guard let url = URL(string: "https://yt.be/activate") else { return }
        NSWorkspace.shared.open(url)
    }
}
