import AppKit
import SwiftUI

@main
struct XeneonEdgeWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var store = DashboardStore()

    var body: some Scene {
        // A single-window scene: the dashboard is one surface, so `Window` (not
        // WindowGroup) makes duplicate dashboards impossible — no per-URL window
        // spawning, no Cmd+N copies, and no scene restoration resurrecting a
        // cascade of stale dashboard windows.
        Window("Kira Edge", id: "dashboard") {
            ContentView(store: store)
                .environment(store)
                .onAppear {
                    store.start()
                }
                .onOpenURL { url in
                    EdgeURLRouter.route(url, store: store)
                }
                // Claim external events (xeneonedge:// URLs) for the existing
                // window so macOS routes them here instead of elsewhere.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandMenu("Kira Edge") {
                // ⌘1–⌘6 jump straight to a profile while the app is frontmost;
                // the menu-bar extra covers switching from anywhere else.
                ForEach(Array(DashboardPreset.allCases.enumerated()), id: \.element.id) { index, preset in
                    Button {
                        store.applyPreset(preset)
                    } label: {
                        Label(preset.title, systemImage: store.selectedPreset == preset ? "checkmark.circle" : preset.symbolName)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }

                Divider()

                Button("Send to XENEON Edge") {
                    store.moveToEdge()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button(store.edgeMode ? "Show Controls" : "Enter Edge Mode") {
                    if store.edgeMode {
                        store.exitEdgeMode()
                    } else {
                        store.moveToEdge()
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button(store.isEditingWidgets ? "Done Editing Widgets" : "Edit Widgets") {
                    store.isEditingWidgets.toggle()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Button("Open Widget Settings") {
                    openWindow(id: "widget-settings")
                    store.placeSettingsWindowOnMainDisplaySoon()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: [.command])

                Divider()

                Button(store.isPinned ? "Unpin Dashboard" : "Pin Dashboard") {
                    store.isPinned.toggle()
                    store.configureWindow()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Kira Edge", systemImage: "display") {
            MenuBarControlView(
                store: store,
                openDashboard: {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                },
                openSettings: {
                    openWindow(id: "widget-settings")
                    store.placeSettingsWindowOnMainDisplaySoon()
                    NSApp.activate(ignoringOtherApps: true)
                }
            )
        }

        Window("Widget Settings", id: "widget-settings") {
            WidgetSettingsWindowView(store: store)
                .environment(store)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1120, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistrar.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
