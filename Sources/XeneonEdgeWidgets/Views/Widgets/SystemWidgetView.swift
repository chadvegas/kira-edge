import SwiftUI

struct SystemWidgetView: View {
    let snapshot: SystemSnapshot
    let harnessUsage: HarnessUsageSnapshot
    let accent: Color
    @Environment(\.privacyMode) private var privacyMode
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 390

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                if isWide {
                    HStack(alignment: .top, spacing: 13) {
                        HStack(spacing: 12) {
                            SystemGauge(
                                title: "CPU",
                                value: snapshot.cpuLoad,
                                subtitle: "\(EdgeFormatters.percent(snapshot.cpuUser)) user",
                                accent: accent
                            )
                            SystemGauge(
                                title: "Pressure",
                                value: snapshot.memoryPressure,
                                subtitle: "Memory",
                                accent: accent.opacity(0.88)
                            )
                        }
                        .frame(width: min(245, proxy.size.width * 0.40))

                        metricStack
                    }
                } else {
                    HStack(spacing: 12) {
                        SystemGauge(
                            title: "CPU",
                            value: snapshot.cpuLoad,
                            subtitle: "\(EdgeFormatters.percent(snapshot.cpuUser)) user",
                            accent: accent
                        )
                        SystemGauge(
                            title: "Pressure",
                            value: snapshot.memoryPressure,
                            subtitle: "Memory",
                            accent: accent.opacity(0.88)
                        )
                    }

                    metricStack
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: isWide ? 4 : 2), spacing: 8) {
                    AnimeStatChip(
                        title: "Battery",
                        value: snapshot.batteryPercent.map(EdgeFormatters.percent) ?? "AC",
                        symbolName: snapshot.isCharging ? "bolt.fill" : "battery.100percent",
                        accent: accent
                    )
                    AnimeStatChip(
                        title: "Upload",
                        value: EdgeFormatters.byteRate(snapshot.networkUploadBytesPerSecond),
                        symbolName: "arrow.up",
                        accent: accent
                    )
                    AnimeStatChip(
                        title: "Download",
                        value: EdgeFormatters.byteRate(snapshot.networkDownloadBytesPerSecond),
                        symbolName: "arrow.down",
                        accent: accent
                    )
                    AnimeStatChip(
                        title: "Disk Free",
                        value: EdgeFormatters.bytes(snapshot.diskAvailableBytes),
                        symbolName: "internaldrive",
                        accent: accent
                    )
                    if isWide {
                        AnimeStatChip(
                            title: "Public IP",
                            value: privacyMode ? PrivacyMask.ip : (snapshot.publicIPAddress ?? "Unavailable"),
                            symbolName: "globe",
                            accent: accent
                        )
                    }
                }

                if !snapshot.deviceBatteries.isEmpty {
                    AnimeWell(padding: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Connected Power")
                                .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(EdgeTheme.tertiaryText)
                                .textCase(.uppercase)

                            ForEach(snapshot.deviceBatteries.prefix(isWide ? 4 : 2)) { device in
                                DeviceBatteryRow(device: device, accent: accent)
                            }
                        }
                    }
                } else if isWide {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone.gen3")
                        Text("Device batteries appear when macOS exposes them")
                    }
                    .font(EdgeTheme.bodyFont(size: 11 * textScale, weight: .bold))
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .lineLimit(1)
                }

                if !snapshot.topProcesses.isEmpty && isWide {
                    AnimeWell(padding: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Top Memory")
                                .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(EdgeTheme.tertiaryText)
                                .textCase(.uppercase)

                            ForEach(snapshot.topProcesses.prefix(3)) { process in
                                HStack(spacing: 6) {
                                    Text(process.name)
                                        .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .bold))
                                        .foregroundStyle(EdgeTheme.secondaryText)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(EdgeFormatters.bytes(process.memoryBytes))
                                        .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .heavy))
                                        .foregroundStyle(EdgeTheme.primaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                HarnessUsageSection(snapshot: harnessUsage, accent: accent, isWide: isWide)

                Spacer(minLength: 0)

                Label(privacyMode ? PrivacyMask.ip : (snapshot.localIPAddress ?? "Offline"), systemImage: "network")
                    .font(EdgeTheme.bodyFont(size: 14 * textScale, weight: .heavy))
                    .foregroundStyle(EdgeTheme.secondaryText)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var metricStack: some View {
        VStack(spacing: 8) {
            SplitMetricBar(
                title: "CPU",
                leadingTitle: "User",
                leadingValue: snapshot.cpuUser,
                trailingTitle: "System",
                trailingValue: snapshot.cpuSystem,
                accent: accent
            )

            SplitMetricBar(
                title: "Memory",
                leadingTitle: "Used",
                leadingValue: snapshot.memoryUsed,
                trailingTitle: "Compressed",
                trailingValue: snapshot.memoryCompressed,
                accent: accent
            )

            AnimeProgressBar(title: "Disk", value: snapshot.diskUsed, accent: accent)
        }
    }
}

private struct HarnessUsageSection: View {
    let snapshot: HarnessUsageSnapshot
    let accent: Color
    let isWide: Bool
    @Environment(\.widgetTextScale) private var textScale

    private var visibleEntries: ArraySlice<HarnessUsageEntry> {
        snapshot.entries.prefix(isWide ? snapshot.entries.count : 2)
    }

