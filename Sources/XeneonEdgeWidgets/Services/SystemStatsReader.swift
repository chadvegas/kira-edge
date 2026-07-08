import Darwin
import Foundation
import IOKit.ps

enum SystemStatsReader {
    private static let state = SystemStatsState()

    static func snapshot() async -> SystemSnapshot {
        async let cpu = cpuSample()
        async let memory = memorySample()
        async let disk = diskSample()
        async let battery = batteryState()
        async let localIP = localIPAddress()
        async let publicIP = publicIPAddress()
        async let network = networkSample()
        async let processes = topProcesses()

        let cpuResult = await cpu
        let batteryResult = await battery
        let memoryResult = await memory
        let diskResult = await disk
        let networkResult = await network

        return SystemSnapshot(
            cpuLoad: cpuResult.load,
            cpuUser: cpuResult.user,
            cpuSystem: cpuResult.system,
            memoryUsed: memoryResult.used,
            memoryPressure: memoryResult.pressure,
            memoryWired: memoryResult.wired,
            memoryCompressed: memoryResult.compressed,
            memoryAvailableBytes: memoryResult.availableBytes,
            diskUsed: diskResult.used,
            diskAvailableBytes: diskResult.availableBytes,
            diskTotalBytes: diskResult.totalBytes,
            batteryPercent: batteryResult.percent,
            isCharging: batteryResult.isCharging,
            localIPAddress: await localIP,
            publicIPAddress: await publicIP,
            networkUploadBytesPerSecond: networkResult.uploadBytesPerSecond,
            networkDownloadBytesPerSecond: networkResult.downloadBytesPerSecond,
            deviceBatteries: batteryResult.devices,
            topProcesses: await processes
        )
    }

    private static func cpuSample() async -> CPUSample {
        guard let ticks = readCPUTicks() else { return .empty }
        return await state.cpuSample(from: ticks)
    }

