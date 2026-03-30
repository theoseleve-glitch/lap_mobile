import Foundation

struct SessionStatisticsAccumulator: Sendable {
    private var lapEngine: LapTimingEngine?
    private var previousCoordinate: GeoPoint?

    private(set) var sampleCount = 0
    private(set) var maxSpeedMps = 0.0
    private(set) var distanceMeters = 0.0
    private(set) var laps: [LapRecord] = []
    private(set) var startedAtMs: Int64?
    private(set) var endedAtMs: Int64?

    init(track: Track?) {
        if let line = track?.startFinishLine {
            lapEngine = LapTimingEngine(startFinishLine: line)
        }
    }

    mutating func consume(_ sample: SensorSample) {
        sampleCount += 1
        startedAtMs = startedAtMs ?? sample.timestampMs
        endedAtMs = sample.timestampMs
        maxSpeedMps = max(maxSpeedMps, sample.speedMps ?? 0.0)

        if let coordinate = sample.coordinate {
            if let previousCoordinate {
                distanceMeters += previousCoordinate.distance(to: coordinate)
            }
            previousCoordinate = coordinate
        }

        if var lapEngine {
            if let lap = lapEngine.consume(sample) {
                laps.append(lap)
            }
            self.lapEngine = lapEngine
        }
    }

    func makeSummary() -> SessionSummary {
        let durationMs = max(0, (endedAtMs ?? startedAtMs ?? 0) - (startedAtMs ?? 0))
        return SessionSummary(
            durationSeconds: Double(durationMs) / 1_000.0,
            totalSamples: sampleCount,
            distanceMeters: distanceMeters,
            maxSpeedMps: maxSpeedMps,
            laps: laps
        )
    }
}

struct LapTimingEngine: Sendable {
    let startFinishLine: StartFinishLine
    let minimumLapDurationMs: Int64

    private var previousSample: SensorSample?
    private var lapStartTimestampMs: Int64?
    private var bestLapDurationMs: Int64?
    private var lapCount = 0

    init(startFinishLine: StartFinishLine, minimumLapDurationMs: Int64 = 10_000) {
        self.startFinishLine = startFinishLine
        self.minimumLapDurationMs = minimumLapDurationMs
    }

    mutating func consume(_ sample: SensorSample) -> LapRecord? {
        defer { previousSample = sample }

        if lapStartTimestampMs == nil {
            lapStartTimestampMs = sample.timestampMs
            return nil
        }

        guard
            let previousSample,
            let start = previousSample.coordinate,
            let end = sample.coordinate,
            segmentsIntersect(start, end, startFinishLine.start, startFinishLine.end)
        else {
            return nil
        }

        let currentLapDurationMs = sample.timestampMs - (lapStartTimestampMs ?? sample.timestampMs)
        guard currentLapDurationMs >= minimumLapDurationMs else {
            return nil
        }

        lapCount += 1
        lapStartTimestampMs = sample.timestampMs

        let bestBefore = bestLapDurationMs
        if bestBefore == nil || currentLapDurationMs < bestBefore ?? .max {
            bestLapDurationMs = currentLapDurationMs
        }

        let delta = bestBefore.map { Double(currentLapDurationMs - $0) / 1_000.0 }
        return LapRecord(
            index: lapCount,
            durationSeconds: Double(currentLapDurationMs) / 1_000.0,
            deltaToBestSeconds: delta
        )
    }

    private func segmentsIntersect(_ p1: GeoPoint, _ p2: GeoPoint, _ q1: GeoPoint, _ q2: GeoPoint) -> Bool {
        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)
        return o1 != o2 && o3 != o4
    }

    private func orientation(_ a: GeoPoint, _ b: GeoPoint, _ c: GeoPoint) -> Int {
        let value = (b.longitude - a.longitude) * (c.latitude - b.latitude)
            - (b.latitude - a.latitude) * (c.longitude - b.longitude)
        if abs(value) < 1e-12 { return 0 }
        return value > 0 ? 1 : 2
    }
}
