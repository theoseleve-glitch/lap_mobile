import Foundation

struct GeoPoint: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180.0
        let lat2 = other.latitude * .pi / 180.0
        let deltaLat = (other.latitude - latitude) * .pi / 180.0
        let deltaLon = (other.longitude - longitude) * .pi / 180.0

        let a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2.0) * sin(deltaLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return earthRadius * c
    }
}

struct StartFinishLine: Codable, Hashable, Sendable {
    let start: GeoPoint
    let end: GeoPoint
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var city: String
    var startFinishLine: StartFinishLine?
    var notes: String?

    static let defaultLibrary: [Track] = [
        Track(
            id: "lydd",
            name: "Lydd Kart Circuit",
            city: "Lydd",
            startFinishLine: StartFinishLine(
                start: GeoPoint(latitude: 50.950060, longitude: 0.906700),
                end: GeoPoint(latitude: 50.950110, longitude: 0.906840)
            ),
            notes: "Reference layout for initial testing."
        ),
        Track(
            id: "genk-club",
            name: "Genk Club Circuit",
            city: "Genk",
            startFinishLine: StartFinishLine(
                start: GeoPoint(latitude: 50.980923, longitude: 5.502328),
                end: GeoPoint(latitude: 50.980830, longitude: 5.502501)
            ),
            notes: "Club layout example."
        ),
        Track(
            id: "custom-track",
            name: "Custom Start-Finish",
            city: "Your Track",
            startFinishLine: nil,
            notes: "Define a custom line before recording timed laps."
        )
    ]
}
