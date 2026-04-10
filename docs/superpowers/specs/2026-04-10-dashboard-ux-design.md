# Dashboard UX Redesign

## Summary

Redesign the live recording dashboard for landscape-mounted kart racing use. The primary goal is sub-second glanceability with live delta-to-best as the dominant metric.

## Context

The current dashboard is a portrait-oriented vertical scroll with a 2x2 metric grid, a status card, and a stop button. It shows speed, acceleration, lap count, and source mode. The numbers are readable but not optimized for at-speed glances on a kart steering column mount.

The user views the phone in landscape orientation at eye level with sub-second glances. The most valuable information is whether the current lap is ahead or behind the best lap *right now*, not after crossing the line.

## Design

### Layout: Landscape Split-Focus

The screen is divided into three tiers optimized for landscape orientation:

```
Normal state (99% of session):
+---------------------------+---------------------------+
|                           |                      Stop |
|      -0.34                |         87                |
|   (60pt+, green/red)      |     (50pt+, white)        |
|                           |        km/h               |
|  Lap 5 . 0:38.2    1.4g  |                           |
+---------------------------+---------------------------+
| *  Lap 3       41.83s                          BEST   |
+-------------------------------------------------------+
|    Lap 6       42.05s                   +0.22         |
|    Lap 5       41.97s                   +0.14         |
|    Lap 4       42.17s                   +0.34         |
|    Lap 2       43.01s                   +1.18         |
+-------------------------------------------------------+

Signal loss state (rare):
+-------------------------------------------------------+
|  (hero + lap table as above)                          |
+-------------------------------------------------------+
|  * RaceBox disconnected - reconnecting...             |
+-------------------------------------------------------+
```

### Tier 1: Hero Zone (~45% of screen)

Two-column split across the full width.

**Left column (~55% width):**
- Live delta in 60pt+ monospaced bold, color-coded:
  - Green when ahead of best lap (negative delta, e.g., `-0.34`)
  - Red/orange when behind (positive delta, e.g., `+0.34`)
  - White with `--` before first completed lap (no reference)
- Below in smaller text: current lap number, current lap elapsed time, lateral-g magnitude

**Right column (~45% width):**
- Speed in 50pt+ monospaced bold, white
- `km/h` label small below
- Stop button as compact red text in top-right corner

Both columns share the `heroGradient` background. The user's eye naturally lands left-of-center on a landscape mount, so delta gets that prime position. Speed is the peripheral anchor on the right.

### Tier 2: Lap Table (~40-55% of screen depending on status bar visibility)

**Best lap pinned at top:**
- Always visible regardless of scroll position
- Subtle accent/gold left border with "BEST" badge right-aligned
- Shows: lap number (left), lap time (center)

**Remaining laps below in reverse chronological order (newest first):**
- Each row: lap number, lap time, delta-to-best (right-aligned, color-coded green/red)
- Compact row height (~44pt) for density
- On a landscape iPhone, 3-4 recent laps visible without scrolling
- Scrollable if more laps exist

**Empty state:** Single muted line: "Waiting for first lap crossing..." No card chrome.

**On new lap completion:**
- New lap appears at top of list with brief opacity fade-in
- If it's a new best: replaces the pinned row with a quick green flash, old best slides into the list

### Tier 3: Conditional Status Bar (~15% when visible)

**Hidden by default.** Appears only in two cases:

1. **Session start:** Visible until the first valid GPS fix arrives (confirming the source is working), or for a maximum of 10 seconds if GPS is already available at launch. Whichever condition is met first triggers the hide animation.
2. **Signal loss:** Slides in when BLE disconnects or GPS accuracy degrades. Shows: connection dot (red) + device name + issue description. Stays visible until the issue resolves.

When hidden, the lap table reclaims the space.

### Stop Button

Small red "Stop" text button in the top-right corner of the hero zone, always accessible. Not a full-width bar — it's compact and out of the way but reachable with one tap. Disabled with "Finalizing..." text during session finalization.

## Live Delta Engine

### Algorithm: Hybrid Distance + GPS Matching

1. **On first completed lap:** Store the best lap's trace as an array of `(cumulativeDistanceMeters: Double, coordinate: GeoPoint, elapsedTimeSeconds: Double)` tuples, one entry per GPS sample received during that lap.

