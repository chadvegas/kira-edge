import SwiftUI

struct PowerWidgetView: View {
    let snapshot: SystemSnapshot
    let accent: Color

    private var level: Double {
        snapshot.batteryPercent ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(snapshot.batteryPercent.map(EdgeFormatters.percent) ?? "AC")
                    .font(EdgeTheme.displayFont(size: 54, weight: .heavy))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                Image(systemName: snapshot.isCharging ? "bolt.fill" : "powerplug")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.58), radius: 8)
            }

            Text(snapshot.isCharging ? "Charging from AC power" : "Battery power")
                .font(EdgeTheme.bodyFont(size: 16, weight: .heavy))
                .foregroundStyle(EdgeTheme.secondaryText)
                .lineLimit(1)

            BatteryBar(level: level, accent: accent)
                .frame(height: 58)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                AnimeStatChip(title: "Level", value: EdgeFormatters.percent(level), symbolName: "battery.100percent", accent: accent)
                AnimeStatChip(title: "Source", value: snapshot.isCharging ? "AC" : "Battery", symbolName: "bolt", accent: accent)
                AnimeStatChip(title: "State", value: snapshot.batteryPercent == nil ? "Desktop" : "Portable", symbolName: "powerplug", accent: accent)
                AnimeStatChip(title: "Health", value: level > 0.18 ? "Ready" : "Low", symbolName: "heart", accent: accent)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct BatteryBar: View {
    let level: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let nubWidth: CGFloat = 10
            let shellWidth = proxy.size.width - nubWidth - 5
            let fillWidth = max(12, shellWidth * min(max(level, 0), 1))

            HStack(spacing: 5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(EdgeTheme.strokeStrong, lineWidth: 3)
                        .background(EdgeTheme.interactiveFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(EdgeTheme.accentFill(accent))
                        .frame(width: fillWidth)
                        .padding(6)
                        .shadow(color: accent.opacity(0.62), radius: 12)
                }
                .frame(width: shellWidth)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(EdgeTheme.strokeStrong)
                    .frame(width: nubWidth, height: proxy.size.height * 0.42)
            }
        }
    }
}
