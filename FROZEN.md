# lap_mobile (iOS) — FROZEN as of 2026-04-23

## Status: FROZEN. No /loop runs here.

iOS development requires a Mac for `xcodebuild`. No Mac currently available. This repo is **paused, not abandoned**.

## Where did the work go?

Active mobile work pivoted to **`../lap-mobile-android/`** (Kotlin + Compose + Gradle). Builds natively on Windows. All 240 M1 sprint tasks are targeted there.

## When this repo resumes

When a Mac becomes available (self-purchase, borrowed, or cloud CI runner ready):

1. Unfreeze: delete this `FROZEN.md`.
2. Read `../docs/roadmap/sprint-30day/sprint-mobile-ios-future.md` (iOS task queue, preserved for catch-up).
3. Port lessons learned from Android sprint — rules engine integration pattern, upload queue architecture, journal design — Swift equivalent.
4. Target: iOS parity within 4-6 weeks of Mac arrival.

## What to do NOT do

- Do not delete this folder. The existing Swift code (capture pipeline, RaceBox UBX parser, session journal skeleton) has value for iOS resumption.
- Do not run `/loop` pointed at this folder — it will hit `xcodebuild` errors on every task.
- Do not merge changes into `../lap-mobile-android/` — Android has its own architecture.

## Snapshot of work already done

Existing Swift code to preserve:
- `LapCoachMobileApp/Services/LocationService.swift` — CoreLocation integration
- `LapCoachMobileApp/Services/MotionService.swift` — CoreMotion integration  
- `LapCoachMobileApp/BLE/RaceBoxParser.swift` — UBX NAV-PVT parser (partial)
- `LapCoachMobileApp/DataModels/CSVWriter.swift` — CSV writer
- `LapCoachMobileApp/ViewModels/SessionManager.swift` — capture orchestration

These inform the Android port (same domain logic, different platform APIs) but are kept intact for later.
