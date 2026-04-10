import Foundation
import XCTest
@testable import LapCoachMobileApp

final class NetworkServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testRegisterChunkAndFinalizeRequests() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.seenPaths.append(request.url?.path ?? "")

            let path = request.url?.path ?? ""
            if path == "/mobile/sessions" {
                let data = #"{"session_id":"remote-123"}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, data)
            }

            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let service = NetworkService(
            apiConfiguration: APIConfiguration(baseURL: URL(string: "https://example.com")!),
            session: session
        )

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent("session.csv")
        let writer = try CSVWriter(fileURL: fileURL)
        let sample = SensorSample(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestampMs: 1_700,
            source: .phone,
            latDeg: 1.0,
            lonDeg: 2.0,
            speedMps: 3.0,
            headingDeg: 4.0,
            ax: nil,
            ay: nil,
            az: nil,
            gx: nil,
            gy: nil,
            gz: nil,
            horizontalAccuracy: nil
        )
        try await writer.append(sample)
        try await writer.close()

        let recordedSession = RecordedSession(
            id: sample.sessionID,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            status: .completed,
            uploadState: .pending,
            sourceMode: .phone,
            trackID: nil,
            totalSamples: 1,
            localFilePath: fileURL.path,
            remoteSessionID: nil,
            totalChunkCount: 0,
            lastUploadedChunkIndex: -1,
            retryCount: 0,
            lastUploadAttemptAt: nil,
            nextRetryAt: nil,
            lastError: nil,
            summary: nil
        )

        let authSession = AuthSession(
            accessToken: "token",
            refreshToken: nil,
            user: AuthenticatedUser(id: "user-1", email: "test@example.com", displayName: nil)
        )

        let remoteID = try await service.register(session: recordedSession, authSession: authSession)
        let chunks = try service.makeChunkPayloads(from: fileURL, chunkSize: service.defaultChunkSize)
        XCTAssertEqual(chunks.count, 1)
        try await service.upload(chunk: chunks[0], remoteSessionID: remoteID, authSession: authSession)
        try await service.finalize(remoteSessionID: remoteID, authSession: authSession)

        XCTAssertEqual(remoteID, "remote-123")
        XCTAssertEqual(MockURLProtocol.seenPaths, [
            "/mobile/sessions",
            "/mobile/sessions/remote-123/chunks",
            "/mobile/sessions/remote-123/finalize"
        ])
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var seenPaths: [String] = []

    static func reset() {
        requestHandler = nil
        seenPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
