import CoreBluetooth

enum UARTService {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let txUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let deviceInfoUUID = CBUUID(string: "180A")

    static func matchesRaceBoxName(_ name: String?) -> Bool {
        guard let name else { return false }
        let prefixes = ["RaceBox Mini", "RaceBox Mini S", "RaceBox Micro", "RaceBox"]
        return prefixes.contains(where: { name.hasPrefix($0) })
    }
}