2. **On each incoming sample during the current lap:**
   - Compute cumulative distance from start/finish line (running sum of haversine distances between consecutive samples using existing `GeoPoint.distance(to:)`)
   - **Distance lookup:** Binary search the best lap trace for the entry closest to current cumulative distance. This gives a rough index in O(log n).
   - **GPS refinement:** Within a window of +/-5 samples around that index, find the trace point with minimum haversine distance to the current GPS position.
   - **Interpolate** the best lap's elapsed time at the matched point.
   - **Delta** = current lap elapsed time - interpolated best lap elapsed time

3. **On new best lap:** Replace the stored trace. All future deltas compare against the new reference.

### Edge Cases

- **Before any completed lap:** Delta displays `--` in white. No reference trace exists.
- **GPS drift at low speed:** Clamp delta updates when speed < 5 km/h to avoid jitter on the grid or in the pits.
- **Very short laps (< 10 samples):** Skip trace storage, treat as invalid start/finish crossing. Do not replace best lap reference.
- **Distance divergence:** If cumulative distance differs from best lap by more than 20% at the matched GPS point, fall back to pure GPS nearest-point (the track line may differ significantly, e.g., a spin or off-track excursion).

### Data Structure: LapTrace

```
struct LapTracePoint: Sendable {
    let cumulativeDistanceMeters: Double
    let coordinate: GeoPoint
    let elapsedTimeSeconds: Double
}

struct LapTrace: Sendable {
    let lapIndex: Int
    let durationSeconds: Double
    let points: [LapTracePoint]
}
```

### Data Structure: LapDeltaTracker

Stateful computation object that:
- Accepts the best lap's `LapTrace` as reference
- Receives each sample via an `update(coordinate:cumulativeDistance:elapsedTime:speed:)` method
- Returns `Double?` (the live delta, nil if no reference or clamped)
- Tracks a cursor into the reference trace for efficient sequential lookup
- Resets on lap completion

Purely in-memory. Does not persist. Does not touch storage or network.

## Component Changes

### New Files

| File | Purpose |
|------|---------|
| `Models/LapTrace.swift` | `LapTrace` and `LapTracePoint` structs |
| `Models/LapDeltaTracker.swift` | Hybrid distance+GPS delta computation |

### Modified Files

| File | Change |
|------|--------|
| `ViewModels/DashboardViewModel.swift` | Expose `liveDelta`, `currentLapTime`, `bestLap`, `sortedLaps`, `isStatusBarVisible`. Subscribe to new SessionManager publishers. |
| `Views/DashboardView.swift` | Full rewrite: landscape hero layout with split columns, lap table with pinned best, conditional status bar, compact stop button. |
| `ViewModels/SessionManager.swift` | Own `LapDeltaTracker`. Publish `@Published liveDelta: Double?` and manage best lap trace. Feed samples into tracker alongside existing `SessionStatisticsAccumulator`. |
| `Models/Session.swift` | Extend `SessionStatisticsAccumulator` to build and store `LapTrace` for the current lap and maintain the best lap trace. |

### Unchanged Files

`StorageService`, `UploadCoordinator`, `NetworkService`, `BLEService`, `RaceBoxParser`, `ContentView`, `SessionListView`, `SessionDetailView`, `LoginView`, `NewSessionView`, `TrackEditorView`, `AppViewModel`, `LoginViewModel`.

### Data Flow

```
GPS/BLE sample arrives
  -> SessionManager.enqueueSample()
      -> SessionStatisticsAccumulator.consume()   [existing: lap detection, distance, summary]
      -> LapDeltaTracker.update()                  [new: computes live delta]
      -> @Published liveDelta updated
          -> DashboardViewModel formats delta text + color
              -> DashboardView hero zone re-renders
```

## Orientation

The dashboard should prefer landscape via `supportedInterfaceOrientations` on its hosting controller or via a landscape preference modifier. The layout degrades gracefully to portrait (hero columns stack vertically) but landscape is the designed-for case.

## Testing Considerations

- `LapDeltaTracker` is a pure computation unit: feed it synthetic traces and samples, assert delta values. No mocks needed.
- `LapTrace` construction from sample arrays: verify cumulative distance monotonically increases, points are ordered.
- `DashboardViewModel`: verify formatting (delta sign/color, speed units, lap ordering with pinned best).
- Status bar visibility: verify it hides after timeout and reappears on connection state changes.
