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
        // Free-space math changes on minute timescales, and the "important
        // usage" key costs a CacheDelete XPC round trip; don't pay it per tick.
        let now = Date()
        if let cached = await state.cachedDisk(at: now) {
            return cached
        }

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
                return await state.updateDisk(.empty, at: now)
            }
            return await state.updateDisk(
                DiskSample(
                    used: min(max(1 - Double(available) / Double(total), 0), 1),
                    availableBytes: Int64(available),
                    totalBytes: Int64(total)
                ),
                at: now
            )
        } catch {
            return await state.updateDisk(.empty, at: now)
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
        let now = Date()
        if let cached = await state.cachedLocalIP(at: now) {
            return cached
        }
        return await state.updateLocalIP(readLocalIPv4(), at: now)
    }

    /// IPv4 of the first preferred interface via getifaddrs, replacing up to
    /// three /usr/sbin/ipconfig spawns per sample. Same interface priority and
    /// nil-when-absent behavior as before.
    private static func readLocalIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var addressByInterface: [String: String] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard
                flags & IFF_UP != 0,
                flags & IFF_LOOPBACK == 0,
                let address = entry.pointee.ifa_addr,
                address.pointee.sa_family == sa_family_t(AF_INET)
            else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }
            addressByInterface[String(cString: entry.pointee.ifa_name)] = Self.string(fromCStringBuffer: host)
        }

        for interface in ["en0", "en1", "bridge100"] {
            if let ip = addressByInterface[interface] {
                return ip
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
        let now = Date()
        if let cached = await state.cachedTopProcesses(at: now) {
            return cached
        }
        let processes = readTopProcesses(limit: 5)
        return await state.updateTopProcesses(processes, at: now)
    }

    /// Top memory consumers read in-process via libproc. The previous
    /// implementation spawned a 4-process shell pipeline (sh, ps, sort, head)
    /// per sample plus a temp file, which dominated the app's resting CPU.
    /// proc_pid_rusage can't read other users' processes, so root daemons no
    /// longer appear; the widget's audience is user apps, which are all visible.
    static func readTopProcesses(limit: Int) -> [ProcessSnapshot] {
        let neededBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard neededBytes > 0 else { return [] }

        // Headroom for processes spawned between the size call and the fill.
        let capacity = Int(neededBytes) / MemoryLayout<pid_t>.size + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let filledBytes = pids.withUnsafeMutableBytes { raw in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, raw.baseAddress, Int32(raw.count))
        }
        guard filledBytes > 0 else { return [] }

        var snapshots: [ProcessSnapshot] = []
        for pid in pids.prefix(Int(filledBytes) / MemoryLayout<pid_t>.size) where pid > 0 {
            var usage = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
                }
            }
            guard status == 0, usage.ri_resident_size > 0 else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 64)
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            snapshots.append(
                ProcessSnapshot(
                    name: Self.string(fromCStringBuffer: nameBuffer),
                    memoryBytes: Int64(usage.ri_resident_size)
                )
            )
        }

        return Array(snapshots.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
    }

    private static func string(fromCStringBuffer buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 3
    ) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(filePath: launchPath)
            process.arguments = arguments

            // Use a temporary file for stdout so a helper cannot block on a full
            // pipe while this task enforces the wall-clock timeout. Output remains
            // byte-for-byte equivalent for the callers below.
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("xeneon-stats-\(UUID().uuidString).out")
            guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
                  let outputHandle = try? FileHandle(forWritingTo: outputURL)
            else {
                return ""
            }
            defer {
                outputHandle.closeFile()
                try? FileManager.default.removeItem(at: outputURL)
            }

            process.standardOutput = outputHandle
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return ""
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    break
                }
            }

            if process.isRunning {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.25)
                while process.isRunning, Date() < terminationDeadline {
                    do {
                        try await Task.sleep(for: .milliseconds(25))
                    } catch {
                        break
                    }
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }

            outputHandle.synchronizeFile()
            outputHandle.closeFile()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            return String(decoding: data, as: UTF8.self)
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
    private var topProcesses: [ProcessSnapshot]?
    private var topProcessesDate: Date?
    private var disk: DiskSample?
    private var diskDate: Date?
    private var localIP: String?
    private var localIPDate: Date?

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

    // Slow-moving samples are cached here so they don't pay their full cost on
    // every 3-second tick: the top-process sweep, the disk XPC round trip, and
    // the interface scan all change on much longer timescales than CPU/network.

    func cachedTopProcesses(at date: Date) -> [ProcessSnapshot]? {
        guard
            let topProcesses,
            let topProcessesDate,
            date.timeIntervalSince(topProcessesDate) < 15
        else {
            return nil
        }
        return topProcesses
    }

    func updateTopProcesses(_ processes: [ProcessSnapshot], at date: Date) -> [ProcessSnapshot] {
        topProcesses = processes
        topProcessesDate = date
        return processes
    }

    func cachedDisk(at date: Date) -> DiskSample? {
        guard
            let disk,
            let diskDate,
            date.timeIntervalSince(diskDate) < 30
        else {
            return nil
        }
        return disk
    }

    func updateDisk(_ sample: DiskSample, at date: Date) -> DiskSample {
        disk = sample
        diskDate = date
        return sample
    }

    /// Double optional: `.some(nil)` is a cached "no address" result, `nil`
    /// means the cache is cold.
    func cachedLocalIP(at date: Date) -> String?? {
        guard
            let localIPDate,
            date.timeIntervalSince(localIPDate) < 60
        else {
            return nil
        }
        return .some(localIP)
    }

    func updateLocalIP(_ ip: String?, at date: Date) -> String? {
        localIP = ip
        localIPDate = date
        return ip
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
