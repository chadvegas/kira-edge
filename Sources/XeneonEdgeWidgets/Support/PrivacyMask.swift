import SwiftUI

/// Pure helpers that replace personal data with generic stand-ins when Privacy
/// Mode is on, so the dashboard can be screenshotted or shared without leaking
/// device owner names, IP addresses, or calendar event titles. Masking happens
/// at the display layer only — the underlying data is never altered.
enum PrivacyMask {
    /// Bulleted placeholder for any IPv4/IPv6 address.
    static let ip = "•••.•••.•••.•••"

    /// Placeholder shown in place of a calendar event's title.
    static let eventTitle = "Busy"

    /// Reduces a device's display name to its generic product type, dropping the
    /// owner ("Alex's Apple Watch" → "Apple Watch", "Jordan's iPhone" → "iPhone").
    static func deviceName(_ name: String, kind: String? = nil) -> String {
        let haystack = "\(name) \(kind ?? "")".lowercased()
        switch true {
        case haystack.contains("watch"): return "Apple Watch"
        case haystack.contains("airpods"): return "AirPods"
        case haystack.contains("iphone"): return "iPhone"
        case haystack.contains("ipad"): return "iPad"
        case haystack.contains("macbook"): return "MacBook"
        case haystack.contains("imac"): return "iMac"
        case haystack.contains("mac mini"), haystack.contains("macmini"): return "Mac mini"
        case haystack.contains("trackpad"): return "Trackpad"
        case haystack.contains("mouse"): return "Mouse"
        case haystack.contains("keyboard"): return "Keyboard"
        case haystack.contains("mac"): return "Mac"
        default: return "Device"
        }
    }
}

private struct PrivacyModeKey: EnvironmentKey {
    static let defaultValue = false
}

private struct WidgetTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    /// When true, widgets substitute generic placeholders for personal data.
    /// Injected once at the dashboard root from `DashboardStore.privacyMode`.
    var privacyMode: Bool {
        get { self[PrivacyModeKey.self] }
        set { self[PrivacyModeKey.self] = newValue }
    }

    /// Per-widget multiplier applied to text sizes, injected from a tile's
    /// `textScale`. Defaults to 1.0, so widgets that aren't given a scale (and
    /// shared primitives reused elsewhere) render at their normal size.
    var widgetTextScale: CGFloat {
        get { self[WidgetTextScaleKey.self] }
        set { self[WidgetTextScaleKey.self] = newValue }
    }
}