    private static func readCPUTicks() -> CPUTicks? {
        var cpuInfo: processor_info_array_t?
        var processorCount: natural_t = 0
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let stateCount = Int(CPU_STATE_MAX)
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for processor in 0..<Int(processorCount) {
            let base = processor * stateCount
            user += UInt64(max(cpuInfo[base + Int(CPU_STATE_USER)], 0))
            system += UInt64(max(cpuInfo[base + Int(CPU_STATE_SYSTEM)], 0))
            idle += UInt64(max(cpuInfo[base + Int(CPU_STATE_IDLE)], 0))
            nice += UInt64(max(cpuInfo[base + Int(CPU_STATE_NICE)], 0))
        }

        return CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private static func memorySample() async -> MemorySample {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return .empty
        }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return .empty }

        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return .empty }

        let page = Double(pageSize)
        let free = Double(stats.free_count + stats.speculative_count) * page
        let inactive = Double(stats.inactive_count) * page
        let active = Double(stats.active_count) * page
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        let available = free + inactive
        let reclaimable = free + inactive * 0.35

        let used = min(max((active + wired + compressed) / total, 0), 1)
        let pressure = min(max(1 - reclaimable / total, 0), 1)

        return MemorySample(
            used: used,
            pressure: pressure,
            wired: min(max(wired / total, 0), 1),
            compressed: min(max(compressed / total, 0), 1),
            availableBytes: Int64(available.rounded())
        )
    }

    private static func diskSample() async -> DiskSample {
        do {
            let values = try URL(filePath: "/").resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
            guard
                let available = values.volumeAvailableCapacityForImportantUsage,
                let total = values.volumeTotalCapacity,
                total > 0
            else {
                return .empty
            }
            return DiskSample(
                used: min(max(1 - Double(available) / Double(total), 0), 1),
                availableBytes: Int64(available),
                totalBytes: Int64(total)
            )
        } catch {
            return .empty
        }
    }

    private static func networkSample() async -> NetworkSample {
        guard let counters = readNetworkCounters() else {
            return await state.networkSample(from: nil, at: Date())
        }
        return await state.networkSample(from: counters, at: Date())
    }

    /// Reads per-interface 64-bit byte counters via `sysctl(NET_RT_IFLIST2)`.
    ///
    /// `getifaddrs` exposes only the 32-bit `struct if_data`, whose
    /// `ifi_ibytes`/`ifi_obytes` wrap every ~4.29 GB. The kernel maintains true
    /// 64-bit counters that are reachable only through the routing-socket
    /// `if_msghdr2`/`if_data64` path used here. Returns `nil` on failure so the
    /// caller can skip updating its baseline instead of treating a failed read
    /// as a zero sample.
    private static func readNetworkCounters() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return nil }

        var perInterface: [UInt16: NetworkCounters.InterfaceBytes] = [:]

        buffer.withUnsafeBytes { raw in
            guard raw.baseAddress != nil else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                defer { offset += messageLength }

                guard
                    Int32(header.ifm_type) == RTM_IFINFO2,
                    offset + MemoryLayout<if_msghdr2>.size <= length
                else {
                    continue
                }

                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard
                    message.ifm_flags & Int32(IFF_UP) != 0,
                    message.ifm_flags & Int32(IFF_LOOPBACK) == 0
                else {
                    continue
                }

                let data = message.ifm_data
                perInterface[message.ifm_index] = NetworkCounters.InterfaceBytes(
                    uploadBytes: data.ifi_obytes,
                    downloadBytes: data.ifi_ibytes
                )
            }
        }

        return NetworkCounters(interfaces: perInterface)
    }

    private static func batteryState() async -> (percent: Double?, isCharging: Bool, devices: [DeviceBatterySnapshot]) {
        var primary: (percent: Double?, isCharging: Bool) = (nil, false)
        var devices: [DeviceBatterySnapshot] = []

        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            let external = await cachedDeviceBatteries()
            return (nil, false, external)
        }

        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Double,
                let max = description[kIOPSMaxCapacityKey] as? Double,
                max > 0
            else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let percent = current / max
            let isCharging = state == kIOPSACPowerValue || (description[kIOPSIsChargingKey] as? Bool == true)
            if primary.percent == nil {
                primary = (percent, isCharging)
            }

            if let rawName = description[kIOPSNameKey] as? String {
                let name = rawName.replacingOccurrences(of: "InternalBattery-0", with: "MacBook")
                devices.append(
                    DeviceBatterySnapshot(
                        name: name,
                        percent: percent,
                        isCharging: isCharging,
                        kind: description[kIOPSTypeKey] as? String,
                        source: .mac
                    )
                )
            }
        }

        let external = await cachedDeviceBatteries()
        for device in external where !devices.contains(where: { $0.name == device.name }) {
            devices.append(device)
        }

        return (primary.percent, primary.isCharging, devices)
    }

    private static func cachedDeviceBatteries() async -> [DeviceBatterySnapshot] {
        let now = Date()
        if let cached = await state.cachedDeviceBatteries(at: now) {
            return cached
        }

        let devices = await DeviceBatteryReader.externalBatteries()
        return await state.updateDeviceBatteries(devices, at: now)
    }

    private static func localIPAddress() async -> String? {
        for interface in ["en0", "en1", "bridge100"] {
            let output = await run("/usr/sbin/ipconfig", ["getifaddr", interface])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                return output
            }
        }
        return nil
    }

    private static func publicIPAddress() async -> String? {
        let now = Date()
        if let cached = await state.cachedPublicIP(at: now) {
            return cached
        }

        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
            let (data, _) = try await URLSession.shared.data(for: request)
            let ip = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return await state.updatePublicIP(ip.isEmpty ? nil : ip, at: now)
        } catch {
            return await state.updatePublicIP(nil, at: now)
        }
    }

    private static func topProcesses() async -> [ProcessSnapshot] {
        let output = await run("/bin/sh", ["-c", "ps -axo rss=,comm= | sort -rn | head -5"])
        return output
            .components(separatedBy: .newlines)
            .compactMap { line -> ProcessSnapshot? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard parts.count == 2, let rssKilobytes = Int64(parts[0]) else { return nil }
                let path = String(parts[1])
                let name = URL(filePath: path).lastPathComponent
                return ProcessSnapshot(name: name, memoryBytes: rssKilobytes * 1024)
            }
    }

    private static func run(_ launchPath: String, _ arguments: [String]) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(filePath: launchPath)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            // Discard stderr to a sink we never read: a child that writes more
            // than the pipe buffer (~64 KB) to an undrained stderr pipe would
            // block forever, and this helper has no timeout.
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                // Drain stdout to EOF BEFORE waiting for exit. Reading after
                // waitUntilExit() deadlocks if the child fills the pipe buffer
                // while we are blocked in waitUntilExit().
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return String(decoding: data, as: UTF8.self)
            } catch {
                return ""
            }
        }.value
    }
}

