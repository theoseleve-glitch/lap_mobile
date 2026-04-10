# Dashboard UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the live recording dashboard as a landscape-optimized HUD with live delta-to-best as the hero metric, backed by a hybrid distance+GPS delta engine.

**Architecture:** Two new pure-data models (`LapTrace`, `LapDeltaTracker`) feed into the existing `SessionStatisticsAccumulator` → `SessionManager` → `DashboardViewModel` → `DashboardView` pipeline. The delta engine is in-memory only — no storage/network changes. The view is a full rewrite targeting landscape orientation.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest

**Spec:** `docs/superpowers/specs/2026-04-10-dashboard-ux-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `LapCoachMobileApp/Models/LapTrace.swift` | Create | `LapTracePoint` and `LapTrace` data structures |
| `LapCoachMobileApp/Models/LapDeltaTracker.swift` | Create | Hybrid distance+GPS delta computation against a reference trace |
| `LapCoachMobileApp/DataModels/SampleModel.swift` | Modify | Extend `SessionStatisticsAccumulator` to build lap traces and maintain best lap trace; extend `LapTimingEngine` to emit lap start timestamps |
| `LapCoachMobileApp/ViewModels/SessionManager.swift` | Modify | Publish `liveDelta: Double?`, feed samples into delta tracker, reset on lap crossing |
| `LapCoachMobileApp/ViewModels/DashboardViewModel.swift` | Modify | Expose formatted delta, current lap time, sorted laps with pinned best, status bar visibility |
| `LapCoachMobileApp/Views/DashboardView.swift` | Rewrite | Landscape split-focus layout: hero zone, lap table, conditional status bar |
| `LapCoachMobileAppTests/LapTraceTests.swift` | Create | Tests for `LapTrace` construction |
| `LapCoachMobileAppTests/LapDeltaTrackerTests.swift` | Create | Tests for delta computation: ahead, behind, no reference, low speed clamp, distance divergence |
| `LapCoachMobileAppTests/LapTimingEngineTests.swift` | Modify | Add test for trace-building integration in `SessionStatisticsAccumulator` |

---

### Task 1: LapTrace Data Structures

**Files:**
- Create: `LapCoachMobileApp/Models/LapTrace.swift`
- Create: `LapCoachMobileAppTests/LapTraceTests.swift`

- [ ] **Step 1: Write the test file**

```swift
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

        // 120m is between index 2 (100m) and index 3 (150m) — should return 2
        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: 120.0), 2)
        // Exact match at 200m
        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: 200.0), 4)
        // Beyond trace end
        XCTAssertEqual(trace.nearestIndex(byCumulativeDistance: 999.0), 9)
        // Before trace start
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

        // Near index 2 by distance, but GPS closest to index 1 within window
        let target = GeoPoint(latitude: 0.0, longitude: 0.0009)
        let refined = trace.nearestIndex(byGPS: target, around: 2, windowSize: 5)
        XCTAssertEqual(refined, 1)
    }

    func testEmptyTraceReturnsNilIndex() {
        let trace = LapTrace(lapIndex: 1, durationSeconds: 0.0, points: [])
        XCTAssertNil(trace.nearestIndex(byCumulativeDistance: 50.0))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing LapCoachMobileAppTests/LapTraceTests 2>&1 | tail -20`
Expected: Compilation failure — `LapTrace`, `LapTracePoint` not defined.

- [ ] **Step 3: Implement LapTrace**

Create `LapCoachMobileApp/Models/LapTrace.swift`:

```swift
import Foundation

struct LapTracePoint: Sendable {
    let cumulativeDistanceMeters: Double
    let coordinate: GeoPoint
    let elapsedTimeSeconds: Double
}

struct LapTrace: Sendable {
    let lapIndex: Int
    let durationSeconds: Double
    let points: [LapTracePoint]

    /// Binary search for the index whose cumulative distance is closest to `distance`.
    /// Returns nil if points is empty.
    func nearestIndex(byCumulativeDistance distance: Double) -> Int? {
        guard points.isEmpty == false else { return nil }

        var lo = 0
        var hi = points.count - 1

        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].cumulativeDistanceMeters < distance {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // lo is the first index >= distance. Check if lo-1 is closer.
        if lo > 0 {
            let distLo = abs(points[lo].cumulativeDistanceMeters - distance)
            let distPrev = abs(points[lo - 1].cumulativeDistanceMeters - distance)
            if distPrev < distLo {
                return lo - 1
            }
        }

        return lo
    }

    /// Within a window around `centerIndex`, find the point closest to `coordinate` by haversine distance.
    func nearestIndex(byGPS coordinate: GeoPoint, around centerIndex: Int, windowSize: Int = 5) -> Int {
        let lo = max(0, centerIndex - windowSize)
        let hi = min(points.count - 1, centerIndex + windowSize)
        guard lo <= hi else { return centerIndex }

        var bestIndex = centerIndex
        var bestDistance = Double.greatestFiniteMagnitude

        for i in lo...hi {
            let d = points[i].coordinate.distance(to: coordinate)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }

        return bestIndex
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing LapCoachMobileAppTests/LapTraceTests 2>&1 | tail -20`
Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LapCoachMobileApp/Models/LapTrace.swift LapCoachMobileAppTests/LapTraceTests.swift
git commit -m "feat(dashboard): add LapTrace data structures with distance and GPS lookup"
```

---

### Task 2: LapDeltaTracker

**Files:**
- Create: `LapCoachMobileApp/Models/LapDeltaTracker.swift`
- Create: `LapCoachMobileAppTests/LapDeltaTrackerTests.swift`

- [ ] **Step 1: Write the test file**

```swift
import XCTest
@testable import LapCoachMobileApp

final class LapDeltaTrackerTests: XCTestCase {

    private func makeReference() -> LapTrace {
        // Simulates a 40-second lap over 10 equally spaced points (every 4s, every 50m)
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
        // At 100m, reference elapsed = 8.0s. Current elapsed = 7.0s. Delta = -1.0
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
        // At 100m, reference elapsed = 8.0s. Current elapsed = 9.5s. Delta = +1.5
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
            speedMps: 3.0 // Below 5 km/h threshold (< 1.39 m/s)
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
        // After reset, first update should still work (cursor back to 0)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing LapCoachMobileAppTests/LapDeltaTrackerTests 2>&1 | tail -20`
Expected: Compilation failure — `LapDeltaTracker` not defined.

- [ ] **Step 3: Implement LapDeltaTracker**

Create `LapCoachMobileApp/Models/LapDeltaTracker.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing LapCoachMobileAppTests/LapDeltaTrackerTests 2>&1 | tail -20`
Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LapCoachMobileApp/Models/LapDeltaTracker.swift LapCoachMobileAppTests/LapDeltaTrackerTests.swift
git commit -m "feat(dashboard): add LapDeltaTracker with hybrid distance+GPS matching"
```

---

### Task 3: Integrate Trace Building into SessionStatisticsAccumulator

**Files:**
- Modify: `LapCoachMobileApp/DataModels/SampleModel.swift`
- Modify: `LapCoachMobileAppTests/LapTimingEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `LapCoachMobileAppTests/LapTimingEngineTests.swift`:

```swift
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

    // Mid-lap sample
    accumulator.consume(SensorSample(
        sessionID: sessionID, timestampMs: 20_000, source: .phone,
        latDeg: 0.5, lonDeg: 0.5, speedMps: 14.0, headingDeg: nil,
        ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
    ))

    // Second crossing -> completes lap 1
    accumulator.consume(SensorSample(
        sessionID: sessionID, timestampMs: 24_000, source: .phone,
        latDeg: 0.0, lonDeg: -0.5, speedMps: 11.0, headingDeg: nil,
        ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
    ))

    // Cross again -> completes lap 2
    accumulator.consume(SensorSample(
        sessionID: sessionID, timestampMs: 36_000, source: .phone,
        latDeg: 0.0, lonDeg: 0.5, speedMps: 13.0, headingDeg: nil,
        ax: nil, ay: nil, az: nil, gx: nil, gy: nil, gz: nil, horizontalAccuracy: nil
    ))

    XCTAssertEqual(accumulator.laps.count, 2)
    XCTAssertNotNil(accumulator.bestLapTrace)
    XCTAssertGreaterThan(accumulator.bestLapTrace!.points.count, 0)
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing LapCoachMobileAppTests/LapTimingEngineTests 2>&1 | tail -20`
Expected: Compilation failure — `bestLapTrace`, `currentLapDistanceMeters`, `currentLapElapsedSeconds` not found on `SessionStatisticsAccumulator`.

- [ ] **Step 3: Extend SessionStatisticsAccumulator**

Edit `LapCoachMobileApp/DataModels/SampleModel.swift`. Add new stored properties and trace-building logic to `SessionStatisticsAccumulator`:

Replace the existing `SessionStatisticsAccumulator` struct with:

```swift
struct SessionStatisticsAccumulator: Sendable {
    private var lapEngine: LapTimingEngine?
    private var previousCoordinate: GeoPoint?

    private(set) var sampleCount = 0
    private(set) var maxSpeedMps = 0.0
    private(set) var distanceMeters = 0.0
    private(set) var laps: [LapRecord] = []
    private(set) var startedAtMs: Int64?
    private(set) var endedAtMs: Int64?

    // Trace building
    private(set) var bestLapTrace: LapTrace?
    private(set) var currentLapDistanceMeters = 0.0
    private(set) var currentLapElapsedSeconds = 0.0
    private var currentLapPoints: [LapTracePoint] = []
    private var currentLapStartMs: Int64?
    private var lapDistanceAtLapStart = 0.0

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

        // Track current lap metrics
        if currentLapStartMs == nil {
            currentLapStartMs = sample.timestampMs
            lapDistanceAtLapStart = distanceMeters
        }
        currentLapDistanceMeters = distanceMeters - lapDistanceAtLapStart
        currentLapElapsedSeconds = Double(sample.timestampMs - (currentLapStartMs ?? sample.timestampMs)) / 1_000.0

        // Build trace point for current lap
        if let coordinate = sample.coordinate {
            currentLapPoints.append(LapTracePoint(
                cumulativeDistanceMeters: currentLapDistanceMeters,
                coordinate: coordinate,
                elapsedTimeSeconds: currentLapElapsedSeconds
            ))
        }

        if var lapEngine {
            if let lap = lapEngine.consume(sample) {
                laps.append(lap)
                finalizeLapTrace(lap: lap)
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

    private mutating func finalizeLapTrace(lap: LapRecord) {
        // Skip trace storage for very short laps (< 10 GPS samples)
        guard currentLapPoints.count >= 10 else {
            currentLapPoints = []
            currentLapStartMs = endedAtMs
            lapDistanceAtLapStart = distanceMeters
            currentLapDistanceMeters = 0.0
            currentLapElapsedSeconds = 0.0
            return
        }

        let trace = LapTrace(
            lapIndex: lap.index,
            durationSeconds: lap.durationSeconds,
            points: currentLapPoints
        )

        // Update best if this lap is the new best (or first)
        if bestLapTrace == nil || lap.durationSeconds < (bestLapTrace?.durationSeconds ?? .greatestFiniteMagnitude) {
            bestLapTrace = trace
        }

        // Reset for next lap
        currentLapPoints = []
        currentLapStartMs = endedAtMs
        lapDistanceAtLapStart = distanceMeters
        currentLapDistanceMeters = 0.0
        currentLapElapsedSeconds = 0.0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing LapCoachMobileAppTests/LapTimingEngineTests 2>&1 | tail -20`
Expected: All tests PASS (existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add LapCoachMobileApp/DataModels/SampleModel.swift LapCoachMobileAppTests/LapTimingEngineTests.swift
git commit -m "feat(dashboard): build lap traces in SessionStatisticsAccumulator"
```

---

### Task 4: Publish Live Delta from SessionManager

**Files:**
- Modify: `LapCoachMobileApp/ViewModels/SessionManager.swift`

- [ ] **Step 1: Add published properties and delta tracker**

Add new properties near the existing `@Published` block in `SessionManager`:

```swift
@Published private(set) var liveDelta: Double?
@Published private(set) var currentLapTime: TimeInterval = 0.0
@Published private(set) var bestLapTrace: LapTrace?
```

Add a private stored property:

```swift
private var deltaTracker = LapDeltaTracker(referenceLap: nil)
```

- [ ] **Step 2: Feed samples into the delta tracker**

In the existing `enqueueSample(_:)` method, after the `statistics.consume(sample)` call, add delta tracking logic:

```swift
// Update delta tracker reference if a new best emerged
if let trace = statistics.bestLapTrace, trace.lapIndex != bestLapTrace?.lapIndex {
    bestLapTrace = trace
    deltaTracker.setReference(trace)
    deltaTracker.reset()
}

// Compute live delta
if let coordinate = sample.coordinate {
    liveDelta = deltaTracker.update(
        coordinate: coordinate,
        cumulativeDistance: statistics.currentLapDistanceMeters,
        elapsedTime: statistics.currentLapElapsedSeconds,
        speedMps: sample.speedMps ?? 0.0
    )
}

currentLapTime = statistics.currentLapElapsedSeconds
```

- [ ] **Step 3: Reset delta tracker on recording stop and start**

In `resetSessionState(track:)`, add:

```swift
liveDelta = nil
currentLapTime = 0.0
bestLapTrace = nil
deltaTracker = LapDeltaTracker(referenceLap: nil)
```

- [ ] **Step 4: Build and verify no compilation errors**

Run: `xcodebuild build -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run full test suite**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add LapCoachMobileApp/ViewModels/SessionManager.swift
git commit -m "feat(dashboard): publish liveDelta and currentLapTime from SessionManager"
```

---

### Task 5: Expand DashboardViewModel

**Files:**
- Modify: `LapCoachMobileApp/ViewModels/DashboardViewModel.swift`

- [ ] **Step 1: Rewrite DashboardViewModel**

Replace the contents of `DashboardViewModel.swift` with:

```swift
import Combine
import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var liveDeltaText = "--"
    @Published private(set) var liveDeltaColor: Color = .white
    @Published private(set) var currentLapTimeText = "0.00"
    @Published private(set) var currentLapLabel = "Lap 0"
    @Published private(set) var speedText = "0"
    @Published private(set) var accelerationText = "0.0 g"
    @Published private(set) var sourceText = "Phone"
    @Published private(set) var bestLap: LapRecord?
    @Published private(set) var sortedLaps: [LapRecord] = []
    @Published private(set) var isStatusBarVisible = true

    private var cancellables: Set<AnyCancellable> = []
    private var statusBarHideTask: Task<Void, Never>?

    init(sessionManager: SessionManager) {
        // Speed, accel, source, lap label
        sessionManager.$latestSample
            .combineLatest(sessionManager.$lapCount, sessionManager.$activeSession)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample, lapCount, session in
                let speedKph = (sample?.speedMps ?? 0.0) * 3.6
                self?.speedText = "\(Int(speedKph.rounded()))"
                self?.accelerationText = String(format: "%.1f g", sample?.accelerationMagnitudeG ?? 0.0)
                self?.sourceText = session?.sourceMode.title ?? "Phone"
                self?.currentLapLabel = "Lap \(lapCount + 1)"
            }
            .store(in: &cancellables)

        // Live delta
        sessionManager.$liveDelta
            .receive(on: DispatchQueue.main)
            .sink { [weak self] delta in
                guard let self else { return }
                if let delta {
                    let sign = delta >= 0 ? "+" : ""
                    self.liveDeltaText = "\(sign)\(String(format: "%.2f", delta))"
                    self.liveDeltaColor = delta <= 0 ? BrandTheme.success : BrandTheme.danger
                } else {
                    self.liveDeltaText = "--"
                    self.liveDeltaColor = .white
                }
            }
            .store(in: &cancellables)

        // Current lap time
        sessionManager.$currentLapTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] elapsed in
                let minutes = Int(elapsed) / 60
                let seconds = elapsed.truncatingRemainder(dividingBy: 60.0)
                if minutes > 0 {
                    self?.currentLapTimeText = String(format: "%d:%05.2f", minutes, seconds)
                } else {
                    self?.currentLapTimeText = String(format: "%.2f", seconds)
                }
            }
            .store(in: &cancellables)

        // Lap table: pinned best + reverse chronological
        sessionManager.$activeSession
            .compactMap { $0?.summary?.laps }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] laps in
                guard let self else { return }
                self.bestLap = laps.min(by: { $0.durationSeconds < $1.durationSeconds })
                self.sortedLaps = laps
                    .filter { $0.index != self.bestLap?.index }
                    .sorted { $0.index > $1.index }
            }
            .store(in: &cancellables)

        // Status bar: show on connection state change, auto-hide after GPS fix
        sessionManager.$bleConnectionState
            .combineLatest(sessionManager.$gpsAuthorizationState, sessionManager.$latestSample)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bleState, gpsState, sample in
                guard let self else { return }
                let hasSignalIssue = bleState == .disconnected || bleState == .failed || bleState == .poweredOff
                if hasSignalIssue {
                    self.isStatusBarVisible = true
                    self.statusBarHideTask?.cancel()
                } else if sample != nil, self.isStatusBarVisible {
                    // Got a sample — schedule hide
                    self.scheduleStatusBarHide()
                }
            }
            .store(in: &cancellables)

        scheduleStatusBarHide()
    }

    private func scheduleStatusBarHide() {
        statusBarHideTask?.cancel()
        statusBarHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard Task.isCancelled == false else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.isStatusBarVisible = false
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add LapCoachMobileApp/ViewModels/DashboardViewModel.swift
git commit -m "feat(dashboard): expand DashboardViewModel with live delta, lap table, status bar logic"
```

---

### Task 6: Rewrite DashboardView for Landscape

**Files:**
- Rewrite: `LapCoachMobileApp/Views/DashboardView.swift`

- [ ] **Step 1: Rewrite DashboardView**

Replace the entire contents of `DashboardView.swift` with:

```swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var sessionManager: SessionManager
    @StateObject private var viewModel: DashboardViewModel

    let stopAction: () -> Void

    init(sessionManager: SessionManager, stopAction: @escaping () -> Void) {
        self.sessionManager = sessionManager
        self.stopAction = stopAction
        _viewModel = StateObject(wrappedValue: DashboardViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        ZStack {
            BrandTheme.heroGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                heroZone
                lapTable
                if viewModel.isStatusBarVisible {
                    statusBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Hero Zone

    private var heroZone: some View {
        HStack(spacing: 0) {
            // Left: Live delta
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.liveDeltaText)
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.liveDeltaColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    Text(viewModel.currentLapLabel)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(viewModel.currentLapTimeText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                    Text(viewModel.accelerationText)
                        .font(.title3.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)

            // Right: Speed + stop
            VStack(alignment: .trailing, spacing: 4) {
                Button(role: .destructive) {
                    stopAction()
                } label: {
                    Text(sessionManager.state == .finalizing ? "Finalizing" : "Stop")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrandTheme.danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .disabled(sessionManager.state == .finalizing)

                Spacer()

                Text(viewModel.speedText)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("km/h")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 28)
        }
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.08))
    }

    // MARK: - Lap Table

    private var lapTable: some View {
        VStack(spacing: 0) {
            if let best = viewModel.bestLap {
                bestLapRow(best)
            }

            if viewModel.bestLap == nil && viewModel.sortedLaps.isEmpty {
                Text("Waiting for first lap crossing...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.sortedLaps) { lap in
                            lapRow(lap)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.3), value: viewModel.sortedLaps.map(\.index))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func bestLapRow(_ lap: LapRecord) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.warning)
                Text("Lap \(lap.index)")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(formatLapTime(lap.durationSeconds))
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text("BEST")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(BrandTheme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(BrandTheme.warning.opacity(0.2))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(BrandTheme.warning.opacity(0.1))
    }

    private func lapRow(_ lap: LapRecord) -> some View {
        HStack {
            Text("Lap \(lap.index)")
                .font(.subheadline)
            Spacer()
            Text(formatLapTime(lap.durationSeconds))
                .font(.subheadline.monospacedDigit())
            if let delta = lap.deltaToBestSeconds {
                Text(String(format: "%+.2f", delta))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(delta <= 0 ? BrandTheme.success : BrandTheme.danger)
                    .frame(width: 80, alignment: .trailing)
            } else {
                Text("--")
                    .font(.subheadline)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(sessionElapsedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    private var statusDotColor: Color {
        switch sessionManager.bleConnectionState {
        case .connected:
            return BrandTheme.success
        case .scanning, .connecting:
            return BrandTheme.warning
        default:
            return sessionManager.activeSession?.sourceMode == .phone ? BrandTheme.success : BrandTheme.danger
        }
    }

    private var statusText: String {
        if let name = sessionManager.connectedPeripheralName {
            return name
        }
        switch sessionManager.bleConnectionState {
        case .scanning:
            return "Scanning for RaceBox..."
        case .connecting:
            return "Connecting..."
        case .disconnected, .failed:
            return "RaceBox disconnected — reconnecting..."
        case .poweredOff:
            return "Bluetooth is off"
        default:
            return sessionManager.activeSession?.sourceMode == .phone ? "Phone GPS" : "Idle"
        }
    }

    private var sessionElapsedText: String {
        let elapsed = sessionManager.elapsedTime
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatLapTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60.0)
        if minutes > 0 {
            return String(format: "%d:%05.2f", minutes, secs)
        }
        return String(format: "%.2f", secs)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild build -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run on simulator and visually verify landscape layout**

Run: `xcodebuild build -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16'`
Then open the simulator, rotate to landscape, start a session, and verify:
- Delta `--` shows large on the left in white
- Speed `0` shows large on the right
- "Waiting for first lap crossing..." appears in the lap area
- Stop button is in the top-right corner
- Status bar is visible briefly then auto-hides

- [ ] **Step 4: Run full test suite**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add LapCoachMobileApp/Views/DashboardView.swift
git commit -m "feat(dashboard): rewrite DashboardView as landscape split-focus HUD"
```

---

### Task 7: Wire Up Lap Data from Summary to ViewModel

The `DashboardViewModel` subscribes to `activeSession?.summary?.laps`, but `SessionManager.activeSession` only gets its summary set during `stopRecording()`. During recording, laps are in `statistics.laps` but not on the published `activeSession`. We need to publish laps live.

**Files:**
- Modify: `LapCoachMobileApp/ViewModels/SessionManager.swift`
- Modify: `LapCoachMobileApp/ViewModels/DashboardViewModel.swift`

- [ ] **Step 1: Add a published laps property to SessionManager**

In `SessionManager`, add a new published property:

```swift
@Published private(set) var completedLaps: [LapRecord] = []
```

In `enqueueSample(_:)`, after updating `lapCount`, add:

```swift
completedLaps = statistics.laps
```

In `resetSessionState(track:)`, add:

```swift
completedLaps = []
```

- [ ] **Step 2: Update DashboardViewModel to use completedLaps**

Replace the lap table subscription in `DashboardViewModel` (the `sessionManager.$activeSession.compactMap` block) with:

```swift
// Lap table: pinned best + reverse chronological
sessionManager.$completedLaps
    .receive(on: DispatchQueue.main)
    .sink { [weak self] laps in
        guard let self else { return }
        self.bestLap = laps.min(by: { $0.durationSeconds < $1.durationSeconds })
        self.sortedLaps = laps
            .filter { $0.index != self.bestLap?.index }
            .sorted { $0.index > $1.index }
    }
    .store(in: &cancellables)
```

- [ ] **Step 3: Build and run tests**

Run: `xcodebuild test -scheme LapCoachMobileApp -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add LapCoachMobileApp/ViewModels/SessionManager.swift LapCoachMobileApp/ViewModels/DashboardViewModel.swift
git commit -m "feat(dashboard): publish live lap records during recording"
```
