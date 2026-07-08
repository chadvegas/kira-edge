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
        if let primaryDisplay = screen(for: CGMainDisplayID()), primaryDisplay != xeneon {
            return primaryDisplay
        }

        if let main = NSScreen.main, main != xeneon {
            return main
        }

        let candidates = NSScreen.screens.filter { screen in
            guard let xeneon else { return true }
            return screen != xeneon
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

    @MainActor
    static func window(_ window: NSWindow, isOn screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return window.frame.intersection(screen.frame).width > screen.frame.width * 0.5
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenID.uint32Value == displayID
        }
    }
}