    var body: some View {
        AnimeWell(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("Harness Usage", systemImage: "chart.bar.xaxis")
                        .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(EdgeTheme.tertiaryText)
                        .textCase(.uppercase)

                    Spacer()

                    if !snapshot.entries.isEmpty {
                        Text("\(snapshot.entries.count) sources")
                            .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .bold))
                            .foregroundStyle(EdgeTheme.tertiaryText)
                    }
                }

                if snapshot.entries.isEmpty {
                    Text(snapshot.status)
                        .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .bold))
                        .foregroundStyle(EdgeTheme.secondaryText)
                        .lineLimit(1)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: isWide ? 2 : 1),
                        spacing: 6
                    ) {
                        ForEach(visibleEntries) { entry in
                            HarnessUsageCard(entry: entry, accent: accent)
                        }
                    }

                    if !isWide, snapshot.entries.count > visibleEntries.count {
                        Text("+\(snapshot.entries.count - visibleEntries.count) more on the wide tile")
                            .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .bold))
                            .foregroundStyle(EdgeTheme.tertiaryText)
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    if snapshot.status != "Updated" {
                        Text(snapshot.status)
                    } else if let retrievedAt = snapshot.retrievedAt {
                        Text("Updated \(retrievedAt, style: .relative)")
                    } else {
                        Text(snapshot.status)
                    }
                }
                .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .bold))
                .foregroundStyle(EdgeTheme.tertiaryText)
                .lineLimit(1)
            }
        }
    }
}

private struct HarnessUsageCard: View {
    let entry: HarnessUsageEntry
    let accent: Color
    @Environment(\.widgetTextScale) private var textScale

    private var primaryWindow: HarnessUsageWindow? {
        entry.windows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.title)
                    .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .heavy))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let usedPercent = primaryWindow?.usedPercent {
                    Text("\(Int(usedPercent.rounded()))%")
                        .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .black))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                }
            }

            if let window = primaryWindow {
                HStack(spacing: 5) {
                    Text(window.title)
                    if let description = window.resetDescription {
                        Text(description)
                            .lineLimit(1)
                    } else if let resetsAt = window.resetsAt {
                        Text("resets \(resetsAt, style: .relative)")
                            .lineLimit(1)
                    }
                }
                .font(EdgeTheme.bodyFont(size: 9 * textScale, weight: .bold))
                .foregroundStyle(EdgeTheme.tertiaryText)
            } else if let status = entry.status {
                Text(status)
                    .font(EdgeTheme.bodyFont(size: 9 * textScale, weight: .bold))
                    .foregroundStyle(EdgeTheme.tertiaryText)
            }

            if entry.windows.count > 1 {
                HStack(spacing: 5) {
                    ForEach(entry.windows.dropFirst().prefix(2)) { window in
                        Text("\(window.title) \(formattedPercent(window.usedPercent))")
                            .lineLimit(1)
                    }
                }
                .font(EdgeTheme.bodyFont(size: 9 * textScale, weight: .bold))
                .foregroundStyle(accent.opacity(0.72))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(EdgeTheme.mutedFill.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }
}

private struct DeviceBatteryRow: View {
    let device: DeviceBatterySnapshot
    let accent: Color
    @Environment(\.privacyMode) private var privacyMode
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 11 * textScale, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 16)

            Text(privacyMode ? PrivacyMask.deviceName(device.name, kind: device.kind) : device.name)
                .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .bold))
                .foregroundStyle(EdgeTheme.secondaryText)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 5) {
                if device.isCharging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9 * textScale, weight: .black))
                        .foregroundStyle(accent)
                }

                Text(device.source.title)
                    .font(EdgeTheme.bodyFont(size: 9 * textScale, weight: .black))
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(EdgeFormatters.percent(device.percent))
                    .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .heavy))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .monospacedDigit()
            }
        }
    }

    private var symbolName: String {
        let label = "\(device.name) \(device.kind ?? "")".lowercased()
        if label.contains("iphone") { return "iphone.gen3" }
        if label.contains("watch") { return "applewatch" }
        if label.contains("airpods") || label.contains("head") { return "airpodspro" }
        if label.contains("mouse") { return "computermouse" }
        if label.contains("keyboard") { return "keyboard" }
        return "battery.100percent"
    }
}

private struct SplitMetricBar: View {
    let title: String
    let leadingTitle: String
    let leadingValue: Double
    let trailingTitle: String
    let trailingValue: Double
    let accent: Color
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(EdgeTheme.bodyFont(size: 13 * textScale, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)

                Spacer()

                Text("\(leadingTitle) \(EdgeFormatters.percent(leadingValue))")
                    .foregroundStyle(accent)
                Text("\(trailingTitle) \(EdgeFormatters.percent(trailingValue))")
                    .foregroundStyle(accent.opacity(0.62))
            }
            .font(EdgeTheme.bodyFont(size: 11 * textScale, weight: .black))
            .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(EdgeTheme.mutedFill)

                    Capsule()
                        .fill(accent.opacity(0.40))
                        .frame(width: max(4, proxy.size.width * min(max(leadingValue + trailingValue, 0), 1)))

                    Capsule()
                        .fill(EdgeTheme.accentFill(accent))
                        .frame(width: max(4, proxy.size.width * min(max(leadingValue, 0), 1)))
                        .shadow(color: accent.opacity(0.55), radius: 8)
                }
            }
            .frame(height: 9)
        }
    }
}

private struct SystemGauge: View {
    let title: String
    let value: Double
    let subtitle: String
    let accent: Color
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        ZStack {
            Circle()
                .stroke(EdgeTheme.mutedFill, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(EdgeTheme.accentFill(accent), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.62), radius: 9)

            VStack(spacing: 1) {
                Text(EdgeFormatters.percent(value))
                    .font(EdgeTheme.displayFont(size: 25 * textScale, weight: .heavy))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .monospacedDigit()
                Text(title)
                    .font(EdgeTheme.bodyFont(size: 10 * textScale, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)
                Text(subtitle)
                    .font(EdgeTheme.bodyFont(size: 9 * textScale, weight: .bold))
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}
