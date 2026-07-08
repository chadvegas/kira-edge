import AppKit
import SwiftUI

struct SettingsOverviewPage: View {
    @Bindable var store: DashboardStore
    let showAddWidget: () -> Void

    var body: some View {
        SettingsPage(
            title: "Overview",
            subtitle: "Check the Edge, preview the current dashboard, and jump into the most common setup tasks."
        ) {
            SettingsCard(padding: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            SettingsIconBadge(symbolName: "display", tint: .blue)
                            StatusPill(title: edgeStatus, tint: edgeTint)
                        }

                        Text(store.selectedPreset.title)
                            .font(.title.weight(.semibold))
                        Text("\(store.currentPageTitle) · \(store.tiles.filter(\.isEnabled).count) visible widgets · \(store.tiles.filter { !$0.isEnabled }.count) hidden")
                            .foregroundStyle(.secondary)

                        Text(store.actionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("2560 x 720")
                            .font(.title3.weight(.semibold))
                        Text("XENEON Edge canvas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            EdgePreviewCard(store: store, height: 245)

            FlowGrid(QuickAction.allCases, minItemWidth: 220) { action in
                QuickActionCard(action: action) {
                    perform(action)
                }
            }

            SettingsCard {
                SettingsRow(
                    symbolName: "checkmark.shield",
                    tint: .green,
                    title: "Setup health",
                    subtitle: "The dashboard works best when the XENEON Edge display and device battery readers are ready."
                ) {
                    StatusPill(title: healthStatus, tint: healthTint)
                }
                SettingsDivider()
                SettingsRow(
                    symbolName: "battery.100percent",
                    tint: .green,
                    title: "Device batteries",
                    subtitle: deviceBatterySubtitle
                ) {
                    StatusPill(title: "\(store.stats.deviceBatteries.count) found", tint: .green)
                }
            }
        }
    }

    private var edgeStatus: String {
        store.screenStatus.localizedCaseInsensitiveContains("not found") ? "Open on Mac" : "Edge connected"
    }

    private var edgeTint: Color {
        store.screenStatus.localizedCaseInsensitiveContains("not found") ? .orange : .green
    }

    private var edgeConnected: Bool {
        !store.screenStatus.localizedCaseInsensitiveContains("not found")
    }

    private var healthStatus: String {
        edgeConnected ? "Looks good" : "Needs attention"
    }

    private var healthTint: Color {
        edgeConnected ? .green : .orange
    }

    private var deviceBatterySubtitle: String {
        if store.stats.deviceBatteries.isEmpty {
            return "No external devices detected yet."
        }
        return store.stats.deviceBatteries.prefix(3)
            .map { "\($0.name) \(($0.percent * 100).rounded().formatted(.number.precision(.fractionLength(0))))%" }
            .joined(separator: " · ")
    }

    private func perform(_ action: QuickAction) {
        switch action {
        case .send:
            store.moveToEdge()
        case .addWidget:
            showAddWidget()
        case .editLayout:
            store.isEditingWidgets.toggle()
            store.actionStatus = store.isEditingWidgets ? "Layout editing on" : "Layout editing off"
        case .appearance:
            switch store.appearanceMode {
            case .dark: store.setAppearanceMode(.light)
            case .light: store.setAppearanceMode(.system)
            case .system: store.setAppearanceMode(.dark)
            }
        }
    }
}

private enum QuickAction: String, CaseIterable, Identifiable {
    case send
    case addWidget
    case editLayout
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .send: "Send to Edge"
        case .addWidget: "Add a widget"
        case .editLayout: "Edit layout"
        case .appearance: "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .send: "Move the dashboard to the XENEON display."
        case .addWidget: "Choose from essentials, web, and home tiles."
        case .editLayout: "Turn on layout handles on the Edge."
        case .appearance: "Cycle dark, light, and system mode."
        }
    }

    var symbolName: String {
        switch self {
        case .send: "arrow.up.forward.app"
        case .addWidget: "plus.square"
        case .editLayout: "slider.horizontal.3"
        case .appearance: "circle.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .send: .blue
        case .addWidget: .teal
        case .editLayout: .orange
        case .appearance: .purple
        }
    }
}

private struct QuickActionCard: View {
    let action: QuickAction
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconBadge(symbolName: action.symbolName, tint: action.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.headline)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(action.tint.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
