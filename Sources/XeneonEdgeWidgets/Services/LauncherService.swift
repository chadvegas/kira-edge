import AppKit
import Foundation

enum LauncherService {
    static func installedApplications() -> [InstalledApplication] {
        // Only user-facing app folders. /System/Library/CoreServices is intentionally
        // excluded: it is full of installers and background agents (Installer, IOUIAgent,
        // "Install Command Line Developer Tools", …) that are not launchable apps.
        let roots = [
            "/Applications",
            "/System/Applications"
        ].map { URL(fileURLWithPath: $0) }

        var seen = Set<String>()
        var apps: [InstalledApplication] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let displayName = (
                    bundle?.localizedInfoDictionary?["CFBundleDisplayName"]
                    ?? bundle?.localizedInfoDictionary?["CFBundleName"]
                    ?? bundle?.infoDictionary?["CFBundleDisplayName"]
                    ?? bundle?.infoDictionary?["CFBundleName"]
                ) as? String ?? url.deletingPathExtension().lastPathComponent
                let appName = url.deletingPathExtension().lastPathComponent
                let uniqueID = bundleID ?? url.path

                guard !seen.contains(uniqueID) else { continue }
                seen.insert(uniqueID)
                apps.append(
                    InstalledApplication(
                        id: uniqueID,
                        displayName: displayName,
                        appName: appName,
                        bundleIdentifier: bundleID
                    )
                )
            }
        }

        return apps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    @MainActor
    static func openApplication(named appName: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        let workspace = NSWorkspace.shared

        // The input is a human app name (e.g. "Safari", "Ecamm Live"), occasionally
        // a bundle identifier. Try a bundle-id lookup first in case it really is one;
        // for a display name this returns nil and we fall through to name resolution.
        if let url = workspace.urlForApplication(withBundleIdentifier: appName) {
            workspace.openApplication(at: url, configuration: configuration) { _, _ in }
            return
        }

        // Resolve by name against the scanned application list so apps that live
        // outside the hardcoded roots, or whose .app filename differs from the
        // configured name, still launch via their real bundle URL.
        if let match = installedApplications().first(where: {
            $0.appName.caseInsensitiveCompare(appName) == .orderedSame
                || $0.displayName.caseInsensitiveCompare(appName) == .orderedSame
        }) {
            // When the bundle id is known, resolve through the workspace. Otherwise
            // `id` is the .app's filesystem path (see installedApplications()).
            let resolved: URL?
            if let bundleID = match.bundleIdentifier {
                resolved = workspace.urlForApplication(withBundleIdentifier: bundleID)
            } else {
                resolved = URL(filePath: match.id)
            }
            if let url = resolved {
                workspace.openApplication(at: url, configuration: configuration) { _, _ in }
                return
            }
        }

        let candidates = [
            "/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Library/CoreServices/\(appName).app"
        ]

        for candidate in candidates {
            let url = URL(filePath: candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                workspace.openApplication(at: url, configuration: configuration) { _, _ in }
                return
            }
        }

        // Couldn't locate the app. Do nothing rather than silently opening a Finder
        // window on /Applications, which masks the failure and confuses the user.
        NSLog("LauncherService: couldn't locate application named \"%@\"", appName)
    }

    /// Resolves the Finder icon for an installed application. When the bundle id
    /// is known, resolve through the workspace; otherwise `id` is the .app's
    /// filesystem path (see installedApplications()). Returns nil if unresolved.
    /// The caller is responsible for sizing the returned image (e.g. 22x22).
    static func appIcon(for app: InstalledApplication) -> NSImage? {
        let url: URL?
        if let bundleID = app.bundleIdentifier {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        } else {
            url = URL(filePath: app.id)
        }
        guard let url else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
