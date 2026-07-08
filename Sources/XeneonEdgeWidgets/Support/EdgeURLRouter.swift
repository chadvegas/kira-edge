import Foundation
import os

/// Routes `xeneonedge://` URLs to `DashboardStore` actions so Stream Deck
/// buttons and shell scripts can drive the dashboard via `open xeneonedge://...`.
/// The scheme itself is registered in the generated Info.plist
/// (script/build_and_run.sh).
///
/// Grammar — `xeneonedge://<command>/<argument>`:
///   profile/<name>                  apply a preset; name matches rawValue or
///                                   title, case-insensitive, spaces/hyphens
///                                   stripped (aiops, ai-ops, AI Ops all work)
///   page/next | prev | <index>     page navigation (index is zero-based)
///   focus/clear | <widget kind>    clear focus, or focus the first visible
///                                   clock|system|power|launcher|note|web
///   edge/send                       move the dashboard to the Edge
///   web/reload                      reload every web tile
///   appearance/dark|light|system    switch appearance mode
///   motion/pause|resume|toggle      motion backdrop pause state
///   mute/on|off|toggle              mute overlay
enum EdgeURLRouter {
    private static let logger = Logger(
        subsystem: "com.chadvegas.XeneonEdgeWidgets",
        category: "URLRouter"
    )

    @MainActor
    static func route(_ url: URL, store: DashboardStore) {
        logger.log("Received URL: \(url.absoluteString, privacy: .public)")

        if let outcome = perform(url, store: store) {
            store.actionStatus = "URL: \(outcome)"
            logger.log("Routed \(url.absoluteString, privacy: .public) -> \(outcome, privacy: .public)")
        } else {
            store.actionStatus = "Unknown command: \(url.absoluteString)"
            logger.log("Unknown command: \(url.absoluteString, privacy: .public)")
        }
    }

    /// Executes the command encoded in `url`. Returns a short human-readable
    /// outcome on success, or nil when the URL is unknown/malformed.
    @MainActor
    private static func perform(_ url: URL, store: DashboardStore) -> String? {
        guard let command = url.host?.lowercased() else { return nil }
        let argument = url.pathComponents.first { $0 != "/" } ?? ""

        switch command {
        case "profile":
            guard let preset = preset(named: argument) else { return nil }
            store.applyPreset(preset)
            return "switched to \(preset.title)"

        case "page":
            switch argument.lowercased() {
            case "next":
                store.selectNextPage()
                return "next page (\(store.currentPageTitle))"
            case "prev", "previous":
                store.selectPreviousPage()
                return "previous page (\(store.currentPageTitle))"
            default:
                guard let index = Int(argument),
                      store.currentPages.indices.contains(index) else { return nil }
                store.selectPage(at: index)
                return "page \(index + 1) (\(store.currentPageTitle))"
            }

        case "focus":
            if argument.lowercased() == "clear" {
                store.clearFocus()
                return "showing all widgets"
            }
            guard let kind = WidgetKind(rawValue: argument.lowercased()) else { return nil }
            guard let tile = store.allVisibleTiles.first(where: { $0.kind == kind }) else {
                return "no visible \(kind.title) widget"
            }
            store.focusedTileID = tile.id
            return "focused \(tile.displayTitle)"

        case "edge":
            guard argument.lowercased() == "send" else { return nil }
            store.moveToEdge()
            // moveToEdge() silently no-ops when the dashboard window is gone
            // or the Edge display is missing; report the real outcome instead
            // of assuming success.
            guard store.dashboardWindow != nil else { return "no dashboard window" }
            guard ScreenResolver.xeneonScreen() != nil else { return "Edge display not found" }
            return "sent to XENEON Edge"

        case "web":
            guard argument.lowercased() == "reload" else { return nil }
            store.reloadAllWebTiles()
            // reloadAllWebTiles() sets a descriptive status ("Reloaded 3 web
            // widgets" / "No web widgets to reload"); surface it as the outcome.
            return store.actionStatus

        case "appearance":
            guard let mode = EdgeAppearanceMode(rawValue: argument.lowercased()) else { return nil }
            store.setAppearanceMode(mode)
            return "\(mode.title) mode"

        case "motion":
            switch argument.lowercased() {
            case "pause":
                store.setMotionPaused(true)
                return "motion paused"
            case "resume":
                store.setMotionPaused(false)
                return "motion resumed"
            case "toggle":
                store.setMotionPaused(!store.motionIsPaused)
                return store.motionIsPaused ? "motion paused" : "motion resumed"
            default:
                return nil
            }

        case "mute":
            switch argument.lowercased() {
            case "on":
                store.setMuteOverlay(true)
                return "mute overlay on"
            case "off":
                store.setMuteOverlay(false)
                return "mute overlay off"
            case "toggle":
                store.toggleMuteOverlay()
                return store.isMuteOverlayVisible ? "mute overlay on" : "mute overlay off"
            default:
                return nil
            }

        default:
            return nil
        }
    }

    /// Lenient preset lookup: case-insensitive match against rawValue and
    /// title with spaces, hyphens, and underscores stripped, so `aiops`,
    /// `ai-ops`, and `AI%20Ops` all resolve to `.aiOps`.
    private static func preset(named name: String) -> DashboardPreset? {
        let needle = normalized(name)
        guard !needle.isEmpty else { return nil }
        return DashboardPreset.allCases.first { candidate in
            normalized(candidate.rawValue) == needle || normalized(candidate.title) == needle
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0 != " " && $0 != "-" && $0 != "_" }
    }
}
