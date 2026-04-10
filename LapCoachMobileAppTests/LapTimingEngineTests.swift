import XCTest
@testable import LapCoachMobileApp

final class LapTimingEngineTests: XCTestCase {
    func testAccumulatorBuildsBestLapTrace() {
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

        // First sample: west of the line
        accumulator.consume(SensorSample(
            sessionID: sessionID, timestampMs: 0, source: .phone,
            latDeg: 0.0, lonDeg: -0.5, speedMps: 10.0, headingDeg: nil,
            ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
        ))

        // Cross the line -> starts lap timing
        accumulator.consume(SensorSample(
            sessionID: sessionID, timestampMs: 12_000, source: .phone,
            latDeg: 0.0, lonDeg: 0.5, speedMps: 12.0, headingDeg: nil,
            ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
        ))

        // Generate 12 mid-lap samples (need >= 10 for trace storage)
        for i in 1...12 {
            accumulator.consume(SensorSample(
                sessionID: sessionID,
                timestampMs: Int64(12_000 + i * 1_000),
                source: .phone,
                latDeg: Double(i) * 0.05,
                lonDeg: 0.5 - Double(i) * 0.08,
                speedMps: 14.0,
                headingDeg: nil,
                ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
            ))
        }

        // Second crossing -> completes lap 1
        accumulator.consume(SensorSample(
            sessionID: sessionID, timestampMs: 25_000, source: .phone,
            latDeg: 0.0, lonDeg: -0.5, speedMps: 11.0, headingDeg: nil,
            ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
        ))

        // Generate 12 mid-lap samples for lap 2
        for i in 1...12 {
            accumulator.consume(SensorSample(
                sessionID: sessionID,
                timestampMs: Int64(25_000 + i * 1_000),
                source: .phone,
                latDeg: Double(i) * 0.05,
                lonDeg: -0.5 + Double(i) * 0.08,
                speedMps: 13.0,
                headingDeg: nil,
                ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
            ))
        }

        // Cross again -> completes lap 2
        accumulator.consume(SensorSample(
            sessionID: sessionID, timestampMs: 38_000, source: .phone,
            latDeg: 0.0, lonDeg: 0.5, speedMps: 13.0, headingDeg: nil,
            ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
        ))

        XCTAssertEqual(accumulator.laps.count, 2)
        XCTAssertNotNil(accumulator.bestLapTrace)
        XCTAssertGreaterThan(accumulator.bestLapTrace!.points.count, 9)
    }

    func testAccumulatorProvidesCurrentLapDistance() {
        var accumulator = SessionStatisticsAccumulator(track: nil)
        let sessionID = UUID()

        accumulator.consume(SensorSample(
            sessionID: sessionID, timestampMs: 0, source: .phone,
            latDeg: 0.0, lonDeg: 0.0, speedMps: 10.0, headingDeg: nil,
            ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
        ))

        accumulator.consume(SensorSample(
            sessionID: sessionID, timestampMs: 1_000, source: .phone,
            latDeg: 0.001, lonDeg: 0.0, speedMps: 10.0, headingDeg: nil,
            ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
        ))

        XCTAssertGreaterThan(accumulator.currentLapDistanceMeters, 0.0)
        XCTAssertGreaterThan(accumulator.currentLapElapsedSeconds, 0.0)
    }

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
