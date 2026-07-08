import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAppsPage: View {
    @Bindable var store: DashboardStore
    @State private var appSearchText = ""
    @State private var dropTargetLauncherID: UUID?
    @State private var isDropAtEnd = false

    private var filteredApplications: [InstalledApplication] {
        // No cap: the list is a lazy ScrollView, so all installed apps render fine.
        // (A 160-item cap previously truncated the alphabetical list around "R".)
        guard !appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.installedApplications
        }
        return store.installedApplications
            .filter { $0.displayName.localizedCaseInsensitiveContains(appSearchText) || $0.appName.localizedCaseInsensitiveContains(appSearchText) }
    }

    var body: some View {
        SettingsPage(
            title: "Launcher",
            subtitle: "Choose the apps that appear in the Launcher widget. Tapping an app on the Edge opens it."
        ) {
            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader("Launcher", subtitle: "These app buttons appear inside the Launcher widget.")

                    if store.launchers.isEmpty {
                        ContentUnavailableView(
                            "No apps in Launcher",
                            systemImage: "square.grid.2x2",
                            description: Text("Add apps below to populate the Launcher widget.")
                        )
                        .frame(minHeight: 130)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(store.launchers) { item in
                                LauncherAppRow(
                                    item: item,
                                    store: store,
                                    showsInsertionLine: dropTargetLauncherID == item.id && !isDropAtEnd
                                )
                                .onDrop(
                                    of: [.text],
                                    delegate: LauncherDropDelegate(
                                        targetID: item.id,
                                        store: store,
                                        dropTargetID: $dropTargetLauncherID,
                                        isDropAtEnd: $isDropAtEnd
                                    )
                                )
                            }

                            // Trailing drop zone: a row that shows the insertion line at the
                            // bottom of the list when dropping past the last app.
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 10)
                                .overlay(alignment: .top) {
                                    LauncherInsertionLine()
                                        .opacity(isDropAtEnd ? 1 : 0)
                                }
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [.text],
                                    delegate: LauncherEndDropDelegate(
                                        store: store,
                                        dropTargetID: $dropTargetLauncherID,
                                        isDropAtEnd: $isDropAtEnd
                                    )
                                )
                        }
                    }
                }
            }

            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader("Add app", subtitle: "Tap + to add an installed app to the Launcher. Tap again to remove it.")
                        Spacer()
                        TextField("Search apps", text: $appSearchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        Button {
                            store.refreshInstalledApplications()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }

                    if filteredApplications.isEmpty {
                        ContentUnavailableView(
                            "No apps found",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search, or press Refresh to rescan installed apps.")
                        )
                        .frame(minHeight: 160)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredApplications) { app in
                                    InstalledAppRow(
                                        app: app,
                                        isAdded: isLauncherInstalled(app),
                                        add: { addLauncher(for: app) },
                                        remove: { removeLauncher(for: app) }
                                    )
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .frame(height: 300)
                    }
                }
            }
        }
        .onAppear {
            if store.installedApplications.isEmpty {
                store.refreshInstalledApplications()
            }
        }
    }

    /// The stable identity of an installed app: its bundle identifier when known,
    /// otherwise the .app leaf filename. Two distinct apps that share a filename but
    /// carry different bundle identifiers therefore resolve to different identities.
    private func identity(of app: InstalledApplication) -> String {
        app.bundleIdentifier ?? app.appName
    }

    /// True when a launcher already exists for `app`. Launchers persist only the .app
    /// filename, so this matches on filename and — when both sides can be resolved to a
    /// bundle identifier via the installed-apps scan — additionally requires the bundle
    /// identifiers to agree, so a same-named app with a different bundle id is not
    /// mistaken for one that is already added.
    private func isLauncherInstalled(_ app: InstalledApplication) -> Bool {
        let targetIdentity = identity(of: app)
        return store.launchers.contains { launcher in
            launcherMatches(launcher, identity: targetIdentity, appName: app.appName)
        }
    }

    /// Matches a stored launcher against a target installed-app identity. Falls back to
    /// filename-only matching when the launcher's filename cannot be resolved to a
    /// distinct bundle identifier in the current scan.
    private func launcherMatches(_ launcher: LauncherItem, identity targetIdentity: String, appName: String) -> Bool {
        guard launcher.appName == appName else { return false }
        // Resolve the launcher's stored filename back to a scanned bundle identifier.
        // If it resolves, require the identities to agree; otherwise fall back to the
        // filename match we already established above.
        if let resolved = store.installedApplications.first(where: { $0.appName == launcher.appName }),
           let bundleID = resolved.bundleIdentifier {
            return bundleID == targetIdentity
        }
        return true
    }

    private func addLauncher(for app: InstalledApplication) {
        // Dedupe guard: never append a launcher for an app that is already present.
        guard !isLauncherInstalled(app) else { return }
        store.addLauncher(
            title: app.displayName,
            appName: app.appName,
            symbolName: controlSurface(for: app.appName).symbolName
        )
    }

    private func removeLauncher(for app: InstalledApplication) {
        let targetIdentity = identity(of: app)
        if let item = store.launchers.first(where: { launcher in
            launcherMatches(launcher, identity: targetIdentity, appName: app.appName)
        }) {
            store.removeLauncher(item)
        }
    }
}

