@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class BLEBatteryScanner: NSObject {
    static let shared = BLEBatteryScanner()

    private let batteryService = CBUUID(string: "180F")
    private let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private let snapshotLifetime: TimeInterval = 120
    private var central: CBCentralManager?
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var pendingConnectIDs: Set<UUID> = []
    private var namesByID: [UUID: String] = [:]
    private var snapshotsByID: [UUID: DeviceBatterySnapshot] = [:]
    private var snapshotDatesByID: [UUID: Date] = [:]
    private var lastScanStart: Date?
    private var stopScanTask: Task<Void, Never>?

    func start() {
        expireStaleSnapshots(at: Date())
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            refreshIfNeeded()
        }
    }

    func currentBatteries() -> [DeviceBatterySnapshot] {
        start()
        return Array(snapshotsByID.values)
    }

    /// Stops scanning, cancels every active or pending link, and permits the next
    /// `start()` to begin a fresh scan immediately. Cached readings are retained
    /// until their normal expiry so a short lifecycle pause does not blank the UI.
    func stop() {
        stopScanTask?.cancel()
        stopScanTask = nil
        central?.stopScan()
        cancelAllConnections()
        lastScanStart = nil
    }

    private func refreshIfNeeded() {
        guard central?.state == .poweredOn else { return }

        let now = Date()
        if let lastScanStart, now.timeIntervalSince(lastScanStart) < 45 {
            return
        }
        lastScanStart = now

        central?.scanForPeripherals(
            withServices: [batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        stopScanTask?.cancel()
        stopScanTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finishScan()
        }
    }

    private func finishScan() {
        central?.stopScan()
        cancelPendingConnections()
        expireStaleSnapshots(at: Date())
        stopScanTask = nil
    }

    // CoreBluetooth's connect(_:) never times out on its own. When scanning
    // stops, cancel any connect attempts that have not completed so stuck
    // peripherals do not accumulate as pending links across re-scans.
    private func cancelPendingConnections() {
        for id in pendingConnectIDs {
            if let peripheral = peripheralsByID[id] {
                central?.cancelPeripheralConnection(peripheral)
            }
            peripheralsByID.removeValue(forKey: id)
        }
        pendingConnectIDs.removeAll()
    }

    private func cancelAllConnections() {
        let peripherals = Array(peripheralsByID.values)
        for peripheral in peripherals {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheralsByID.removeAll()
        pendingConnectIDs.removeAll()
    }

    private func expireStaleSnapshots(at date: Date) {
        for (id, snapshotDate) in snapshotDatesByID {
            guard date.timeIntervalSince(snapshotDate) >= snapshotLifetime else { continue }
            snapshotsByID.removeValue(forKey: id)
            snapshotDatesByID.removeValue(forKey: id)
        }
    }

    private func rememberName(_ peripheral: CBPeripheral, advertisementData: [String: Any]) {
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            namesByID[peripheral.identifier] = localName
            return
        }

        if let name = peripheral.name, !name.isEmpty {
            namesByID[peripheral.identifier] = name
        }
    }
}

extension BLEBatteryScanner: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            refreshIfNeeded()
        } else {
            stopScanTask?.cancel()
            stopScanTask = nil
            central.stopScan()
            cancelAllConnections()
            lastScanStart = nil
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        rememberName(peripheral, advertisementData: advertisementData)
        // Skip devices already connected or with a connect attempt in flight so
        // re-scans every 45s do not stack duplicate connect calls.
        if peripheralsByID[peripheral.identifier] != nil { return }
        peripheralsByID[peripheral.identifier] = peripheral
        pendingConnectIDs.insert(peripheral.identifier)
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        pendingConnectIDs.remove(peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices([batteryService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        pendingConnectIDs.remove(peripheral.identifier)
        peripheralsByID.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        pendingConnectIDs.remove(peripheral.identifier)
        peripheralsByID.removeValue(forKey: peripheral.identifier)
    }
}

extension BLEBatteryScanner: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        for service in services where service.uuid == batteryService {
            peripheral.discoverCharacteristics([batteryLevelCharacteristic], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        for characteristic in characteristics where characteristic.uuid == batteryLevelCharacteristic {
            peripheral.readValue(for: characteristic)
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, characteristic.uuid == batteryLevelCharacteristic else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        guard let value = characteristic.value, let byte = value.first else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        // GATT Battery Level (0x2A19) is defined only for 0-100. Values 101-255 are
        // reserved/invalid (some peripherals send 0xFF for "unknown"); reject them
        // rather than clamping, so an invalid byte is not surfaced as 100% charged.
        guard byte <= 100 else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }

        let percent = min(max(Double(byte) / 100, 0), 1)
        let name = namesByID[peripheral.identifier] ?? peripheral.name ?? "BLE Device"
        snapshotsByID[peripheral.identifier] = DeviceBatterySnapshot(
            name: name,
            percent: percent,
            isCharging: nil,
            kind: "BLE Battery Service",
            source: .bluetoothLE
        )
        snapshotDatesByID[peripheral.identifier] = Date()

        // Battery level captured; release the link. didDisconnectPeripheral
        // drops the peripheral from peripheralsByID so the next re-scan can
        // reconnect to read a fresh value instead of holding the radio open.
        central?.cancelPeripheralConnection(peripheral)
    }
}
