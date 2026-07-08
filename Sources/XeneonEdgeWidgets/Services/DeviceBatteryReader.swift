import Foundation
import IOKit

enum DeviceBatteryReader {
    static func externalBatteries() async -> [DeviceBatterySnapshot] {
        async let profiler = bluetoothProfilerBatteries()
        async let mobile = mobileDeviceBatteries()

        var collector = DeviceBatteryCollector()
        collector.add(contentsOf: ioRegistryBatteries())
        collector.add(contentsOf: await BLEBatteryScanner.shared.currentBatteries())
        collector.add(contentsOf: await profiler)
        collector.add(contentsOf: await mobile)
        return collector.sortedSnapshots
    }

    static func normalizedBatteryPercent(_ value: Any?) -> Double? {
        guard let value else { return nil }

        if let number = value as? NSNumber {
            return normalizedBatteryPercent(number.doubleValue)
        }

        if let double = value as? Double {
            return normalizedBatteryPercent(double)
        }

        if let integer = value as? Int {
            return normalizedBatteryPercent(Double(integer))
        }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.localizedCaseInsensitiveContains("unknown") || trimmed == "--" {
                return nil
            }
            let allowed = CharacterSet(charactersIn: "0123456789.")
            let scalarString = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            if let raw = Double(scalarString) {
                return normalizedBatteryPercent(raw)
            }
        }