/// A thin accent-colored bar that marks where a dragged Launcher app will land.
private struct LauncherInsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 2)
    }
}

/// A row in the installed-applications picker showing the real app icon, its name,
/// and a +/checkmark toggle for adding to or removing from the Launcher.
private struct InstalledAppRow: View {
    let app: InstalledApplication
    let isAdded: Bool
    let add: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            if let icon = LauncherService.appIcon(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                SettingsIconBadge(symbolName: controlSurface(for: app.appName).symbolName, tint: controlSurface(for: app.appName).tint)
            }

            Text(app.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer()

            Button {
                if isAdded { remove() } else { add() }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isAdded ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(isAdded ? "Remove \(app.displayName) from Launcher" : "Add \(app.displayName) to Launcher")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isAdded ? Color.green.opacity(0.08) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isAdded ? Color.green.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

/// Drop delegate for an individual Launcher row: tracks hover so an insertion line
/// can appear at the row's top edge, and reorders before the targeted item on drop.
private struct LauncherDropDelegate: DropDelegate {
    let targetID: UUID
    let store: DashboardStore
    @Binding var dropTargetID: UUID?
    @Binding var isDropAtEnd: Bool

    func dropEntered(info: DropInfo) {
        dropTargetID = targetID
        isDropAtEnd = false
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID {
            dropTargetID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dropTargetID = nil
            isDropAtEnd = false
        }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let target = targetID
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let sourceID = UUID(uuidString: raw) else { return }
            Task { @MainActor in
                store.moveLauncher(id: sourceID, before: target)
            }
        }
        return true
    }
}

/// Drop delegate for the trailing zone below the last Launcher row: moves the dragged
/// app to the end of the list and shows the insertion line at the list's bottom edge.
private struct LauncherEndDropDelegate: DropDelegate {
    let store: DashboardStore
    @Binding var dropTargetID: UUID?
    @Binding var isDropAtEnd: Bool

    func dropEntered(info: DropInfo) {
        dropTargetID = nil
        isDropAtEnd = true
    }

    func dropExited(info: DropInfo) {
        isDropAtEnd = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dropTargetID = nil
            isDropAtEnd = false
        }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let sourceID = UUID(uuidString: raw) else { return }
            Task { @MainActor in
                store.moveLauncherToEnd(id: sourceID)
            }
        }
        return true
    }
}

private struct LauncherAppRow: View {
    let item: LauncherItem
    @Bindable var store: DashboardStore
    var showsInsertionLine = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)

            SettingsIconBadge(symbolName: item.symbolName.isEmpty ? control.symbolName : item.symbolName, tint: control.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                Text(control.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(title: control.shortTitle, tint: control.tint)

            Button {
                store.openLauncher(item)
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Open \(item.title)")

            Button(role: .destructive) {
                store.removeLauncher(item)
            } label: {
                Image(systemName: "trash")
            }
            .foregroundStyle(.red)
            .help("Remove \(item.title)")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        // Insertion indicator: a clear accent bar at the TOP edge of the row the
        // dragged app will land before.
        .overlay(alignment: .top) {
            LauncherInsertionLine()
                .offset(y: -5)
                .opacity(showsInsertionLine ? 1 : 0)
        }
        .draggable(item.id.uuidString) {
            Label(item.title, systemImage: item.symbolName.isEmpty ? control.symbolName : item.symbolName)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var control: LauncherControlSurface {
        controlSurface(for: item.appName)
    }
}

private struct LauncherControlSurface {
    let title: String
    let shortTitle: String
    let symbolName: String
    let tint: Color
}

private func controlSurface(for appName: String) -> LauncherControlSurface {
    // Tapping a launcher app on the Edge simply opens it, so every app shares one
    // plain "tap to open" surface — the fallback icon when the real app icon is
    // unavailable, and a neutral label in Settings.
    LauncherControlSurface(title: "Tap to open", shortTitle: "Open", symbolName: "app", tint: .orange)
}
