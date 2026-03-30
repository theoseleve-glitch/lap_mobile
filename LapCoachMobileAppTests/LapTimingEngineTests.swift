import XCTest
@testable import LapCoachMobileApp

final class LapTimingEngineTests: XCTestCase {
    func testAccumulatorProducesLapWhenPathCrossesLine() {
        let track = Track(
            id: "test-track",
            name: "Test",
            city: "Nowhere",
            startFinishLine: StartFinishLine(
                start: GeoPoint(latitude: -1.0, longitude: 0.0),
                end: GeoPoint(latitude: 1.0, longitude: 0.0)
            ),
            notes: nil
        )

        var accumulator = SessionStatisticsAccumulator(track: track)
        let sessionID = UUID()

        accumulator.consume(
            SensorSample(
                sessionID: sessionID,
                timestampMs: 0,
                source: .phone,
                latDeg: 0.0,
                lonDeg: -0.5,
                speedMps: 10.0,
                headingDeg: nil,
                ax: nil,
                ay: nil,
                az: nil,
                gx: nil,
                gy: nil,
                gz: nil,
                horizontalAccuracy: nil
            )
        )

        accumulator.consume(
            SensorSample(
                sessionID: sessionID,
                timestampMs: 12_000,
                source: .phone,
                latDeg: 0.0,
                lonDeg: 0.5,
                speedMps: 12.0,
                headingDeg: nil,
                ax: nil,
                ay: nil,
                az: nil,
                gx: nil,
                gy: nil,
                gz: nil,
                horizontalAccuracy: nil
            )
        )

        let summary = accumulator.makeSummary()
        XCTAssertEqual(summary.laps.count, 1)
        XCTAssertEqual(summary.laps.first?.durationSeconds, 12.0, accuracy: 0.001)
        XCTAssertGreaterThan(summary.distanceMeters, 0.0)
    }
}
