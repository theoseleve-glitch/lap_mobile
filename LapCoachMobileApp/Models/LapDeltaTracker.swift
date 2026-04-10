import Foundation

struct LapDeltaTracker: Sendable {
    private static let lowSpeedThresholdMps = 5.0 / 3.6 // 5 km/h

    private var referenceLap: LapTrace?
    private var cursorIndex = 0

    init(referenceLap: LapTrace?) {
        self.referenceLap = referenceLap
    }

    mutating func setReference(_ lap: LapTrace) {
        referenceLap = lap
    }

    mutating func reset() {
        cursorIndex = 0
    }

    /// Returns the live delta in seconds (negative = ahead, positive = behind), or nil if
    /// no reference exists, speed is too low, or the trace is empty.
    mutating func update(
        coordinate: GeoPoint,
        cumulativeDistance: Double,
        elapsedTime: Double,
        speedMps: Double
    ) -> Double? {
        guard let referenceLap, referenceLap.points.isEmpty == false else {
            return nil
        }

        guard speedMps >= Self.lowSpeedThresholdMps else {
            return nil
        }

        // Phase 1: distance-based lookup
        guard let distanceIndex = referenceLap.nearestIndex(byCumulativeDistance: cumulativeDistance) else {
            return nil
        }

        // Phase 2: GPS refinement within window around distance match
        let refinedIndex = referenceLap.nearestIndex(byGPS: coordinate, around: distanceIndex, windowSize: 5)
        cursorIndex = refinedIndex

        let referenceElapsed = referenceLap.points[refinedIndex].elapsedTimeSeconds
        return elapsedTime - referenceElapsed
    }
}
