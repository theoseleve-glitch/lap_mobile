import Foundation
import XCTest
@testable import LapCoachMobileApp

final class UploadCoordinatorTests: XCTestCase {
    func testEnqueueUploadsPendingSessionOnce() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageService = try StorageService(rootURL: rootURL)
        let networkService = CoordinatorNetworkService()
        let coordinator = UploadCoordinator(storageService: storageService, networkService: networkService)
        let authSession = makeAuthSession()

        let session = try await makeSession(storageService: storageService, sampleCount: 3)

        await coordinator.enqueue(sessionID: session.id, authSession: authSession)
        await coordinator.enqueue(sessionID: session.id, authSession: authSession)

        try await waitForUploadCompletion(storageService: storageService, sessionID: session.id)

        let stored = try await storageService.session(id: session.id)
        XCTAssertEqual(stored?.uploadState, .uploaded)
        XCTAssertEqual(stored?.remoteSessionID, "remote-1")
        XCTAssertEqual(stored?.lastUploadedChunkIndex, 0)
        XCTAssertEqual(stored?.totalChunkCount, 1)
        XCTAssertEqual(networkService.registerCallCount, 1)
        XCTAssertEqual(networkService.uploadedChunkIndices, [0])
        XCTAssertEqual(networkService.finalizeCallCount, 1)
    }

    func testResumeQueuedUploadsStartsFromNextChunkIndex() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageService = try StorageService(rootURL: rootURL)
        let networkService = CoordinatorNetworkService()
        let coordinator = UploadCoordinator(storageService: storageService, networkService: networkService)
        let authSession = makeAuthSession()

        var session = try await makeSession(storageService: storageService, sampleCount: 300)
        session.remoteSessionID = "remote-resume"
        session.uploadState = .uploadingChunks
        session.totalChunkCount = 2
        session.lastUploadedChunkIndex = 0
        try await storageService.save(session: session)

        await coordinator.resumeQueuedUploads(authSession: authSession)

        try await waitForUploadCompletion(storageService: storageService, sessionID: session.id)

        let stored = try await storageService.session(id: session.id)
        XCTAssertEqual(stored?.uploadState, .uploaded)
        XCTAssertEqual(networkService.registerCallCount, 0)
        XCTAssertEqual(networkService.uploadedChunkIndices, [1])
        XCTAssertEqual(networkService.finalizeCallCount, 1)
    }

    func testNonRetryableFailureMarksSessionFailed() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storageService = try StorageService(rootURL: rootURL)
        let networkService = CoordinatorNetworkService()
        networkService.uploadError = NetworkServiceError.statusCode(400)
        let coordinator = UploadCoordinator(storageService: storageService, networkService: networkService)
        let authSession = makeAuthSession()

        let session = try await makeSession(storageService: storageService, sampleCount: 3)

        await coordinator.enqueue(sessionID: session.id, authSession: authSession)

        try await waitForSession(storageService: storageService, sessionID: session.id) { stored in
            stored?.uploadState == .failed
        }

        let stored = try await storageService.session(id: session.id)
        XCTAssertEqual(stored?.uploadState, .failed)
        XCTAssertNil(stored?.nextRetryAt)
        XCTAssertEqual(stored?.retryCount, 1)
        XCTAssertEqual(networkService.finalizeCallCount, 0)
    }

    private func makeAuthSession() -> AuthSession {
        AuthSession(
            accessToken: "token",
            refreshToken: nil,
            user: AuthenticatedUser(id: "user-1", email: "test@example.com", displayName: nil)
        )
    }

    private func makeSession(storageService: StorageService, sampleCount: Int) async throws -> RecordedSession {
        let artifacts = try await storageService.createSession(mode: .phone, track: nil)

        for offset in 0 ..< sampleCount {
            let sample = SensorSample(
                sessionID: artifacts.session.id,
                timestampMs: Int64(offset * 100),
                source: .phone,
                latDeg: 48.0 + (Double(offset) * 0.0001),
                lonDeg: 2.0 + (Double(offset) * 0.0001),
                speedMps: 20.0,
                headingDeg: 180.0,
                ax: nil,
                ay: nil,
                az: nil,
                gx: nil,
                gy: nil,
                gz: nil,
                horizontalAccuracy: nil
            )
            try await artifacts.writer.append(sample)
        }
        try await artifacts.writer.close()

        var session = artifacts.session
        session.endedAt = session.startedAt.addingTimeInterval(Double(sampleCount) / 10.0)
        session.status = .completed
        session.totalSamples = sampleCount
        session.summary = SessionSummary(
            durationSeconds: Double(sampleCount) / 10.0,
            totalSamples: sampleCount,
            distanceMeters: 100.0,
            maxSpeedMps: 20.0,
            laps: []
        )

        return try await storageService.finalizeSession(session)
    }

    private func waitForUploadCompletion(storageService: StorageService, sessionID: UUID) async throws {
        try await waitForSession(storageService: storageService, sessionID: sessionID) { stored in
            stored?.uploadState == .uploaded
        }
    }

    private func waitForSession(
        storageService: StorageService,
        sessionID: UUID,
        timeout: TimeInterval = 2.0,
        matcher: @escaping (RecordedSession?) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let session = try await storageService.session(id: sessionID)
            if matcher(session) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for session state.")
    }
}

private final class CoordinatorNetworkService: NetworkServiceType {
    let backgroundSessionIdentifier = "com.lapcoach.uploads"
    let defaultChunkSize = 250

    private(set) var registerCallCount = 0
    private(set) var uploadedChunkIndices: [Int] = []
    private(set) var finalizeCallCount = 0

    var uploadError: Error?

    func makeChunkPayloads(from fileURL: URL, chunkSize: Int) throws -> [SessionChunkPayload] {
        try CSVSampleFileReader.makeChunks(from: fileURL, chunkSize: chunkSize)
    }

    func register(session: RecordedSession, authSession: AuthSession) async throws -> String {
        registerCallCount += 1
        return "remote-\(registerCallCount)"
    }

    func upload(chunk: SessionChunkPayload, remoteSessionID: String, authSession: AuthSession) async throws {
        if let uploadError {
            throw uploadError
        }

        uploadedChunkIndices.append(chunk.chunkIndex)
    }

    func finalize(remoteSessionID: String, authSession: AuthSession) async throws {
        finalizeCallCount += 1
    }
}
