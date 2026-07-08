import AppKit
import SwiftUI

enum EdgeTheme {
    static let tileRadius: CGFloat = 20
    static let wellRadius: CGFloat = 15
    static let chipRadius: CGFloat = 12
    static let iconChipRadius: CGFloat = 13
    static let tilePadding: CGFloat = 19

    static let background = dynamicColor(
        dark: NSColor(hex: 0x1B1438),
        light: NSColor(hex: 0xF4EDFF)
    )
    static let backgroundBandA = dynamicColor(
        dark: NSColor(hex: 0x1D1640),
        light: NSColor(hex: 0xFDEEF4)
    )
    static let backgroundBandB = dynamicColor(
        dark: NSColor(hex: 0x241B46),
        light: NSColor(hex: 0xEAF1FF)
    )
    static let backgroundBandC = dynamicColor(
        dark: NSColor(hex: 0x2C1D48),
        light: NSColor(hex: 0xF1ECFF)
    )
    static let card = dynamicColor(
        dark: NSColor(hex: 0x241D45, alpha: 0.96),
        light: NSColor(hex: 0xFFFFFF)
    )
    static let cardWell = dynamicColor(
        dark: NSColor(hex: 0x322A59),
        light: NSColor(hex: 0xF4F1FB)
    )
    static let primaryText = dynamicColor(
        dark: NSColor(hex: 0xFCF7FF),
        light: NSColor(hex: 0x2A2140)
    )
    static let secondaryText = dynamicColor(
        dark: NSColor(hex: 0xFCF7FF, alpha: 0.76),
        light: NSColor(hex: 0x2A2140, alpha: 0.68)
    )
    static let tertiaryText = dynamicColor(
        dark: NSColor(hex: 0xFCF7FF, alpha: 0.54),
        light: NSColor(hex: 0x2A2140, alpha: 0.48)
    )
    static let stroke = dynamicColor(
        dark: NSColor(hex: 0xFFFFFF, alpha: 0.13),
        light: NSColor(hex: 0x2A2140, alpha: 0.10)
    )
    static let strokeStrong = dynamicColor(
        dark: NSColor(hex: 0xFFFFFF, alpha: 0.30),
        light: NSColor(hex: 0x2A2140, alpha: 0.24)
    )
    static let mutedFill = dynamicColor(
        dark: NSColor(hex: 0xFFFFFF, alpha: 0.15),
        light: NSColor(hex: 0x2A2140, alpha: 0.10)
    )
    static let interactiveFill = dynamicColor(
        dark: NSColor(hex: 0xFFFFFF, alpha: 0.07),
        light: NSColor(hex: 0x2A2140, alpha: 0.045)
    )
    static let interactivePressedFill = dynamicColor(
        dark: NSColor(hex: 0xFFFFFF, alpha: 0.16),
        light: NSColor(hex: 0x2A2140, alpha: 0.095)
    )
    static let accentGlyph = Color(nsColor: NSColor(hex: 0x2A1F48))
    static let overlayText = Color.white
    static let overlaySecondaryText = Color.white.opacity(0.72)
    static let overlayTertiaryText = Color.white.opacity(0.52)
    static let overlayFill = Color.black.opacity(0.64)
    static let overlaySubtleFill = Color.white.opacity(0.12)

    static func accentColor(_ accent: WidgetAccent) -> Color {
        switch accent {
        case .coral:
            dynamicColor(dark: NSColor(hex: 0xFF9DBB), light: NSColor(hex: 0xFF7AA2))
        case .amber:
            dynamicColor(dark: NSColor(hex: 0xFFD37C), light: NSColor(hex: 0xF5B53C))
        case .green:
            dynamicColor(dark: NSColor(hex: 0x8BE8C4), light: NSColor(hex: 0x36C99B))
        case .cyan:
            dynamicColor(dark: NSColor(hex: 0x7CD7FF), light: NSColor(hex: 0x36B6E8))
        case .violet:
            dynamicColor(dark: NSColor(hex: 0xC4A8FF), light: NSColor(hex: 0x9B7BF0))
        }
    }

    static func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Baloo 2", size: size).weight(weight)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Nunito", size: size).weight(weight)
    }

    static func cardFill(accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.22),
                card.opacity(0.98),
                dynamicColor(
                    dark: NSColor(hex: 0x241D45, alpha: 0.58),
                    light: NSColor(hex: 0xFFFFFF, alpha: 0.96)
                )
            ],
            startPoint: UnitPoint(x: 0.08, y: 0.0),
            endPoint: UnitPoint(x: 0.96, y: 1.0)
        )
    }

    static func accentFill(_ accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                accent,
                accent.opacity(0.76),
                Color.white.opacity(0.86)
            ],
            startPoint: UnitPoint(x: 0.0, y: 0.0),
            endPoint: UnitPoint(x: 1.0, y: 1.0)
        )
    }

    static func progressFill(_ accent: Color) -> some ShapeStyle {
        accent.shadow(.drop(color: accent.opacity(0.55), radius: 7))
    }

    static func dynamicColor(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

extension Color {
    init?(hexRGB: String) {
        let trimmed = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self = Color(nsColor: NSColor(hex: value))
    }

    var hexRGBString: String? {
        guard
            let color = NSColor(self).usingColorSpace(.sRGB)
        else {
            return nil
        }

        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
