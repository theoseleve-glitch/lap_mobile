# Lap Coach Mobile

Native SwiftUI iPhone app scaffold for recording telemetry from iPhone sensors and a RaceBox BLE device, storing sessions locally as CSV, and uploading them to a Flask backend in resumable chunks.

## What Is Included

- SwiftUI app shell with login, session list, new session, dashboard, detail, and basic track editor screens.
- Core services for CoreLocation, CoreMotion, CoreBluetooth, local CSV persistence, SQLite session metadata, and chunked uploads.
- RaceBox UBX frame buffering with `NAV-PVT` decoding and fragmentation handling.
- Unit tests for CSV writing, chunk uploads, lap timing, and RaceBox parsing.
- XcodeGen project spec plus a GitHub Actions workflow scaffold.

## Project Layout

```text
LapCoachMobileApp/
  App/
  BLE/
  DataModels/
  Models/
  Services/
  ViewModels/
  Views/
LapCoachMobileAppTests/
Config/
project.yml
```

## Setup

1. Install Xcode 26 or newer on macOS.
2. Install XcodeGen.
3. Generate the project:

```bash
xcodegen generate
```

4. Open `LapCoachMobileApp.xcodeproj`.
5. Set `LAPCOACH_API_BASE_URL` in your scheme environment or replace the placeholder in `AppViewModel.swift`.
6. Run the `LapCoachMobileApp` scheme on an iPhone or iOS simulator.

## Notes

- This repository was scaffolded from Windows, so the source is ready but final iOS compilation, signing, and device validation still need to happen on a Mac with Xcode.
- The RaceBox parser currently handles UBX framing plus `NAV-PVT` extraction. Once you have live device captures, extend `RaceBoxParser.swift` with the exact IMU message classes your hardware emits.
- Session metadata uses `SQLite3` directly to avoid an external dependency.
