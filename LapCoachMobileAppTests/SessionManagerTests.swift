import Foundation
import XCTest
@testable import LapCoachMobileApp

@MainActor
final class SessionManagerTests: XCTestCase {
    func testPhoneRecordingPersistsCompletedSession() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageService = try StorageService(rootURL: rootURL)
        let locationService = FakeLocationService()
        let motionService = FakeMotionService()
        let bleService = FakeBLEService()
        let manager = SessionManager(
            storageService: storageService,
            networkService: FakeNetworkService(),
            locationService: locationService,
            motionService: motionService,
            bleService: bleService
        )

        try await manager.startRecording(mode: .phone, track: nil)

        locationService.onLocationUpdate?(
            LocationSnapshot(
                timestampMs: 1_000,
                latitude: 48.0,
                longitude: 2.0,
                speedMps: 12.0,
                headingDeg: 180.0,
                horizontalAccuracy: 1.0
            )
        )
        motionService.onMotionUpdate?(
            MotionSnapshot(
                timestampMs: 1_020,
                ax: 1.0,
                ay: 0.0,
                az: 9.8,
                gx: 0.1,
                gy: 0.2,
                gz: 0.3
            )
        )

        await manager.stopRecording(authSession: nil)

        let sessions = try await storageService.listSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].status, .completed)
        XCTAssertGreaterThan(sessions[0].totalSamples, 0)
        XCTAssertNotNil(sessions[0].summary)
    }
}

private final class FakeLocationService: LocationServiceType {
    var onLocationUpdate: ((LocationSnapshot) -> Void)?
    var onAuthorizationChange: ((GPSAuthorizationState) -> Void)?

    func requestAuthorization() {
        onAuthorizationChange?(.authorizedAlways)
    }

    func start() {}
    func stop() {}
}

private final class FakeMotionService: MotionServiceType {
    var onMotionUpdate: ((MotionSnapshot) -> Void)?
    func start() {}
    func stop() {}
}

private final class FakeBLEService: BLEServiceType {
    var onTelemetry: ((RaceBoxTelemetrySample) -> Void)?
    var onConnectionStateChange: ((BLEConnectionState) -> Void)?
    var onPeripheralNameChange: ((String?) -> Void)?
    func startScanning() {}
    func stop() {}
}

private final class FakeNetworkService: NetworkServiceType {
    func upload(session: RecordedSession, fileURL: URL, authSession: AuthSession) async throws -> String {
        "remote-session"
    }
}
