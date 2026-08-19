import Foundation

enum HarnessUsageReader {
    static let refreshInterval: Duration = .seconds(600)
    // Omitting --provider makes CodexBar honor its enabled-provider toggles.
    private static let commandArguments = [
        "usage",
        "--format", "json",
        "--no-color",
        "--web-timeout", "5"
    ]

    private static let executableCandidates = [
        "/opt/homebrew/bin/codexbar",
        "/usr/local/bin/codexbar",
        "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"
    ]

    static func snapshot() async -> HarnessUsageSnapshot {
        guard let executable = executableURL() else {
            return HarnessUsageSnapshot(
                entries: [],
                retrievedAt: Date(),
                status: "CodexBar CLI unavailable"
            )
        }

        let output = await SystemStatsReader.run(
            executable.path,
            commandArguments,
            timeout: 20
        )
        guard let data = output.data(using: .utf8), !data.isEmpty else {
            return HarnessUsageSnapshot(
                entries: [],
                retrievedAt: Date(),
                status: "Usage refresh timed out"
            )
        }

        return parse(data, retrievedAt: Date())
    }

    static func parse(_ data: Data, retrievedAt: Date = Date()) -> HarnessUsageSnapshot {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let records = object as? [Any]
        else {
            return HarnessUsageSnapshot(
                entries: [],
                retrievedAt: retrievedAt,
                status: "Usage data unavailable"
            )
        }

        var entries = records.compactMap { record -> HarnessUsageEntry? in
            guard
                let record = record as? [String: Any],
                let provider = record["provider"] as? String
            else {
                return nil
            }

            let isUnavailable = record["error"] != nil && !(record["error"] is NSNull)
            let windows = (record["usage"] as? [String: Any])
                .map { usageWindows(from: $0, provider: provider) } ?? []
            guard !windows.isEmpty || isUnavailable else { return nil }

            return HarnessUsageEntry(
                id: provider,
                title: displayTitle(for: provider),
                windows: windows,
                status: isUnavailable ? "Unavailable" : nil
            )
        }

        entries.sort { lhs, rhs in
            let leftRank = providerRank[lhs.id.lowercased()] ?? Int.max
            let rightRank = providerRank[rhs.id.lowercased()] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return HarnessUsageSnapshot(
            entries: entries,
            retrievedAt: retrievedAt,
            status: entries.isEmpty ? "No usage data available" : "Updated"
        )
    }

    private static var providerRank: [String: Int] {
        [
            "codex": 0,
            "claude": 1,
            "gemini": 2,
            "cursor": 3,
            "kimi": 4,
            "grok": 5,
            "perplexity": 6,
            "deepseek": 7,
            "notion": 8
        ]
    }

    private static func executableURL() -> URL? {
        executableCandidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func displayTitle(for provider: String) -> String {
        switch provider.lowercased() {
        case "codex": "Codex"
        case "claude": "Claude"
        case "gemini": "Gemini"
        case "cursor": "Cursor"
        case "kimi": "Kimi"
        case "grok": "Grok"
        case "perplexity": "Perplexity"
        case "deepseek": "DeepSeek"
        case "notion": "Notion"
        default:
            provider
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private static func usageWindows(
        from usage: [String: Any],
        provider: String
    ) -> [HarnessUsageWindow] {
        var windows: [HarnessUsageWindow] = []

        for key in ["primary", "secondary", "tertiary"] {
            guard let value = usage[key] as? [String: Any] else { continue }
            guard let window = makeWindow(
                id: "\(provider)-\(key)",
                title: title(for: key, window: value),
                value: value
            ) else {
                continue
            }
            windows.append(window)
        }

        if let extras = usage["extraRateWindows"] as? [Any] {
            for (index, extra) in extras.enumerated() {
                guard let extra = extra as? [String: Any] else { continue }
                let window = (extra["window"] as? [String: Any]) ?? extra

                let extraTitle = extra["title"] as? String ?? "Additional"
                guard let usageWindow = makeWindow(
                    id: "\(provider)-extra-\(index)",
                    title: extraTitle,
                    value: window
                ) else {
                    continue
                }
                windows.append(usageWindow)
            }
        }

        return Array(windows.prefix(3))
    }

    private static func makeWindow(
        id: String,
        title: String,
        value: [String: Any]
    ) -> HarnessUsageWindow? {
        let usedPercent = number(value["usedPercent"])
            .map { min(max($0, 0), 100) }
        let resetsAt = date(value["resetsAt"])
        let resetDescription = value["resetDescription"] as? String

        guard usedPercent != nil || resetsAt != nil || resetDescription != nil else {
            return nil
        }

        return HarnessUsageWindow(
            id: id,
            title: title,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            resetDescription: resetDescription
        )
    }

    private static func title(for key: String, window: [String: Any]) -> String {
        if let duration = number(window["windowMinutes"]) {
            switch duration {
            case 0..<120: return "Short"
            case 120..<1_500: return "Daily"
            case 1_500..<11_000: return "Weekly"
            default: return "Monthly"
            }
        }

        switch key {
        case "primary": return "Primary"
        case "secondary": return "Secondary"
        default: return "Tertiary"
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}
