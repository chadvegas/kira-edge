import SwiftUI

struct LauncherWidgetView: View {
    let items: [LauncherItem]
    let accent: Color
    let onLaunch: (LauncherItem) -> Void

    private var rows: [[LauncherItem]] {
        stride(from: 0, to: items.count, by: 2).map { index in
            Array(items[index..<min(index + 2, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: 11) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 11) {
                    ForEach(rows[rowIndex]) { item in
                        LauncherGridItemView(
                            item: item,
                            accent: accent,
                            onLaunch: onLaunch
                        )
                    }

                    if rows[rowIndex].count == 1 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

private struct LauncherGridItemView: View {
    let item: LauncherItem
    let accent: Color
    let onLaunch: (LauncherItem) -> Void

    var body: some View {
        Button {
            onLaunch(item)
        } label: {
            VStack(spacing: 9) {
                AnimeIconBadge(symbolName: item.symbolName, accent: accent, size: 40, iconSize: 21)

                Text(item.title)
                    .font(EdgeTheme.bodyFont(size: 15, weight: .black))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
        }
        .buttonStyle(LauncherButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

struct LauncherButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? EdgeTheme.interactivePressedFill : EdgeTheme.interactiveFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(EdgeTheme.stroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.10 : 0.18), radius: 12, y: 8)
    }
}
