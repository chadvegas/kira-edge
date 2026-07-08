import SwiftUI

enum ControlSection: String, CaseIterable, Identifiable {
    case overview
    case profiles
    case widgets
    case apps
    case display
    case devices
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .profiles: "Profiles"
        case .widgets: "Widgets"
        case .apps: "Launcher"
        case .display: "Display"
        case .devices: "Devices & Permissions"
        case .advanced: "Advanced"
        }
    }

    var sidebarGroup: SettingsSidebarGroup {
        switch self {
        case .overview: .top
        case .profiles, .widgets, .apps: .dashboard
        case .display, .devices, .advanced: .system
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .profiles: "person.2.crop.square.stack"
        case .widgets: "square.grid.3x3"
        case .apps: "square.grid.2x2"
        case .display: "display"
        case .devices: "checkmark.shield"
        case .advanced: "gearshape.2"
        }
    }

    var tint: Color {
        switch self {
        case .overview: .blue
        case .profiles: .purple
        case .widgets: .teal
        case .apps: .orange
        case .display: .indigo
        case .devices: .green
        case .advanced: .gray
        }
    }
}

enum SettingsSidebarGroup: String, CaseIterable, Identifiable {
    case top
    case dashboard
    case system

    var id: String { rawValue }

    var title: String? {
        switch self {
        case .top: nil
        case .dashboard: "Dashboard"
        case .system: "System"
        }
    }
}

struct ContentView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        EdgeDashboardView(store: store)
            .frame(minWidth: 860, minHeight: 260)
            .background(WindowAccessor { window in
                store.attachWindow(window)
            })
    }
}

struct WidgetSettingsWindowView: View {
    @Bindable var store: DashboardStore
    @State private var isAddWidgetPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $store.settingsSection, store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 310)
        } detail: {
            DetailView(
                selection: store.settingsSection ?? .overview,
                store: store,
                showAddWidget: {
                    store.settingsSection = .widgets
                    isAddWidgetPresented = true
                }
            )
        }
        .background(WindowAccessor { window in
            store.attachSettingsWindow(window)
        })
        .onAppear {
            store.placeSettingsWindowOnMainDisplaySoon()
        }
        .sheet(isPresented: $isAddWidgetPresented) {
            AddWidgetSheetView(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    cycleAppearance()
                } label: {
                    Label(store.appearanceMode.title, systemImage: store.appearanceMode.symbolName)
                }
                .help("Switch dashboard appearance")

                Button {
                    store.settingsSection = .widgets
                    isAddWidgetPresented = true
                } label: {
                    Label("Add Widget", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("Add a widget to the current page")

                Button {
                    store.moveToEdge()
                } label: {
                    Label("Send to Edge", systemImage: "arrow.up.forward.app")
                }
            }
        }
    }

    private func cycleAppearance() {
        switch store.appearanceMode {
        case .dark:
            store.setAppearanceMode(.light)
        case .light:
            store.setAppearanceMode(.system)
        case .system:
            store.setAppearanceMode(.dark)
        }
    }
}

struct SidebarView: View {
    @Binding var selection: ControlSection?
    @Bindable var store: DashboardStore
    @State private var searchText = ""

    private var filteredSections: [ControlSection] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ControlSection.allCases
        }
        return ControlSection.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SettingsSidebarGroup.allCases) { group in
                    let sections = filteredSections.filter { $0.sidebarGroup == group }
                    if !sections.isEmpty {
                        if let title = group.title {
                            Section(title) {
                                sidebarRows(sections)
                            }
                        } else {
                            sidebarRows(sections)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")

            EdgeStatusPill(store: store)
                .padding(12)
        }
        .navigationTitle("Kira Edge")
    }

    @ViewBuilder
    private func sidebarRows(_ sections: [ControlSection]) -> some View {
        ForEach(sections) { section in
            HStack(spacing: 10) {
                SettingsIconBadge(symbolName: section.symbolName, tint: section.tint)
                Text(section.title)
                    .font(.body)
            }
            .tag(section)
        }
    }
}

private struct EdgeStatusPill: View {
    @Bindable var store: DashboardStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.screenStatus.localizedCaseInsensitiveContains("not found") ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(edgeStatusTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(store.selectedPreset.title) · \(store.currentPageTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.75), in: Capsule())
    }

    private var edgeStatusTitle: String {
        if store.screenStatus.localizedCaseInsensitiveContains("XENEON") {
            return "Edge connected · 2560x720"
        }
        return "Edge status · \(store.screenStatus)"
    }
}

struct DetailView: View {
    let selection: ControlSection
    @Bindable var store: DashboardStore
    let showAddWidget: () -> Void

    var body: some View {
        ScrollView {
            switch selection {
            case .overview:
                SettingsOverviewPage(store: store, showAddWidget: showAddWidget)
            case .profiles:
                SettingsProfilesPage(store: store)
            case .widgets:
                SettingsWidgetsPage(store: store, showAddWidget: showAddWidget)
            case .apps:
                SettingsAppsPage(store: store)
            case .display:
                SettingsDisplayPage(store: store)
            case .devices:
                SettingsDevicesPage(store: store)
            case .advanced:
                SettingsAdvancedPage(store: store)
            }
        }
        .background(Color.settingsWindowBackground)
    }
}