        return nil
    }

    static func bluetoothProfilerBatteries(from output: String) -> [DeviceBatterySnapshot] {
        guard
            let data = output.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else {
            return []
        }

        var devices: [DeviceBatterySnapshot] = []
        for section in sections {
            for key in ["device_connected", "device_not_connected"] {
                guard let entries = section[key] as? [[String: Any]] else { continue }
                for entry in entries {
                    for (name, rawProperties) in entry {
                        guard
                            let properties = rawProperties as? [String: Any],
                            let percent = batteryPercent(in: properties)
                        else {
                            continue
                        }

                        devices.append(
                            DeviceBatterySnapshot(
                                name: name,
                                percent: percent,
                                isCharging: nil,
                                kind: properties["device_minorType"] as? String,
                                source: .bluetoothProfiler
                            )
                        )
                    }
                }
            }
        }
        return devices
    }

    static func mobileDeviceBatteries(
        ideviceIDOutput: String,
        deviceInfoByID: [String: String],
        batteryInfoByID: [String: String],
        isNetwork: Bool
    ) -> [DeviceBatterySnapshot] {
        ideviceIDOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { id in
                let deviceInfo = keyValueLines(deviceInfoByID[id] ?? "")
                let batteryInfo = keyValueLines(batteryInfoByID[id] ?? "")

                guard
                    batteryInfo["HasBattery"]?.localizedCaseInsensitiveContains("false") != true,
                    let percent = normalizedBatteryPercent(batteryInfo["BatteryCurrentCapacity"])
                else {
                    return nil
                }

                let name = deviceInfo["DeviceName"]
                    ?? deviceInfo["ProductName"]
                    ?? deviceInfo["ProductType"]
                    ?? (isNetwork ? "Network iOS Device" : "iOS Device")
                let kind = deviceInfo["DeviceClass"] ?? deviceInfo["ProductType"] ?? "iOS"
                let isCharging = boolValue(batteryInfo["BatteryIsCharging"])
                    ?? boolValue(batteryInfo["ExternalConnected"])

                return DeviceBatterySnapshot(
                    name: name,
                    percent: percent,
                    isCharging: isCharging,
                    kind: kind,
                    source: .mobileDevice
                )
            }
    }

    static func watchBatteries(fromCompanionRegistryJSON output: String) -> [DeviceBatterySnapshot] {
        guard
            let data = output.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data)
        else {
            return watchBatteries(fromComptestOutput: output)
        }

        var collector = DeviceBatteryCollector()
        collectWatchBatteries(from: root, collector: &collector)
        return collector.sortedSnapshots
    }

    private static func bluetoothProfilerBatteries() async -> [DeviceBatterySnapshot] {
        let output = await run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 8)
        return bluetoothProfilerBatteries(from: output)
    }

    private static func ioRegistryBatteries() -> [DeviceBatterySnapshot] {
        let classes = [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDKeyboard",
            "AppleHIDKeyboardEventDriverV2",
            "BNBMouseDevice",
            "BNBTrackpadDevice",
            "IOHIDEventService",
            "AppleUserHIDDevice"
        ]

        var snapshots: [DeviceBatterySnapshot] = []
        var seenEntryIDs: Set<UInt64> = []

        for className in classes {
            guard let matching = IOServiceMatching(className) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != IO_OBJECT_NULL {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }

                var entryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
                   seenEntryIDs.contains(entryID) {
                    continue
                }
                if entryID != 0 {
                    seenEntryIDs.insert(entryID)
                }

                guard
                    let properties = registryProperties(for: service),
                    let percent = batteryPercent(in: properties)
                else {
                    continue
                }

                snapshots.append(
                    DeviceBatterySnapshot(
                        name: deviceName(from: properties, service: service),
                        percent: percent,
                        isCharging: boolValue(properties["BatteryIsCharging"]),
                        kind: deviceKind(from: properties),
                        source: .ioRegistry
                    )
                )
            }
        }

        return snapshots
    }

    private static func mobileDeviceBatteries() async -> [DeviceBatterySnapshot] {
        guard
            let ideviceID = executable(named: "idevice_id"),
            let ideviceInfo = executable(named: "ideviceinfo")
        else {
            return []
        }

        async let usb = mobileDeviceBatteries(
            ideviceID: ideviceID,
            ideviceInfo: ideviceInfo,
            isNetwork: false
        )
        async let network = mobileDeviceBatteries(
            ideviceID: ideviceID,
            ideviceInfo: ideviceInfo,
            isNetwork: true
        )

        var collector = DeviceBatteryCollector()
        collector.add(contentsOf: await usb)
        collector.add(contentsOf: await network)
        collector.add(contentsOf: await pairedWatchBatteries(ideviceID: ideviceID))
        return collector.sortedSnapshots
    }

    private static func mobileDeviceBatteries(
        ideviceID: URL,
        ideviceInfo: URL,
        isNetwork: Bool
    ) async -> [DeviceBatterySnapshot] {
        let idArguments = isNetwork ? ["-n"] : ["-l"]
        let idsOutput = await run(ideviceID.path, idArguments, timeout: 5)
        let ids = idsOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !ids.isEmpty else { return [] }

        var deviceInfoByID: [String: String] = [:]
        var batteryInfoByID: [String: String] = [:]
        for id in ids {
            let baseArguments = (isNetwork ? ["-n"] : []) + ["-u", id]
            deviceInfoByID[id] = await run(ideviceInfo.path, baseArguments, timeout: 5)
            batteryInfoByID[id] = await run(
                ideviceInfo.path,
                baseArguments + ["-q", "com.apple.mobile.battery"],
                timeout: 5
            )
        }

        return mobileDeviceBatteries(
            ideviceIDOutput: idsOutput,
            deviceInfoByID: deviceInfoByID,
            batteryInfoByID: batteryInfoByID,
            isNetwork: isNetwork
        )
    }

    private static func pairedWatchBatteries(ideviceID: URL) async -> [DeviceBatterySnapshot] {
        let ids = await pairedMobileDeviceIDs(ideviceID: ideviceID)

        var collector = DeviceBatteryCollector()

        if let bridge = executable(named: "xeneon-watch-battery") {
            let output = await run(bridge.path, [], timeout: 10)
            collector.add(contentsOf: watchBatteries(fromCompanionRegistryJSON: output))

            for id in ids {
                let output = await run(bridge.path, [id], timeout: 10)
                collector.add(contentsOf: watchBatteries(fromCompanionRegistryJSON: output))
            }
        }

        if let comptest = executable(named: "comptest") {
            for id in ids {
                let output = await run(comptest.path, [id], timeout: 8)
                collector.add(contentsOf: watchBatteries(fromComptestOutput: output))
            }
        }

        return collector.sortedSnapshots
    }

    private static func pairedMobileDeviceIDs(ideviceID: URL) async -> [String] {
        async let usbOutput = run(ideviceID.path, ["-l"], timeout: 5)
        async let networkOutput = run(ideviceID.path, ["-n"], timeout: 5)

        return await "\(usbOutput)\n\(networkOutput)"
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: []) { ids, id in
                if !ids.contains(id) {
                    ids.append(id)
                }
            }
    }

    private static func watchBatteries(fromComptestOutput output: String) -> [DeviceBatterySnapshot] {
        let lines = output.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.localizedCaseInsensitiveContains("BatteryCurrentCapacity") }) else {
            return []
        }

        let keyValues = keyValueLines(output)
        guard let percent = normalizedBatteryPercent(keyValues["BatteryCurrentCapacity"]) else {
            return []
        }

        return [
            DeviceBatterySnapshot(
                name: keyValues["DeviceName"] ?? keyValues["Name"] ?? "Apple Watch",
                percent: percent,
                isCharging: boolValue(keyValues["BatteryIsCharging"]),
                kind: "Apple Watch",
                source: .watchRelay
            )
        ]
    }

    private static func collectWatchBatteries(from node: Any, collector: inout DeviceBatteryCollector) {
        if let dictionary = node as? [String: Any] {
            if let snapshot = watchBattery(from: dictionary) {
                collector.add(snapshot)
                return
            }

            for value in dictionary.values {
                collectWatchBatteries(from: value, collector: &collector)
            }
            return
        }

        if let array = node as? [Any] {
            for value in array {
                collectWatchBatteries(from: value, collector: &collector)
            }
        }
    }

    private static func watchBattery(from dictionary: [String: Any]) -> DeviceBatterySnapshot? {
        guard
            dictionaryLooksLikeWatch(dictionary),
            let percent = watchBatteryPercent(from: dictionary)
        else {
            return nil
        }

        let name = stringValue(in: dictionary, keys: [
            "DeviceName",
            "Name",
            "ProductName",
            "MarketingName",
            "CompanionName"
        ]) ?? "Apple Watch"

        let kind = stringValue(in: dictionary, keys: [
            "ProductType",
            "DeviceClass",
            "Class",
            "Model"
        ]) ?? "Apple Watch"

        return DeviceBatterySnapshot(
            name: name.localizedCaseInsensitiveContains("watch") ? name : "Apple Watch",
            percent: percent,
            isCharging: boolValue(unwrappedValue(in: dictionary, keys: [
                "BatteryIsCharging",
                "IsCharging",
                "ExternalConnected"
            ])),
            kind: kind.localizedCaseInsensitiveContains("watch") ? kind : "Apple Watch",
            source: .watchRelay
        )
    }

    private static func watchBatteryPercent(from dictionary: [String: Any]) -> Double? {
        for key in [
            "BatteryCurrentCapacity",
            "BatteryPercent",
            "BatteryLevel",
            "CurrentBatteryCapacity"
        ] {
            if let percent = normalizedBatteryPercent(unwrappedValue(dictionary[key], preferredKey: key)) {
                return percent
            }
        }
        return nil
    }

    private static func dictionaryLooksLikeWatch(_ dictionary: [String: Any]) -> Bool {
        if dictionary.keys.contains(where: { $0.localizedCaseInsensitiveContains("BatteryCurrentCapacity") }) {
            return true
        }

        let searchText = dictionary.compactMap { key, value -> String? in
            if value is [String: Any] || value is [Any] {
                return key
            }
            return "\(key) \(value)"
        }
        .joined(separator: " ")
        .lowercased()

        return searchText.contains("watch")
            || searchText.contains("gizmo")
            || searchText.contains("nano")
    }

    private static func unwrappedValue(in dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = unwrappedValue(dictionary[key], preferredKey: key) {
                return value
            }
        }
        return nil
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = unwrappedValue(dictionary[key], preferredKey: key) as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func unwrappedValue(_ value: Any?, preferredKey: String) -> Any? {
        guard let value else { return nil }
        if let dictionary = value as? [String: Any] {
            if let exact = dictionary[preferredKey] {
                return exact
            }
            if dictionary.count == 1 {
                return dictionary.values.first
            }
        }
        return value
    }

    private static func registryProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        ) == KERN_SUCCESS else {
            return nil
        }

        return unmanagedProperties?.takeRetainedValue() as? [String: Any]
    }

    private static func batteryPercent(in properties: [String: Any]) -> Double? {
        let preferredKeys = [
            "BatteryPercent",
            "BatteryCurrentCapacity",
            "BatteryLevel",
            "BatteryCapacity",
            "DeviceBatteryLevel",
            "Battery Percentage",
            "device_batteryLevelMain"
        ]

        for key in preferredKeys {
            if let percent = normalizedBatteryPercent(properties[key]) {
                return percent
            }
        }

        // Deterministic fallback: Dictionary iteration order is unspecified, so for
        // multi-cell devices (e.g. AirPods expose Main/Left/Right/Case keys
        // simultaneously) sort the matched keys by a defined priority before
        // returning, otherwise the displayed cell varies between refreshes.
        let matchedKeys = properties.keys
            .filter { $0.localizedCaseInsensitiveContains("battery") }
            .sorted { batteryKeyPriority($0) < batteryKeyPriority($1) }

        for key in matchedKeys {
            if let percent = normalizedBatteryPercent(properties[key]) {
                return percent
            }
        }

        return nil
    }

    // Lower value sorts first. Prefer combined/main cells, then left/right buds,
    // then the case, then any remaining battery key alphabetically.
    private static func batteryKeyPriority(_ key: String) -> (Int, String) {
        let lowered = key.lowercased()
        let rank: Int
        if lowered.contains("main") || lowered.contains("combined") || lowered.contains("single") {
            rank = 0
        } else if lowered.contains("left") || lowered.contains("right") {
            rank = 1
        } else if lowered.contains("case") {
            rank = 3
        } else {
            rank = 2
        }
        return (rank, lowered)
    }

    private static func normalizedBatteryPercent(_ raw: Double) -> Double? {
        guard raw.isFinite, raw >= 0 else { return nil }
        // Only treat a value as an already-normalized 0.0-1.0 fraction when it is
        // strictly less than 1 AND not a whole number. Otherwise the data is on a
        // 0-100 integer percentage scale (e.g. ideviceinfo BatteryCurrentCapacity).
        // This avoids the discontinuity where the integer 1 (= 1%) was returned as
        // 1.0 (= 100%).
        if raw < 1 && raw != raw.rounded() {
            return min(max(raw, 0), 1)
        }
        if raw <= 100 {
            return min(max(raw / 100, 0), 1)
        }
        return nil
    }

    private static func deviceName(from properties: [String: Any], service: io_registry_entry_t) -> String {
        for key in ["Product", "ProductName", "DeviceName", "HIDProduct", "Name", "DisplayName"] {
            if let name = properties[key] as? String, !name.isEmpty {
                return name
            }
        }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        if IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS {
            let name = nameBuffer.withUnsafeBufferPointer { buffer in
                let prefix = buffer.prefix { $0 != 0 }
                return String(decoding: prefix.map(UInt8.init(bitPattern:)), as: UTF8.self)
            }
            if !name.isEmpty {
                return name
            }
        }

        return "Bluetooth Device"
    }

    private static func deviceKind(from properties: [String: Any]) -> String? {
        for key in ["DeviceClass", "Transport", "device_minorType", "Product", "PrimaryUsage"] {
            if let value = properties[key] as? String, !value.isEmpty {
                return value
            }
            if let number = properties[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func keyValueLines(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        guard let string = value as? String else { return nil }
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "charging", "charged":
            return true
        case "false", "no", "0", "not charging":
            return false
        default:
            return nil
        }
    }

    private static func executable(named name: String) -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "Helpers/\(name)").path,
            Bundle.main.bundleURL.appending(path: "Contents/Resources/Helpers/\(name)").path,
            URL(filePath: FileManager.default.currentDirectoryPath).appending(path: ".build/helpers/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ].compactMap(\.self)

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(filePath: candidate)
        }

        let pathOutput = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathOutput.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(filePath: candidate)
            }
        }

        return nil
    }

    private static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(filePath: launchPath)
            process.arguments = arguments

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            // Discard stderr at the kernel level so a child writing a large volume
            // to stderr cannot block on a pipe nobody is draining.
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return ""
            }

            // Drain stdout incrementally while the process runs so the child never
            // blocks writing into a full pipe buffer (the documented Foundation
            // pipe-buffer deadlock). availableData returns whatever is buffered and
            // returns empty only at EOF; reading on this same task keeps the
            // non-Sendable Pipe/FileHandle off any concurrency boundary.
            let readHandle = outputPipe.fileHandleForReading
            var data = Data()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                let chunk = readHandle.availableData
                if chunk.isEmpty {
                    try? await Task.sleep(for: .milliseconds(50))
                } else {
                    data.append(chunk)
                }
            }

            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }

            // Read any remaining buffered output after the process has exited.
            data.append(readHandle.readDataToEndOfFile())
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

