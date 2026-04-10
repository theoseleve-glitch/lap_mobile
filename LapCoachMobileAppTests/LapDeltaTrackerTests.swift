import XCTest
@testable import LapCoachMobileApp

final class LapDeltaTrackerTests: XCTestCase {

    private func makeReference() -> LapTrace {
        let points = (0..<10).map { i in
            LapTracePoint(
                cumulativeDistanceMeters: Double(i) * 50.0,
                coordinate: GeoPoint(latitude: 0.0, longitude: Double(i) * 0.0005),
                elapsedTimeSeconds: Double(i) * 4.0
            )
        }
        return LapTrace(lapIndex: 1, durationSeconds: 40.0, points: points)
    }

    func testDeltaIsNilWithNoReference() {
        var tracker = LapDeltaTracker(referenceLap: nil)
        let delta = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.0),
            cumulativeDistance: 50.0,
            elapsedTime: 3.5,
            speedMps: 15.0
        )
        XCTAssertNil(delta)
    }

    func testAheadOfReferenceLapProducesNegativeDelta() {
        var tracker = LapDeltaTracker(referenceLap: makeReference())
        let delta = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.001),
            cumulativeDistance: 100.0,
            elapsedTime: 7.0,
            speedMps: 15.0
        )
        XCTAssertNotNil(delta)
        XCTAssertLessThan(delta!, 0.0)
    }

    func testBehindReferenceLapProducesPositiveDelta() {
        var tracker = LapDeltaTracker(referenceLap: makeReference())
        let delta = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.001),
            cumulativeDistance: 100.0,
            elapsedTime: 9.5,
            speedMps: 15.0
        )
        XCTAssertNotNil(delta)
        XCTAssertGreaterThan(delta!, 0.0)
    }

    func testLowSpeedClampReturnsNil() {
        var tracker = LapDeltaTracker(referenceLap: makeReference())
        let delta = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.001),
            cumulativeDistance: 100.0,
            elapsedTime: 7.0,
            speedMps: 3.0
        )
        XCTAssertNil(delta)
    }

    func testResetClearsCursor() {
        var tracker = LapDeltaTracker(referenceLap: makeReference())
        _ = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.001),
            cumulativeDistance: 100.0,
            elapsedTime: 7.0,
            speedMps: 15.0
        )
        tracker.reset()
        let delta = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.00025),
            cumulativeDistance: 50.0,
            elapsedTime: 3.5,
            speedMps: 15.0
        )
        XCTAssertNotNil(delta)
    }

    func testUpdateReferenceLap() {
        var tracker = LapDeltaTracker(referenceLap: nil)
        XCTAssertNil(tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.0),
            cumulativeDistance: 50.0,
            elapsedTime: 3.5,
            speedMps: 15.0
        ))

        tracker.setReference(makeReference())
        tracker.reset()

        let delta = tracker.update(
            coordinate: GeoPoint(latitude: 0.0, longitude: 0.001),
            cumulativeDistance: 100.0,
            elapsedTime: 7.0,
            speedMps: 15.0
        )
        XCTAssertNotNil(delta)
    }
}
