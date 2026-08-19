import AppKit
import Foundation

enum LauncherService {
    private static let applicationCache = InstalledApplicationCache()

    static func installedApplications() -> [InstalledApplication] {
        scanInstalledApplications()
    }

    /// Returns the installed-application list from a short-lived cache. The first
    /// load and an explicitly forced refresh run on the cache actor, so recursive
    /// bundle enumeration does not run on the caller's actor (especially the main
    /// actor used by the settings UI).
    static func installedApplicationsCached(forceRefresh: Bool = false) async -> [InstalledApplication] {
        await applicationCache.applications(forceRefresh: forceRefresh) {
            scanInstalledApplications()
        }
    }

    /// Refreshes the cached list in the background and returns the new snapshot.
    static func refreshInstalledApplications() async -> [InstalledApplication] {
        await installedApplicationsCached(forceRefresh: true)
    }

    /// Resolves a configured launcher name without making the caller scan the
    /// filesystem. Set `forceRefresh` when the caller knows an app was installed
    /// or removed since the previous lookup.
    static func resolveApplication(
        named appName: String,
        forceRefresh: Bool = false
    ) async -> InstalledApplication? {
        let applications = await installedApplicationsCached(forceRefresh: forceRefresh)
        return findApplication(named: appName, in: applications)
    }

    private static func scanInstalledApplications() -> [InstalledApplication] {
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

    private static func findApplication(
        named appName: String,
        in applications: [InstalledApplication]
    ) -> InstalledApplication? {
        applications.first {
            $0.appName.caseInsensitiveCompare(appName) == .orderedSame
                || $0.displayName.caseInsensitiveCompare(appName) == .orderedSame
                || $0.bundleIdentifier?.caseInsensitiveCompare(appName) == .orderedSame
        }
    }

    @MainActor
    static func openApplication(named appName: String) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        let workspace = NSWorkspace.shared

        // The input is a human app name (e.g. "Safari", "Ecamm Live"), occasionally
        // a bundle identifier. Try a bundle-id lookup first in case it really is one;
        // for a display name this returns nil and we fall through to name resolution.
        if let url = workspace.urlForApplication(withBundleIdentifier: appName) {
            workspace.openApplication(at: url, configuration: configuration) { _, _ in }
            return true
        }

        // Resolve by name against the scanned application list so apps that live
        // outside the hardcoded roots, or whose .app filename differs from the
        // configured name, still launch via their real bundle URL.
        if let match = findApplication(named: appName, in: installedApplications()) {
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
                return true
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
                return true
            }
        }

        // Couldn't locate the app. Do nothing rather than silently opening a Finder
        // window on /Applications, which masks the failure and confuses the user.
        NSLog("LauncherService: couldn't locate application named \"%@\"", appName)
        return false
    }

    /// Opens an application that was already resolved by the background lookup
    /// API. This keeps bundle resolution and launching on the main actor while
    /// avoiding another recursive filesystem scan.
    @MainActor
    static func openApplication(_ application: InstalledApplication) -> Bool {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        let resolved: URL?
        if let bundleID = application.bundleIdentifier {
            resolved = workspace.urlForApplication(withBundleIdentifier: bundleID)
        } else {
            resolved = URL(filePath: application.id)
        }

        guard let url = resolved else {
            NSLog("LauncherService: couldn't locate application named \"%@\"", application.appName)
            return false
        }

        workspace.openApplication(at: url, configuration: configuration) { _, _ in }
        return true
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

private actor InstalledApplicationCache {
    private static let lifetime: TimeInterval = 300
    private var cachedApplications: [InstalledApplication] = []
    private var refreshedAt: Date?

    func applications(
        forceRefresh: Bool,
        at date: Date = Date(),
        loader: @Sendable () -> [InstalledApplication]
    ) -> [InstalledApplication] {
        if !forceRefresh,
           let refreshedAt,
           date.timeIntervalSince(refreshedAt) < Self.lifetime {
            return cachedApplications
        }

        let applications = loader()
        cachedApplications = applications
        refreshedAt = date
        return applications
    }
}
