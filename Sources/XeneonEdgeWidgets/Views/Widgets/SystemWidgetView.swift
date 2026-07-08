import SwiftUI

struct SystemWidgetView: View {
    let snapshot: SystemSnapshot
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > 390

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
                            value: snapshot.publicIPAddress ?? "Unavailable",
                            symbolName: "globe",
                            accent: accent
                        )
                    }
                }

                if !snapshot.deviceBatteries.isEmpty {
                    AnimeWell(padding: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Connected Power")
                                .font(EdgeTheme.bodyFont(size: 10, weight: .black))
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
                    .font(EdgeTheme.bodyFont(size: 11, weight: .bold))
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .lineLimit(1)
                }

                if !snapshot.topProcesses.isEmpty && isWide {
                    AnimeWell(padding: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Top Memory")
                                .font(EdgeTheme.bodyFont(size: 10, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(EdgeTheme.tertiaryText)
                                .textCase(.uppercase)

                            ForEach(snapshot.topProcesses.prefix(3)) { process in
                                HStack(spacing: 6) {
                                    Text(process.name)
                                        .font(EdgeTheme.bodyFont(size: 12, weight: .bold))
                                        .foregroundStyle(EdgeTheme.secondaryText)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(EdgeFormatters.bytes(process.memoryBytes))
                                        .font(EdgeTheme.bodyFont(size: 12, weight: .heavy))
                                        .foregroundStyle(EdgeTheme.primaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                Label(snapshot.localIPAddress ?? "Offline", systemImage: "network")
                    .font(EdgeTheme.bodyFont(size: 14, weight: .heavy))
                    .foregroundStyle(EdgeTheme.secondaryText)
                    .lineLimit(1)
            }
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

private struct DeviceBatteryRow: View {
    let device: DeviceBatterySnapshot
    let accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 16)

            Text(device.name)
                .font(EdgeTheme.bodyFont(size: 12, weight: .bold))
                .foregroundStyle(EdgeTheme.secondaryText)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 5) {
                if device.isCharging == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(accent)
                }

                Text(device.source.title)
                    .font(EdgeTheme.bodyFont(size: 9, weight: .black))
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(EdgeFormatters.percent(device.percent))
                    .font(EdgeTheme.bodyFont(size: 12, weight: .heavy))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)

                Spacer()

                Text("\(leadingTitle) \(EdgeFormatters.percent(leadingValue))")
                    .foregroundStyle(accent)
                Text("\(trailingTitle) \(EdgeFormatters.percent(trailingValue))")
                    .foregroundStyle(accent.opacity(0.62))
            }
            .font(EdgeTheme.bodyFont(size: 11, weight: .black))
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
                    .font(EdgeTheme.displayFont(size: 25, weight: .heavy))
                    .foregroundStyle(EdgeTheme.primaryText)
                    .monospacedDigit()
                Text(title)
                    .font(EdgeTheme.bodyFont(size: 10, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)
                Text(subtitle)
                    .font(EdgeTheme.bodyFont(size: 9, weight: .bold))
                    .foregroundStyle(EdgeTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}
