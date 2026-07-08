import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @Bindable var store: DashboardStore
    let openDashboard: () -> Void
    let openSettings: () -> Void

    var body: some View {
        // Profile switching is the most common menu action, so it leads the menu
        // and its label always shows which profile is live.
        Menu {
            ForEach(DashboardPreset.allCases) { preset in
                Button {
                    store.applyPreset(preset)
                } label: {
                    Label(preset.title, systemImage: store.selectedPreset == preset ? "checkmark.circle" : preset.symbolName)
                }
            }
        } label: {
            Label("Profile: \(store.selectedPreset.title)", systemImage: store.selectedPreset.symbolName)
        }

        Divider()

        Button {
            sendToEdge()
        } label: {
            Label("Send to Edge", systemImage: "arrow.up.forward.app")
        }

        Button {
            showControls()
        } label: {
            Label(store.edgeMode ? "Show Controls" : "Open Controls", systemImage: "macwindow")
        }

        Button {
            openSettings()
        } label: {
            Label("Widget Settings", systemImage: "gearshape")
        }

        Divider()

        Toggle(isOn: $store.isEditingWidgets) {
            Label(store.isEditingWidgets ? "Done Editing" : "Edit Widgets", systemImage: "slider.horizontal.3")
        }

        Toggle(isOn: pinBinding) {
            Label(store.isPinned ? "Pinned" : "Pin Dashboard", systemImage: store.isPinned ? "pin.fill" : "pin")
        }

        Toggle(isOn: forecastBinding) {
            Label(store.showsFullDayForecast ? "Full Forecast" : "Compact Weather", systemImage: "cloud.sun")
        }

        Button {
            reloadWebWidgets()
        } label: {
            Label("Reload Web", systemImage: "arrow.clockwise")
        }
        .disabled(webTiles.isEmpty)

        Divider()

        Menu {
            ForEach(EdgeAppearanceMode.allCases) { mode in
                Button {
                    store.setAppearanceMode(mode)
                } label: {
                    Label(mode.title, systemImage: store.appearanceMode == mode ? "checkmark.circle" : mode.symbolName)
                }
            }
        } label: {
            Label("Appearance", systemImage: store.appearanceMode.symbolName)
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var pinBinding: Binding<Bool> {
        Binding {
            store.isPinned
        } set: { isPinned in
            store.isPinned = isPinned
            store.configureWindow()
            store.persist()
        }
    }

    private var forecastBinding: Binding<Bool> {
        Binding {
            store.showsFullDayForecast
        } set: { _ in
            store.toggleFullDayForecast()
        }
    }

    private var webTiles: [WidgetTile] {
        store.tiles.filter { $0.kind == .web }
    }

    private func sendToEdge() {
        openDashboard()
        store.moveToEdge()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            store.moveToEdge()
        }
    }

    private func showControls() {
        openDashboard()

        guard store.edgeMode else { return }
        store.exitEdgeMode()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if store.edgeMode {
                store.exitEdgeMode()
            }
        }
    }

    private func reloadWebWidgets() {
        store.reloadAllWebTiles()
    }
}
