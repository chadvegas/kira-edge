import SwiftUI

struct WebWidgetView: View {
    let tile: WidgetTile
    let config: WebTileConfig
    let reloadToken: Int

    var body: some View {
        ZStack {
            WebTileWebView(config: config, reloadToken: reloadToken)
                .clipShape(RoundedRectangle(cornerRadius: EdgeTheme.wellRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EdgeTheme.wellRadius, style: .continuous)
                        .stroke(EdgeTheme.stroke, lineWidth: 1)
                }

            if config.url == nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text("Invalid URL")
                        .font(EdgeTheme.bodyFont(size: 15, weight: .black))
                        .foregroundStyle(EdgeTheme.overlayText)
                    Text(config.urlString)
                        .font(.caption)
                        .foregroundStyle(EdgeTheme.overlaySecondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.72))
            }
        }
        .background(EdgeTheme.cardWell, in: RoundedRectangle(cornerRadius: EdgeTheme.wellRadius, style: .continuous))
    }
}
