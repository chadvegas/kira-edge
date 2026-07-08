import SwiftUI

struct NoteWidgetView: View {
    let text: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.isEmpty ? "Ready" : text)
                .font(EdgeTheme.displayFont(size: 34, weight: .heavy))
                .foregroundStyle(EdgeTheme.primaryText)
                .lineLimit(5)
                .minimumScaleFactor(0.55)

            Text("Pinned command note")
                .font(EdgeTheme.bodyFont(size: 14, weight: .heavy))
                .foregroundStyle(EdgeTheme.secondaryText)
                .lineLimit(1)

            Spacer()

            AnimeWell(padding: 10) {
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(index == 0 ? accent : EdgeTheme.mutedFill)
                            .shadow(color: index == 0 ? accent.opacity(0.55) : .clear, radius: 7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 9)
                    }
                }
            }
        }
    }
}
