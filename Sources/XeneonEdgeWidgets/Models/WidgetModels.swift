import AppKit
import Foundation
import SwiftUI

enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case clock
    case system
    case power
    case launcher
    case note
    case web

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Clock"
        case .system: "System"
        case .power: "Power"
        case .launcher: "Apps"
        case .note: "Note"
        case .web: "Web"
        }
    }

    var symbolName: String {
        switch self {
        case .clock: "clock"
        case .system: "cpu"
        case .power: "battery.100percent"
        case .launcher: "square.grid.2x2"
        case .note: "text.alignleft"
        case .web: "globe"
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetKind(rawValue: raw) ?? .system
    }
}

enum WidgetSize: String, CaseIterable, Identifiable, Codable {
    case compact
    case standard
    case wide

    var id: String { rawValue }

    var widthWeight: CGFloat {
        switch self {
        case .compact: 0.8
        case .standard: 1.0
        case .wide: 1.65
        }
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetSize(rawValue: raw) ?? .standard
    }
}

enum WidgetAccent: String, CaseIterable, Identifiable, Codable {
    case coral
    case amber
    case green
    case cyan
    case violet

    var id: String { rawValue }

    var color: Color {
        EdgeTheme.accentColor(self)
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetAccent(rawValue: raw) ?? .cyan
    }
}

struct WidgetTile: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: WidgetKind
    var title: String
    var size: WidgetSize
    var accent: WidgetAccent
    var customAccentHex: String?
    var isEnabled: Bool
    var web: WebTileConfig?

    init(
        id: UUID = UUID(),
        kind: WidgetKind,
        title: String? = nil,
        size: WidgetSize = .standard,
        accent: WidgetAccent,
        customAccentHex: String? = nil,
        isEnabled: Bool = true,
        web: WebTileConfig? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.size = size
        self.accent = accent
        self.customAccentHex = customAccentHex
        self.isEnabled = isEnabled
        self.web = web
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case size
        case accent
        case customAccentHex
        case isEnabled
        case web
    }

    // Tolerant decode so a single forward-incompatible field degrades to a
    // defaulted tile rather than throwing out of the whole profile decode.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The "app on the Edge" tile kind was removed. Old profiles may still hold
        // tiles with kind == "app"; decode the raw kind first and throw for those so
        // the enclosing LossyArray<WidgetTile> silently DROPS the tile instead of
        // WidgetKind.init(from:) mapping the unknown value to .system (a broken tile).
        let rawKind = try container.decode(String.self, forKey: .kind)
        if rawKind == "app" {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "The 'app' widget kind has been removed."
            )
        }
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = WidgetKind(rawValue: rawKind) ?? .system
        size = try container.decodeIfPresent(WidgetSize.self, forKey: .size) ?? .standard
        accent = try container.decodeIfPresent(WidgetAccent.self, forKey: .accent) ?? .cyan
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? kind.title
        customAccentHex = try container.decodeIfPresent(String.self, forKey: .customAccentHex)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        web = try container.decodeIfPresent(WebTileConfig.self, forKey: .web)
    }

    var displayTitle: String {
        switch kind {
        case .web:
            web?.title.isEmpty == false ? web?.title ?? title : title
        default:
            title
        }
    }

    var accentColor: Color {
        if let customAccentHex, let color = Color(hexRGB: customAccentHex) {
            return color
        }
        return accent.color
    }

    mutating func setCustomAccentColor(_ color: Color) {
        customAccentHex = color.hexRGBString
    }
}

struct DashboardPage: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var tiles: [WidgetTile]

    init(id: UUID = UUID(), title: String, tiles: [WidgetTile]) {
        self.id = id
        self.title = title
        self.tiles = tiles
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case tiles
    }

    // Tolerant decode: a single un-decodable tile is dropped (via LossyArray)
    // rather than failing the page — and ultimately the whole saved profile.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        tiles = (try container.decodeIfPresent(LossyArray<WidgetTile>.self, forKey: .tiles))?.elements ?? []
    }
}

struct WebTileConfig: Codable, Equatable {
    var title: String
    var urlString: String
    var zoom: Double
    var reloadInterval: TimeInterval
    var usesDesktopUserAgent: Bool
    var injectsReadableCSS: Bool

