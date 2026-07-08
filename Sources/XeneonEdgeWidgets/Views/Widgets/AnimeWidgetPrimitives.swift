import SwiftUI

struct AnimeWell<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(EdgeTheme.cardWell, in: RoundedRectangle(cornerRadius: EdgeTheme.wellRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EdgeTheme.wellRadius, style: .continuous)
                    .stroke(EdgeTheme.stroke, lineWidth: 1)
            }
    }
}

struct AnimeStatChip: View {
    let title: String
    let value: String
    var symbolName: String?
    var accent: Color?
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        HStack(spacing: 7) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 12 * textScale, weight: .black))
                    .foregroundStyle(accent ?? EdgeTheme.secondaryText)
                    .frame(width: 15)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(EdgeTheme.bodyFont(size: 9 * textScale, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .lineLimit(1)

                Text(value)
                    .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .heavy))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(EdgeTheme.interactiveFill, in: RoundedRectangle(cornerRadius: EdgeTheme.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EdgeTheme.chipRadius, style: .continuous)
                .stroke(EdgeTheme.stroke, lineWidth: 1)
        }
    }
}

struct AnimeProgressBar: View {
    let title: String
    let value: Double
    let accent: Color
    var trailingText: String?
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(EdgeTheme.bodyFont(size: 13 * textScale, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)
                Spacer()
                Text(trailingText ?? EdgeFormatters.percent(value))
                    .font(EdgeTheme.bodyFont(size: 13 * textScale, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(EdgeTheme.mutedFill)
                    Capsule()
                        .fill(EdgeTheme.accentFill(accent))
                        .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
                        .shadow(color: accent.opacity(0.58), radius: 8)
                }
            }
            .frame(height: 9)
        }
    }
}

struct AnimeIconBadge: View {
    let symbolName: String
    let accent: Color
    var size: CGFloat = 42
    var iconSize: CGFloat = 20

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: iconSize, weight: .black))
            .foregroundStyle(EdgeTheme.accentGlyph)
            .frame(width: size, height: size)
            .background(EdgeTheme.accentFill(accent), in: RoundedRectangle(cornerRadius: EdgeTheme.iconChipRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EdgeTheme.iconChipRadius, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.55), radius: 13, x: 0, y: 5)
    }
}
