import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAdvancedPage: View {
    @Bindable var store: DashboardStore
    @State private var isResetConfirmationPresented = false

    var body: some View {
        SettingsPage(
            title: "Advanced",
            subtitle: "Technical fields and reset tools live here so the normal setup flow stays calm."
        ) {
            SettingsCard {
                SettingsRow(
                    symbolName: "exclamationmark.triangle",
                    tint: .orange,
                    title: "Advanced settings",
                    subtitle: "These controls can break a widget if the values are wrong. Use them when you know exactly what needs changing."
                ) {
                    EmptyView()
                }
            }

            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Selected widget raw fields", subtitle: "Select a widget on the Widgets page to edit its technical options.")
                    if let selectedID = store.selectedWidgetID,
                       let tile = store.tiles.first(where: { $0.id == selectedID }) {
                        WidgetAdvancedInspector(tile: store.tileBinding(id: tile.id, snapshot: tile), store: store)
                    } else {
                        ContentUnavailableView(
                            "No widget selected",
                            systemImage: "rectangle.dashed",
                            description: Text("Choose a widget first, then return here for raw fields.")
                        )
                        .frame(minHeight: 150)
                    }
                }
            }

            SettingsCard {
                SettingsRow(symbolName: "square.and.arrow.up", tint: .blue, title: "Export profile", subtitle: "Saves every profile, page, and widget to a JSON file.") {
                    Button {
                        exportProfile()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                SettingsDivider()
                SettingsRow(symbolName: "square.and.arrow.down", tint: .blue, title: "Import profile", subtitle: "Replaces the current setup with a previously exported JSON file.") {
                    Button {
                        importProfile()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                SettingsDivider()
                SettingsRow(symbolName: "power", tint: .green, title: "Launch at login", subtitle: "Starts the dashboard automatically when you sign in.") {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsDivider()
                SettingsRow(symbolName: "arrow.counterclockwise", tint: .red, title: "Reset to defaults", subtitle: "Restores the built-in profiles, pages, widgets, appearance, and launchers.") {
                    Button(role: .destructive) {
                        isResetConfirmationPresented = true
                    } label: {
                        Label("Reset", systemImage: "trash")
                    }
                    .confirmationDialog("Reset everything to defaults?", isPresented: $isResetConfirmationPresented) {
                        Button("Reset to Defaults", role: .destructive) {
                            store.resetProfile()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }

            SettingsCard {
                SettingsRow(symbolName: "display", tint: .gray, title: "Screen status", subtitle: store.screenStatus) {
                    Button("Refresh") {
                        store.screenStatus = ScreenResolver.targetDescription()
                    }
                }
                SettingsDivider()
                SettingsRow(symbolName: "bolt.horizontal", tint: .gray, title: "Last action", subtitle: store.actionStatus) {
                    EmptyView()
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginEnabled },
            set: { store.setLaunchAtLogin($0) }
        )
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "xeneon-profile.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportProfileData()
            try data.write(to: url, options: .atomic)
            store.actionStatus = "Profile exported to \(url.lastPathComponent)"
        } catch {
            store.actionStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try store.importProfile(from: data)
            store.actionStatus = "Profile imported from \(url.lastPathComponent)"
        } catch {
            store.actionStatus = "Import failed: \(error.localizedDescription)"
        }
    }
}