    init(
        title: String,
        urlString: String,
        zoom: Double = 0.8,
        reloadInterval: TimeInterval = 0,
        usesDesktopUserAgent: Bool = true,
        injectsReadableCSS: Bool = false
    ) {
        self.title = title
        self.urlString = urlString
        self.zoom = zoom
        self.reloadInterval = reloadInterval
        self.usesDesktopUserAgent = usesDesktopUserAgent
        self.injectsReadableCSS = injectsReadableCSS
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case urlString
        case zoom
        case reloadInterval
        case usesDesktopUserAgent
        case injectsReadableCSS
    }

    // Tolerant decode so a forward-incompatible field degrades to a defaulted
    // value rather than throwing out of the whole profile decode.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString) ?? ""
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 0.8
        reloadInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .reloadInterval) ?? 0
        usesDesktopUserAgent = try container.decodeIfPresent(Bool.self, forKey: .usesDesktopUserAgent) ?? true
        injectsReadableCSS = try container.decodeIfPresent(Bool.self, forKey: .injectsReadableCSS) ?? false
    }

    var url: URL? {
        if let direct = URL(string: urlString), direct.scheme != nil {
            return direct
        }

        return URL(string: "https://\(urlString)")
    }
}

enum DashboardPreset: String, CaseIterable, Identifiable {
    case command
    case media
    case work
    case streaming
    case aiOps
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "Command"
        case .media: "Media"
        case .work: "Work"
        case .streaming: "Streaming"
        case .aiOps: "AI Ops"
        case .home: "Home"
        }
    }

    var symbolName: String {
        switch self {
        case .command: "rectangle.3.group"
        case .media: "play.rectangle"
        case .work: "briefcase"
        case .streaming: "dot.radiowaves.left.and.right"
        case .aiOps: "sparkles"
        case .home: "house"
        }
    }

    var shortLabel: String {
        switch self {
        case .command: "Cmd"
        case .media: "Media"
        case .work: "Work"
        case .streaming: "Live"
        case .aiOps: "AI"
        case .home: "Home"
        }
    }

    var intent: String {
        switch self {
        case .command: "Daily controls, launchers, quick notes, and system pulse."
        case .media: "Entertainment controls for video, music, and playback."
        case .work: "Calendar, focused work apps, and operational status."
        case .streaming: "Live production shortcuts, chat, media, and scenes."
        case .aiOps: "AI tools, coding surfaces, project status, and machine health."
        case .home: "Home Assistant, family calendar, weather, and house controls."
        }
    }
}

enum EdgeAppearanceMode: String, CaseIterable, Identifiable, Codable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    var symbolName: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    func resolvedColorScheme(system systemColorScheme: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? systemColorScheme
    }
}

enum MotionBackdropMode: String, CaseIterable, Identifiable, Codable {
    case aurora
    case sakura
    case sparkle
    case nebula

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: "Aurora Drift"
        case .sakura: "Sakura Bloom"
        case .sparkle: "Sparkle Bokeh"
        case .nebula: "Nebula Field"
        }
    }

    var shortTitle: String {
        switch self {
        case .aurora: "Aurora"
        case .sakura: "Sakura"
        case .sparkle: "Sparkle"
        case .nebula: "Nebula"
        }
    }

    var symbolName: String {
        switch self {
        case .aurora: "sparkles"
        case .sakura: "camera.macro"
        case .sparkle: "wand.and.stars"
        case .nebula: "moon.stars.fill"
        }
    }
}

enum MotionTileMaterial: String, CaseIterable, Identifiable, Codable {
    case frosted
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: "Frosted"
        case .solid: "Solid"
        }
    }

    var symbolName: String {
        switch self {
        case .frosted: "square.on.square.dashed"
        case .solid: "rectangle.fill"
        }
    }
}

struct MotionBackdropPreferences: Codable, Equatable {
    var mode: MotionBackdropMode
    var tileMaterial: MotionTileMaterial
    var speed: Double
    var intensity: Double
    var isPaused: Bool

    static let `default` = MotionBackdropPreferences(
        mode: .sakura,
        tileMaterial: .frosted,
        speed: 1.0,
        intensity: 1.0,
        isPaused: false
    )
}

struct LauncherItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var appName: String
    var symbolName: String

    init(id: UUID = UUID(), title: String, appName: String, symbolName: String) {
        self.id = id
        self.title = title
        self.appName = appName
        self.symbolName = symbolName
    }
}

struct InstalledApplication: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var appName: String
    var bundleIdentifier: String?
}

