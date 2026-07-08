import SwiftUI

struct SettingsDevicesPage: View {
    @Bindable var store: DashboardStore

    var body: some View {
        SettingsPage(
            title: "Devices & Permissions",
            subtitle: "Plain-language status for the device readers behind the battery widgets."
        ) {
            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Device batteries · optional", subtitle: "These feed the System widget when the devices are visible to macOS.")
                    PermissionRow(
                        symbolName: "antenna.radiowaves.left.and.right",
                        tint: bluetoothTint,
                        title: "Bluetooth",
                        explanation: "Reads battery levels for Bluetooth and BLE accessories.",
                        status: bluetoothStatus,
                        result: bluetoothResult,
                        actionTitle: nil,
                        action: {}
                    )
                    PermissionRow(
                        symbolName: "iphone",
                        tint: mobileTint,
                        title: "iPhone / iPad USB trust",
                        explanation: "Reads iOS device battery when the device is trusted over USB or Wi-Fi.",
                        status: mobileStatus,
                        result: mobileResult,
                        actionTitle: nil,
                        action: {}
                    )
                    PermissionRow(
                        symbolName: "applewatch",
                        tint: watchTint,
                        title: "Apple Watch via iPhone",
                        explanation: "Uses paired iPhone data when the watch battery relay is visible.",
                        status: watchStatus,
                        result: watchResult,
                        actionTitle: nil,
                        action: {}
                    )
                }
            }
        }
    }

    private var bluetoothDevices: [DeviceBatterySnapshot] {
        store.stats.deviceBatteries.filter { [.bluetoothLE, .bluetoothProfiler, .ioRegistry].contains($0.source) }
    }

    private var mobileDevices: [DeviceBatterySnapshot] {
        store.stats.deviceBatteries.filter { $0.source == .mobileDevice }
    }

    private var watchDevices: [DeviceBatterySnapshot] {
        store.stats.deviceBatteries.filter { $0.source == .watchRelay || $0.name.localizedCaseInsensitiveContains("watch") }
    }

    private var bluetoothStatus: String { bluetoothDevices.isEmpty ? "Idle" : "Working" }
    private var mobileStatus: String { mobileDevices.isEmpty ? "Idle" : "Working" }
    private var watchStatus: String { watchDevices.isEmpty ? "Idle" : "Working" }
    private var bluetoothTint: Color { bluetoothDevices.isEmpty ? .secondary : .green }
    private var mobileTint: Color { mobileDevices.isEmpty ? .secondary : .green }
    private var watchTint: Color { watchDevices.isEmpty ? .secondary : .green }
    private var bluetoothResult: String { resultText(bluetoothDevices, fallback: "No Bluetooth batteries detected yet.") }
    private var mobileResult: String { resultText(mobileDevices, fallback: "Plug in and trust an iPhone or iPad.") }
    private var watchResult: String { resultText(watchDevices, fallback: "No Apple Watch relay detected yet.") }

    private func resultText(_ devices: [DeviceBatterySnapshot], fallback: String) -> String {
        guard !devices.isEmpty else { return fallback }
        return devices.prefix(3)
            .map { "\($0.name) \(Int($0.percent * 100))%" + (($0.isCharging == true) ? ", charging" : "") }
            .joined(separator: " · ")
    }
}

private struct PermissionRow: View {
    let symbolName: String
    let tint: Color
    let title: String
    let explanation: String
    let status: String
    let result: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(symbolName: symbolName, tint: tint, title: title, subtitle: explanation) {
                HStack {
                    StatusPill(title: status, tint: status == "Working" ? .green : status == "Action needed" ? .orange : .secondary)
                    if let actionTitle {
                        Button(actionTitle, action: action)
                    }
                }
            }
            Text(result)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 58)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
        }
        .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}
