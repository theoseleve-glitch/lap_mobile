import Foundation
import XCTest
@testable import LapCoachMobileApp

final class TrackStoreTests: XCTestCase {
    func testCustomTracksPersistAcrossLoads() async throws {
        let suiteName = "TrackStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = TrackStore(defaults: defaults, storageKey: "custom-tracks")
        let customTrack = Track(
            id: "my-custom-track",
            name: "My Track",
            city: "Paris",
            startFinishLine: StartFinishLine(
                start: GeoPoint(latitude: 48.0, longitude: 2.0),
                end: GeoPoint(latitude: 48.1, longitude: 2.1)
            ),
            notes: "Persist me"
        )

        try await store.saveCustomTracks(Track.defaultLibrary + [customTrack])
        let loadedTracks = await store.loadCustomTracks()

        XCTAssertEqual(loadedTracks, [customTrack])
    }
}