/// Decodes an array element-by-element, silently dropping any element whose
/// decode throws (e.g. a tile written by a newer app version). This prevents a
/// single corrupt/forward-incompatible element from failing the entire array.
private struct LossyArray<Element: Codable>: Codable {
    var elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        if let count = container.count {
            result.reserveCapacity(count)
        }
        while !container.isAtEnd {
            // Always advance the cursor: decode the element if possible, otherwise
            // consume it as an opaque value so the loop makes progress and we skip it.
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(AnyDecodableSkip.self)
            }
        }
        elements = result
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for element in elements {
            try container.encode(element)
        }
    }
}

/// Throwaway type used to consume and discard one element from an unkeyed
/// container when its real decode failed, keeping the cursor advancing.
private struct AnyDecodableSkip: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

struct DashboardProfile: Codable, Equatable {
    var noteText: String
    var isPinned: Bool
    var tiles: [WidgetTile]
    var launchers: [LauncherItem]
    var selectedPreset: DashboardPreset.RawValue
    var pagesByPreset: [DashboardPreset.RawValue: [DashboardPage]]?
    var selectedPageIndexByPreset: [DashboardPreset.RawValue: Int]?
    var appearanceMode: EdgeAppearanceMode.RawValue?
    var showsFullDayForecast: Bool?
    var motionBackdropMode: MotionBackdropMode.RawValue?
    var motionTileMaterial: MotionTileMaterial.RawValue?
    var motionSpeed: Double?
    var motionIntensity: Double?
    var motionIsPaused: Bool?
    var googleCalendarClientID: String?
    var selectedCalendarIDs: [String]?
    var uses24HourTime: Bool?
    var forecastRange: String?
    var automationMeetingEnabled: Bool?
    var automationMeetingLeadMinutes: Int?
    var automationMeetingPreset: String?

    init(
        noteText: String,
        isPinned: Bool,
        tiles: [WidgetTile],
        launchers: [LauncherItem],
        selectedPreset: DashboardPreset.RawValue,
        pagesByPreset: [DashboardPreset.RawValue: [DashboardPage]]? = nil,
        selectedPageIndexByPreset: [DashboardPreset.RawValue: Int]? = nil,
        appearanceMode: EdgeAppearanceMode.RawValue? = nil,
        showsFullDayForecast: Bool? = nil,
        motionBackdropMode: MotionBackdropMode.RawValue? = nil,
        motionTileMaterial: MotionTileMaterial.RawValue? = nil,
        motionSpeed: Double? = nil,
        motionIntensity: Double? = nil,
        motionIsPaused: Bool? = nil,
        googleCalendarClientID: String? = nil,
        selectedCalendarIDs: [String]? = nil,
        uses24HourTime: Bool? = nil,
        forecastRange: String? = nil,
        automationMeetingEnabled: Bool? = nil,
        automationMeetingLeadMinutes: Int? = nil,
        automationMeetingPreset: String? = nil
    ) {
        self.noteText = noteText
        self.isPinned = isPinned
        self.tiles = tiles
        self.launchers = launchers
        self.selectedPreset = selectedPreset
        self.pagesByPreset = pagesByPreset
        self.selectedPageIndexByPreset = selectedPageIndexByPreset
        self.appearanceMode = appearanceMode
        self.showsFullDayForecast = showsFullDayForecast
        self.motionBackdropMode = motionBackdropMode
        self.motionTileMaterial = motionTileMaterial
        self.motionSpeed = motionSpeed
        self.motionIntensity = motionIntensity
        self.motionIsPaused = motionIsPaused
        self.googleCalendarClientID = googleCalendarClientID
        self.selectedCalendarIDs = selectedCalendarIDs
        self.uses24HourTime = uses24HourTime
        self.forecastRange = forecastRange
        self.automationMeetingEnabled = automationMeetingEnabled
        self.automationMeetingLeadMinutes = automationMeetingLeadMinutes
        self.automationMeetingPreset = automationMeetingPreset
    }

