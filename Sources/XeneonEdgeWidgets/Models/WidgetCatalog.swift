import Foundation
import SwiftUI

enum WidgetCatalogCategory: String, CaseIterable, Identifiable {
    case web
    case essentials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: "Web"
        case .essentials: "Essentials"
        }
    }
}

struct WidgetCatalogItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let category: WidgetCatalogCategory
    let kind: WidgetKind
    let size: WidgetSize
    let accent: WidgetAccent
    let web: WebTileConfig?

    func makeTile() -> WidgetTile {
        WidgetTile(
            kind: kind,
            title: title,
            size: size,
            accent: accent,
            web: web
        )
    }
}

extension WidgetCatalogItem {
    static let catalog: [WidgetCatalogItem] = [
        web(
            id: "youtube",
            title: "YouTube",
            subtitle: "Video",
            symbolName: "play.rectangle.fill",
            urlString: "https://www.youtube.com",
            zoom: 0.7,
            accent: .coral
        ),
        web(
            id: "youtube-tv",
            title: "YouTube TV",
            subtitle: "Device sign-in",
            symbolName: "tv.and.mediabox",
            urlString: "https://www.youtube.com/tv",
            zoom: 0.86,
            accent: .coral
        ),
        web(
            id: "youtube-mobile",
            title: "YouTube Mobile",
            subtitle: "Touch layout",
            symbolName: "iphone",
            urlString: "https://m.youtube.com",
            zoom: 0.78,
            accent: .coral
        ),
        web(
            id: "google",
            title: "Google",
            subtitle: "Search",
            symbolName: "magnifyingglass",
            urlString: "https://www.google.com",
            zoom: 0.75,
            accent: .cyan
        ),
        web(
            id: "home-assistant",
            title: "Home Assistant",
            subtitle: "Local control",
            symbolName: "house.fill",
            urlString: "http://homeassistant.local:8123",
            zoom: 0.78,
            accent: .green
        ),
        web(
            id: "calendar",
            title: "Calendar",
            subtitle: "Google web",
            symbolName: "calendar",
            urlString: "https://calendar.google.com",
            zoom: 0.72,
            accent: .cyan
        ),
        web(
            id: "github",
            title: "GitHub",
            subtitle: "Code",
            symbolName: "chevron.left.forwardslash.chevron.right",
            urlString: "https://github.com",
            zoom: 0.75,
            accent: .violet
        ),
        web(
            id: "spotify",
            title: "Spotify",
            subtitle: "Music web",
            symbolName: "music.note.list",
            urlString: "https://open.spotify.com",
            zoom: 0.78,
            accent: .green
        ),
        web(
            id: "plex",
            title: "Plex",
            subtitle: "Media",
            symbolName: "tv",
            urlString: "https://app.plex.tv",
            zoom: 0.75,
            accent: .amber
        ),
        web(
            id: "weather",
            title: "Weather",
            subtitle: "Forecast",
            symbolName: "cloud.sun",
            urlString: "https://weather.com/weather/today",
            zoom: 0.78,
            accent: .cyan
        ),
        native(
            id: "system",
            title: "System",
            subtitle: "CPU, memory, disk",
            symbolName: "cpu",
            kind: .system,
            size: .wide,
            accent: .cyan
        ),
        native(
            id: "power",
            title: "Power",
            subtitle: "Battery",
            symbolName: "battery.100percent",
            kind: .power,
            size: .standard,
            accent: .green
        ),
        native(
            id: "clock",
            title: "Clock",
            subtitle: "Time",
            symbolName: "clock",
            kind: .clock,
            size: .standard,
            accent: .coral
        ),
        native(
            id: "note",
            title: "Note",
            subtitle: "Pinned text",
            symbolName: "text.alignleft",
            kind: .note,
            size: .standard,
            accent: .violet
        ),
        native(
            id: "launcher",
            title: "Launcher",
            subtitle: "Apps grid",
            symbolName: "square.grid.2x2",
            kind: .launcher,
            size: .wide,
            accent: .amber
        )
    ]

    private static func web(
        id: String,
        title: String,
        subtitle: String,
        symbolName: String,
        urlString: String,
        zoom: Double,
        accent: WidgetAccent
    ) -> WidgetCatalogItem {
        WidgetCatalogItem(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            category: .web,
            kind: .web,
            size: .wide,
            accent: accent,
            web: WebTileConfig(title: title, urlString: urlString, zoom: zoom)
        )
    }

    private static func native(
        id: String,
        title: String,
        subtitle: String,
        symbolName: String,
        kind: WidgetKind,
        size: WidgetSize,
        accent: WidgetAccent
    ) -> WidgetCatalogItem {
        WidgetCatalogItem(
            id: id,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            category: .essentials,
            kind: kind,
            size: size,
            accent: accent,
            web: nil
        )
    }
}

@MainActor
extension DashboardStore {
    func addCatalogItem(_ item: WidgetCatalogItem) {
        addTile(item.makeTile())
    }
}
