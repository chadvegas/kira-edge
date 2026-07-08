import SwiftUI

struct SettingsWidgetsPage: View {
    @Bindable var store: DashboardStore
    let showAddWidget: () -> Void

    var body: some View {
        SettingsPage(
            title: "Widgets",
            subtitle: "Add, reorder, resize, and tune the widgets on the current page."
        ) {
            WidgetsProfilePicker(store: store)

            EdgePreviewCard(store: store, height: 210)

            HStack(alignment: .top, spacing: 16) {
                SettingsCard(padding: 14) {
                    SettingsWidgetList(store: store, showAddWidget: showAddWidget)
                }
                .frame(minWidth: 330, idealWidth: 380, maxWidth: 430)

                SettingsWidgetInspector(store: store)
                    .frame(minWidth: 430, maxWidth: .infinity)
            }
        }
    }
}

private struct WidgetsProfilePicker: View {
    @Bindable var store: DashboardStore

    var body: some View {
        SettingsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Profile", subtitle: "Switch the active dashboard mode without leaving Widgets.")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DashboardPreset.allCases) { preset in
                            ProfileChip(
                                preset: preset,
                                isSelected: store.selectedPreset == preset
                            ) {
                                store.applyPreset(preset)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

private struct ProfileChip: View {
    let preset: DashboardPreset
    let isSelected: Bool
    let select: () -> Void

    private var tint: Color {
        settingsPresetTint(preset)
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                Image(systemName: preset.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : .secondary)
                Text(preset.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? tint.opacity(0.16) : Color.secondary.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? tint.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .help("Switch to \(preset.title)")
    }
}

private struct SettingsWidgetList: View {
    @Bindable var store: DashboardStore
    let showAddWidget: () -> Void

    private var visibleTiles: [WidgetTile] {
        store.tiles.filter(\.isEnabled)
    }

    private var hiddenTiles: [WidgetTile] {
        store.tiles.filter { !$0.isEnabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(store.currentPageTitle, subtitle: "\(visibleTiles.count) shown · \(hiddenTiles.count) hidden")
                Spacer()
                Button(action: showAddWidget) {
                    Label("Add Widget", systemImage: "plus")
                }
            }

            if store.tiles.isEmpty {
                ContentUnavailableView(
                    "No widgets on this page",
                    systemImage: "rectangle.dashed",
                    description: Text("Add a widget to start building this page.")
                )
                Button(action: showAddWidget) {
                    Label("Add widget", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleTiles) { tile in
                        SettingsWidgetRow(tile: tile, store: store)
                    }

                    if !hiddenTiles.isEmpty {
                        Text("Hidden")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        ForEach(hiddenTiles) { tile in
                            SettingsWidgetRow(tile: tile, store: store)
                        }
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let rawID = items.first, let sourceID = UUID(uuidString: rawID) else {
                        return false
                    }
                    store.moveTileToEnd(id: sourceID)
                    return true
                }
            }
        }
    }
}

private struct SettingsWidgetRow: View {
    let tile: WidgetTile
    @Bindable var store: DashboardStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Image(systemName: tile.kind.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tile.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(tile.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(store.selectedWidgetID == tile.id ? tile.accentColor.opacity(0.14) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(store.selectedWidgetID == tile.id ? tile.accentColor.opacity(0.72) : Color.primary.opacity(0.07), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectWidget(tile)
        }
        .draggable(tile.id.uuidString) {
            Label(tile.displayTitle, systemImage: tile.kind.symbolName)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let rawID = items.first, let sourceID = UUID(uuidString: rawID) else {
                return false
            }
            store.moveTile(id: sourceID, before: tile.id)
            return true
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            tile.isEnabled
        } set: { _ in
            store.toggleWidget(tile)
        }
    }

    private var rowDetail: String {
        switch tile.kind {
        case .web:
            tile.web?.urlString ?? "Website"
        case .launcher:
            "Launcher"
        default:
            "\(tile.kind.title) · \(tile.size.rawValue.capitalized)"
        }
    }
}