    private enum CodingKeys: String, CodingKey {
        case noteText
        case isPinned
        case tiles
        case launchers
        case selectedPreset
        case pagesByPreset
        case selectedPageIndexByPreset
        case appearanceMode
        case showsFullDayForecast
        case motionBackdropMode
        case motionTileMaterial
        case motionSpeed
        case motionIntensity
        case motionIsPaused
        case googleCalendarClientID
        case selectedCalendarIDs
        case uses24HourTime
        case forecastRange
        case automationMeetingEnabled
        case automationMeetingLeadMinutes
        case automationMeetingPreset
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteText = try container.decodeIfPresent(String.self, forKey: .noteText) ?? "Ready"
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        tiles = (try container.decodeIfPresent(LossyArray<WidgetTile>.self, forKey: .tiles))?.elements ?? []
        launchers = (try container.decodeIfPresent(LossyArray<LauncherItem>.self, forKey: .launchers))?.elements ?? []
        selectedPreset = try container.decodeIfPresent(DashboardPreset.RawValue.self, forKey: .selectedPreset)
            ?? DashboardPreset.command.rawValue
        pagesByPreset = Self.decodeLossyPagesByPreset(from: container)
        selectedPageIndexByPreset = try container.decodeIfPresent(
            [DashboardPreset.RawValue: Int].self,
            forKey: .selectedPageIndexByPreset
        )
        appearanceMode = try container.decodeIfPresent(EdgeAppearanceMode.RawValue.self, forKey: .appearanceMode)
        showsFullDayForecast = try container.decodeIfPresent(Bool.self, forKey: .showsFullDayForecast)
        motionBackdropMode = try container.decodeIfPresent(MotionBackdropMode.RawValue.self, forKey: .motionBackdropMode)
        motionTileMaterial = try container.decodeIfPresent(MotionTileMaterial.RawValue.self, forKey: .motionTileMaterial)
        motionSpeed = try container.decodeIfPresent(Double.self, forKey: .motionSpeed)
        motionIntensity = try container.decodeIfPresent(Double.self, forKey: .motionIntensity)
        motionIsPaused = try container.decodeIfPresent(Bool.self, forKey: .motionIsPaused)
        googleCalendarClientID = try container.decodeIfPresent(String.self, forKey: .googleCalendarClientID)
        selectedCalendarIDs = try container.decodeIfPresent([String].self, forKey: .selectedCalendarIDs)
        uses24HourTime = try container.decodeIfPresent(Bool.self, forKey: .uses24HourTime)
        forecastRange = try container.decodeIfPresent(String.self, forKey: .forecastRange)
        automationMeetingEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationMeetingEnabled)
        automationMeetingLeadMinutes = try container.decodeIfPresent(Int.self, forKey: .automationMeetingLeadMinutes)
        automationMeetingPreset = try container.decodeIfPresent(String.self, forKey: .automationMeetingPreset)
    }

    /// Dynamic string key used to iterate the `pagesByPreset` dictionary
    /// preset-by-preset so a single bad preset can be skipped.
    private struct PresetKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Decodes `pagesByPreset` one preset at a time, dropping any single preset
    /// (and, via LossyArray, any single page/tile) that fails to decode rather
    /// than throwing out of the whole profile decode and wiping every setting.
    private static func decodeLossyPagesByPreset(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [DashboardPreset.RawValue: [DashboardPage]]? {
        guard let nested = try? container.nestedContainer(
            keyedBy: PresetKey.self,
            forKey: .pagesByPreset
        ) else {
            return nil
        }

        var result: [DashboardPreset.RawValue: [DashboardPage]] = [:]
        for key in nested.allKeys {
            if let pages = try? nested.decode(LossyArray<DashboardPage>.self, forKey: key) {
                result[key.stringValue] = pages.elements
            }
        }
        return result
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(noteText, forKey: .noteText)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(tiles, forKey: .tiles)
        try container.encode(launchers, forKey: .launchers)
        try container.encode(selectedPreset, forKey: .selectedPreset)
        try container.encodeIfPresent(pagesByPreset, forKey: .pagesByPreset)
        try container.encodeIfPresent(selectedPageIndexByPreset, forKey: .selectedPageIndexByPreset)
        try container.encodeIfPresent(appearanceMode, forKey: .appearanceMode)
        try container.encodeIfPresent(showsFullDayForecast, forKey: .showsFullDayForecast)
        try container.encodeIfPresent(motionBackdropMode, forKey: .motionBackdropMode)
        try container.encodeIfPresent(motionTileMaterial, forKey: .motionTileMaterial)
        try container.encodeIfPresent(motionSpeed, forKey: .motionSpeed)
        try container.encodeIfPresent(motionIntensity, forKey: .motionIntensity)
        try container.encodeIfPresent(motionIsPaused, forKey: .motionIsPaused)
        try container.encodeIfPresent(googleCalendarClientID, forKey: .googleCalendarClientID)
        try container.encodeIfPresent(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try container.encodeIfPresent(uses24HourTime, forKey: .uses24HourTime)
        try container.encodeIfPresent(forecastRange, forKey: .forecastRange)
        try container.encodeIfPresent(automationMeetingEnabled, forKey: .automationMeetingEnabled)
        try container.encodeIfPresent(automationMeetingLeadMinutes, forKey: .automationMeetingLeadMinutes)
        try container.encodeIfPresent(automationMeetingPreset, forKey: .automationMeetingPreset)
    }
}

struct SystemSnapshot: Equatable {
    var cpuLoad: Double
    var cpuUser: Double
    var cpuSystem: Double
    var memoryUsed: Double
    var memoryPressure: Double
    var memoryWired: Double
    var memoryCompressed: Double
    var memoryAvailableBytes: Int64?
    var diskUsed: Double
    var diskAvailableBytes: Int64?
    var diskTotalBytes: Int64?
    var batteryPercent: Double?
    var isCharging: Bool
    var localIPAddress: String?
    var publicIPAddress: String?
    var networkUploadBytesPerSecond: Double
    var networkDownloadBytesPerSecond: Double
    var deviceBatteries: [DeviceBatterySnapshot]
    var topProcesses: [ProcessSnapshot]

    static let empty = SystemSnapshot(
        cpuLoad: 0,
        cpuUser: 0,
        cpuSystem: 0,
        memoryUsed: 0,
        memoryPressure: 0,
        memoryWired: 0,
        memoryCompressed: 0,
        memoryAvailableBytes: nil,
        diskUsed: 0,
        diskAvailableBytes: nil,
        diskTotalBytes: nil,
        batteryPercent: nil,
        isCharging: false,
        localIPAddress: nil,
        publicIPAddress: nil,
        networkUploadBytesPerSecond: 0,
        networkDownloadBytesPerSecond: 0,
        deviceBatteries: [],
        topProcesses: []
    )
}

enum DeviceBatterySource: String, Equatable, Sendable {
    case mac
    case ioRegistry
    case bluetoothProfiler
    case bluetoothLE
    case mobileDevice
    case watchRelay
    case unknown

    var title: String {
        switch self {
        case .mac: "Mac"
        case .ioRegistry: "macOS"
        case .bluetoothProfiler: "Bluetooth"
        case .bluetoothLE: "BLE"
        case .mobileDevice: "iOS"
        case .watchRelay: "Watch"
        case .unknown: "Device"
        }
    }
}

struct DeviceBatterySnapshot: Identifiable, Equatable, Sendable {
    var id: String { "\(source.rawValue)-\(name)" }
    var name: String
    var percent: Double
    var isCharging: Bool?
    var kind: String?
    var source: DeviceBatterySource = .unknown
}

struct ProcessSnapshot: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var memoryBytes: Int64
}

