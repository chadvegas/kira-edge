import AppKit
import CoreGraphics
import Foundation

enum ScreenResolver {
    static func xeneonScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.localizedName.localizedCaseInsensitiveContains("XENEON")
        } ?? NSScreen.screens.first { screen in
            let frame = screen.frame
            guard frame.height > 0 else { return false }
            let aspect = frame.width / frame.height
            return aspect > 3.0 && frame.width >= 1800 && frame.height <= 900
        }
    }

    static func primaryWorkScreen() -> NSScreen? {
        let xeneon = xeneonScreen()
        if let primaryDisplay = screen(for: CGMainDisplayID()), !sameScreen(primaryDisplay, xeneon) {
            return primaryDisplay
        }

        if let main = NSScreen.main, !sameScreen(main, xeneon) {
            return main
        }

        let candidates = NSScreen.screens.filter { screen in
            guard let xeneon else { return true }
            return !sameScreen(screen, xeneon)
        }

        return candidates.max { lhs, rhs in
            lhs.visibleFrame.width * lhs.visibleFrame.height < rhs.visibleFrame.width * rhs.visibleFrame.height
        } ?? NSScreen.screens.first
    }

    static func targetDescription() -> String {
        guard let screen = xeneonScreen() else {
            return "XENEON EDGE display not found"
        }

        let frame = screen.frame
        return "\(screen.localizedName) \(Int(frame.width))x\(Int(frame.height))"
    }

    static func screenSummaries() -> [String] {
        NSScreen.screens.map { screen in
            let frame = screen.frame
            return "\(screen.localizedName) - \(Int(frame.width))x\(Int(frame.height))"
        }
    }

    /// Returns the stable CoreGraphics display identity for an AppKit screen.
    /// `NSScreen` instances can be recreated after a display reconfiguration, so
    /// callers should retain this ID rather than the screen object itself.
    static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard
            let screen,
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Re-resolves a display ID against the current AppKit screen list.
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            Self.displayID(for: screen) == displayID
        }
    }

    /// Returns the current AppKit object for a previously captured screen.
    static func refreshedScreen(_ screen: NSScreen?) -> NSScreen? {
        guard let screen, let displayID = displayID(for: screen) else { return nil }
        return self.screen(for: displayID)
    }

    /// Compares screens by stable display ID, with object identity as a fallback
    /// for unusual screens that do not expose `NSScreenNumber`.
    static func sameScreen(_ lhs: NSScreen?, _ rhs: NSScreen?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        if let lhsID = displayID(for: lhs), let rhsID = displayID(for: rhs) {
            return lhsID == rhsID
        }
        return lhs === rhs
    }

    @MainActor
    static func window(_ window: NSWindow, isOn screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return window.frame.intersection(screen.frame).width > screen.frame.width * 0.5
    }

}
