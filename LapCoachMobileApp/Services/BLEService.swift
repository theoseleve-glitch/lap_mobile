import CoreBluetooth
import Foundation

protocol BLEServiceType: AnyObject {
    var onTelemetry: ((RaceBoxTelemetrySample) -> Void)? { get set }
    var onConnectionStateChange: ((BLEConnectionState) -> Void)? { get set }
    var onPeripheralNameChange: ((String?) -> Void)? { get set }
    func startScanning()
    func stop()
}

final class BLEService: NSObject, BLEServiceType, CBCentralManagerDelegate, CBPeripheralDelegate {
    private lazy var central = CBCentralManager(
        delegate: self,
        queue: nil,
        options: [CBCentralManagerOptionRestoreIdentifierKey: "com.lapcoach.racebox"]
    )

    private let parser = RaceBoxParser()
    private var shouldScan = false
    private var connectedPeripheral: CBPeripheral?

    var onTelemetry: ((RaceBoxTelemetrySample) -> Void)?
    var onConnectionStateChange: ((BLEConnectionState) -> Void)?
    var onPeripheralNameChange: ((String?) -> Void)?

    func startScanning() {
        shouldScan = true
        parser.reset()
        if central.state == .poweredOn {
            onConnectionStateChange?(.scanning)
            central.scanForPeripherals(withServices: [UARTService.serviceUUID], options: nil)
        }
    }

    func stop() {
        shouldScan = false
        central.stopScan()
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        parser.reset()
        onConnectionStateChange?(.disconnected)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if shouldScan {
                startScanning()
            }
        case .poweredOff:
            onConnectionStateChange?(.poweredOff)
        default:
            onConnectionStateChange?(.idle)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard UARTService.matchesRaceBoxName(peripheral.name) else { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        onPeripheralNameChange?(peripheral.name)
        onConnectionStateChange?(.connecting)
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnectionStateChange?(.connected)
        peripheral.discoverServices([UARTService.serviceUUID, UARTService.deviceInfoUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onConnectionStateChange?(error == nil ? .disconnected : .failed)
        if shouldScan {
            startScanning()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == UARTService.serviceUUID {
            peripheral.discoverCharacteristics([UARTService.txUUID, UARTService.rxUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == UARTService.txUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        parser.append(data).forEach { onTelemetry?($0) }
    }
}
