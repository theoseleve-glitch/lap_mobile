import XCTest
@testable import LapCoachMobileApp

final class LapTraceTests: XCTestCase {
    func testTracePointsAreOrdered() {
        let trace = LapTrace(
            lapIndex: 1,
            durationSeconds: 42.0,
            points: [
                LapTracePoint(cumulativeDistanceMeters: 0.0, coordinate: GeoPoint(latitude: 0.0, longitude: 0.0), elapsedTimeSeconds: 0.0),
                LapTracePoint(cumulativeDistanceMeters: 50.0, coordinate: GeoPoint(latitude: 0.0, longitude: 0.001), elapsedTimeSeconds: 5.0),
                LapTracePoint(cumulativeDistanceMeters: 120.0, coordinate: GeoPoint(latitude: 0.001, longitude: 0.001), elapsedTimeSeconds: 12.0),
            ]
        )

        XCTAssertEqual(trace.points.count, 3)
        XCTAssertEqual(trace.lapIndex, 1)
        XCTAssertEqual(trace.durationSeconds, 42.0)
    }

    func testNearestIndexByDistanceFindsClosest() {
        let points = (0..<10).map { i in
            LapTracePoint(
                cumulativeDistanceMeters: Double(i) * 50.0,
                coordinate: GeoPoint(latitude: 0.0, longitude: Double(i) * 0.0005),
                elapsedTimeSeconds: Double(i) * 4.0
            )
        }
        let trace = LapTrace(lapIndex: 1, durationSeconds: 36.0, points: points)

        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: 120.0), 2)
        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: 200.0), 4)
        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: 999.0), 9)
        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: -10.0), 0)
    }

    func testNearestIndexByGPSWithinWindow() {
        let points = [
            LapTracePoint(cumulativeDistanceMeters: 0.0, coordinate: GeoPoint(latitude: 0.0, longitude: 0.0), elapsedTimeSeconds: 0.0),
            LapTracePoint(cumulativeDistanceMeters: 50.0, coordinate: GeoPoint(latitude: 0.0, longitude: 0.001), elapsedTimeSeconds: 5.0),
            LapTracePoint(cumulativeDistanceMeters: 100.0, coordinate: GeoPoint(latitude: 0.001, longitude: 0.001), elapsedTimeSeconds: 10.0),
            LapTracePoint(cumulativeDistanceMeters: 150.0, coordinate: GeoPoint(latitude: 0.001, longitude: 0.0), elapsedTimeSeconds: 15.0),
            LapTracePoint(cumulativeDistanceMeters: 200.0, coordinate: GeoPoint(latitude: 0.0, longitude: 0.0), elapsedTimeSeconds: 20.0),
        ]
        let trace = LapTrace(lapIndex: 1, durationSeconds: 20.0, points: points)

        let target = GeoPoint(latitude: 0.0, longitude: 0.0009)
        let refined = trace.nearestIndex(byGPS: target, around: 2, windowSize: 5)
        XCTAssertEqual(refined, 1)
    }

    func testEmptyTraceReturnsNilIndex() {
        let trace = LapTrace(lapIndex: 1, durationSeconds: 0.0, points: [])
        XCTAssertNil(trace.nearestIndex(byCumulativeDistance: 50.0))
    }
}