private actor SystemStatsState {
    private var previousCPU: CPUTicks?
    private var previousNetwork: NetworkCounters?
    private var previousNetworkDate: Date?
    private var publicIP: String?
    private var publicIPDate: Date?
    private var deviceBatteries: [DeviceBatterySnapshot] = []
    private var deviceBatteriesDate: Date?

    func cpuSample(from current: CPUTicks) -> CPUSample {
        let previous = previousCPU
        previousCPU = current

        // The first sample has no prior baseline; deriving load from the raw
        // since-boot totals would report the machine's lifetime-average load.
        // Store the baseline and report a neutral value until a real two-sample
        // delta is available.
        guard let previous else {
            return .empty
        }

        let delta = current.delta(from: previous)
        let total = Double(max(delta.total, 1))
        let user = Double(delta.user + delta.nice) / total
        let system = Double(delta.system) / total
        let idle = Double(delta.idle) / total

        return CPUSample(
            load: min(max(1 - idle, 0), 1),
            user: min(max(user, 0), 1),
            system: min(max(system, 0), 1)
        )
    }

    func networkSample(from current: NetworkCounters?, at date: Date) -> NetworkSample {
        // A failed read (nil) must not become the baseline: overwriting the
        // previous sample with zeros would make the next successful read report
        // the entire since-boot counter as a single multi-GB/s spike.
        guard let current else {
            return .empty
        }

        defer {
            previousNetwork = current
            previousNetworkDate = date
        }

        guard
            let previousNetwork,
            let previousNetworkDate
        else {
            return .empty
        }

        let interval = max(date.timeIntervalSince(previousNetworkDate), 0.5)

        // Only diff interfaces present in BOTH samples, so an interface that
        // appears (VPN tunnel, AWDL, etc.) or disappears between samples
        // contributes 0 to the delta rather than its full since-boot total.
        var uploadDelta: UInt64 = 0
        var downloadDelta: UInt64 = 0
        for (index, bytes) in current.interfaces {
            guard let previousBytes = previousNetwork.interfaces[index] else { continue }
            if bytes.uploadBytes >= previousBytes.uploadBytes {
                uploadDelta += bytes.uploadBytes - previousBytes.uploadBytes
            }
            if bytes.downloadBytes >= previousBytes.downloadBytes {
                downloadDelta += bytes.downloadBytes - previousBytes.downloadBytes
            }
        }

        return NetworkSample(
            uploadBytesPerSecond: Double(uploadDelta) / interval,
            downloadBytesPerSecond: Double(downloadDelta) / interval
        )
    }

    func cachedPublicIP(at date: Date) -> String? {
        guard
            let publicIP,
            let publicIPDate,
            date.timeIntervalSince(publicIPDate) < 600
        else {
            return nil
        }
        return publicIP
    }

    func updatePublicIP(_ ip: String?, at date: Date) -> String? {
        if let ip {
            publicIP = ip
        }
        publicIPDate = date
        return publicIP
    }

    func cachedDeviceBatteries(at date: Date) -> [DeviceBatterySnapshot]? {
        guard
            let deviceBatteriesDate,
            date.timeIntervalSince(deviceBatteriesDate) < 60
        else {
            return nil
        }
        return deviceBatteries
    }

    func updateDeviceBatteries(_ batteries: [DeviceBatterySnapshot], at date: Date) -> [DeviceBatterySnapshot] {
        deviceBatteries = batteries
        deviceBatteriesDate = date
        return batteries
    }
}

private struct CPUTicks {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var total: UInt64 {
        user + system + idle + nice
    }

    func delta(from previous: CPUTicks) -> CPUTicks {
        CPUTicks(
            user: user >= previous.user ? user - previous.user : 0,
            system: system >= previous.system ? system - previous.system : 0,
            idle: idle >= previous.idle ? idle - previous.idle : 0,
            nice: nice >= previous.nice ? nice - previous.nice : 0
        )
    }
}

private struct CPUSample {
    var load: Double
    var user: Double
    var system: Double

    static let empty = CPUSample(load: 0, user: 0, system: 0)
}

private struct MemorySample {
    var used: Double
    var pressure: Double
    var wired: Double
    var compressed: Double
    var availableBytes: Int64?

    static let empty = MemorySample(used: 0, pressure: 0, wired: 0, compressed: 0, availableBytes: nil)
}

private struct DiskSample {
    var used: Double
    var availableBytes: Int64?
    var totalBytes: Int64?

    static let empty = DiskSample(used: 0, availableBytes: nil, totalBytes: nil)
}

private struct NetworkCounters {
    struct InterfaceBytes {
        var uploadBytes: UInt64
        var downloadBytes: UInt64
    }

    /// Per-interface 64-bit byte counters keyed by `ifm_index`. Keyed by index
    /// so the actor can diff only interfaces present in two consecutive samples.
    var interfaces: [UInt16: InterfaceBytes]
}

private struct NetworkSample {
    var uploadBytesPerSecond: Double
    var downloadBytesPerSecond: Double

    static let empty = NetworkSample(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0)
}