private struct DeviceBatteryCollector {
    private var snapshotsByKey: [String: DeviceBatterySnapshot] = [:]
    private var fallbackCounter = 0

    // Generic placeholder names emitted by producers when a real device name is
    // unavailable (DeviceBatteryReader.deviceName -> "Bluetooth Device",
    // BLEBatteryScanner -> "BLE Device"). Two genuinely distinct unnamed devices
    // must NOT collapse onto the same key, so they are never deduplicated by name.
    private static let genericFallbackKeys: Set<String> = [
        "bluetoothdevice",
        "bledevice"
    ]

    var sortedSnapshots: [DeviceBatterySnapshot] {
        snapshotsByKey.values.sorted { lhs, rhs in
            if lhs.source.sortRank != rhs.source.sortRank {
                return lhs.source.sortRank > rhs.source.sortRank
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    mutating func add(contentsOf snapshots: [DeviceBatterySnapshot]) {
        for snapshot in snapshots {
            add(snapshot)
        }
    }

    mutating func add(_ snapshot: DeviceBatterySnapshot) {
        let nameKey = normalizedKey(snapshot.name)
        guard !nameKey.isEmpty else { return }

        // For generic fallback names, give each device a unique dedup key so two
        // distinct unnamed devices both survive instead of one overwriting the
        // other. Real device-provided names continue to collapse by name (so the
        // same physical device seen via multiple sources is merged).
        if Self.genericFallbackKeys.contains(nameKey) {
            let uniqueKey = "\(nameKey)#\(snapshot.source.rawValue)#\(fallbackCounter)"
            fallbackCounter += 1
            snapshotsByKey[uniqueKey] = snapshot
            return
        }

        if let existing = snapshotsByKey[nameKey] {
            if snapshot.source.sortRank >= existing.source.sortRank {
                snapshotsByKey[nameKey] = snapshot
            }
        } else {
            snapshotsByKey[nameKey] = snapshot
        }
    }

    private func normalizedKey(_ name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension DeviceBatterySource {
    var sortRank: Int {
        switch self {
        case .watchRelay: 70
        case .mobileDevice: 60
        case .bluetoothLE: 50
        case .ioRegistry: 40
        case .bluetoothProfiler: 30
        case .mac: 20
        case .unknown: 0
        }
    }
}