struct WeatherSnapshot: Equatable {
    var locationName: String
    var currentTemperature: Double?
    var apparentTemperature: Double?
    var conditionCode: Int?
    var precipitationProbability: Double?
    var windSpeed: Double?
    var highTemperature: Double?
    var lowTemperature: Double?
    var hourly: [HourlyWeather]
    var daily: [DailyForecast] = []
    var lastUpdated: Date?
    var status: String

    static let empty = WeatherSnapshot(
        locationName: "Weather",
        currentTemperature: nil,
        apparentTemperature: nil,
        conditionCode: nil,
        precipitationProbability: nil,
        windSpeed: nil,
        highTemperature: nil,
        lowTemperature: nil,
        hourly: [],
        lastUpdated: nil,
        status: "Weather loading"
    )

    var conditionTitle: String {
        WeatherCodeMapper.title(for: conditionCode)
    }

    var symbolName: String {
        WeatherCodeMapper.symbolName(for: conditionCode)
    }
}

struct HourlyWeather: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var temperature: Double
    var precipitationProbability: Double?
    var conditionCode: Int?

    var symbolName: String {
        WeatherCodeMapper.symbolName(for: conditionCode)
    }
}

struct DailyForecast: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var high: Double
    var low: Double
    var conditionCode: Int?

    var symbolName: String {
        WeatherCodeMapper.symbolName(for: conditionCode)
    }
}

enum ForecastRange: String, CaseIterable, Identifiable, Equatable {
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        }
    }
}

enum WeatherCodeMapper {
    static func title(for code: Int?) -> String {
        guard let code else { return "Forecast" }
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95, 96, 99: return "Storms"
        default: return "Weather"
        }
    }

    static func symbolName(for code: Int?) -> String {
        guard let code else { return "cloud.sun" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun"
        }
    }
}
