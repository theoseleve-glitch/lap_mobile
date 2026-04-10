import Foundation

protocol NetworkServiceType: AnyObject {
    var backgroundSessionIdentifier: String { get }
    var defaultChunkSize: Int { get }
    func makeChunkPayloads(from fileURL: URL, chunkSize: Int) throws -> [SessionChunkPayload]
    func register(session: RecordedSession, authSession: AuthSession) async throws -> String
    func upload(chunk: SessionChunkPayload, remoteSessionID: String, authSession: AuthSession) async throws
    func finalize(remoteSessionID: String, authSession: AuthSession) async throws
}

final class NetworkService: NetworkServiceType {
    let backgroundSessionIdentifier = "com.lapcoach.uploads"
    let defaultChunkSize = 250

    private let apiConfiguration: APIConfiguration?
    private let session: URLSession
    private let uploadSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(apiConfiguration: APIConfiguration?, session: URLSession? = nil) {
        self.apiConfiguration = apiConfiguration

        if let session {
            self.session = session
            self.uploadSession = session
        } else {
            self.session = URLSession(configuration: .default)

            let configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 300
            self.uploadSession = URLSession(configuration: configuration)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func makeChunkPayloads(from fileURL: URL, chunkSize: Int) throws -> [SessionChunkPayload] {
        try CSVSampleFileReader.makeChunks(from: fileURL, chunkSize: chunkSize)
    }

    func register(session: RecordedSession, authSession: AuthSession) async throws -> String {
        let payload = SessionRegistrationPayload(
            sessionID: session.id.uuidString,
            source: session.sourceMode.rawValue,
            startedAt: session.startedAt,
            trackID: session.trackID,
            totalSamples: session.totalSamples
        )

        var request = URLRequest(url: try endpoint(for: requiredConfiguration().sessionsPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let createResponse = try decoder.decode(SessionCreateResponse.self, from: data)
        return createResponse.sessionID
    }

    func upload(chunk: SessionChunkPayload, remoteSessionID: String, authSession: AuthSession) async throws {
        let tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapcoach-\(remoteSessionID)-\(chunk.chunkIndex).json")
        let body = try encoder.encode(chunk)
        try body.write(to: tempFileURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        var request = URLRequest(url: try endpoint(for: "\(requiredConfiguration().sessionsPath)/\(remoteSessionID)/chunks"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await uploadSession.upload(for: request, fromFile: tempFileURL)
        try validate(response: response)
    }

    func finalize(remoteSessionID: String, authSession: AuthSession) async throws {
        let payload = SessionFinalizePayload(sessionID: remoteSessionID)

        var request = URLRequest(url: try endpoint(for: "\(requiredConfiguration().sessionsPath)/\(remoteSessionID)/finalize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func requiredConfiguration() throws -> APIConfiguration {
        guard let apiConfiguration else {
            throw NetworkServiceError.syncUnavailable
        }
        return apiConfiguration
    }

    private func endpoint(for path: String) throws -> URL {
        try requiredConfiguration().endpoint(path)
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }

        guard (200 ... 299).contains(response.statusCode) else {
            throw NetworkServiceError.statusCode(response.statusCode)
        }
    }
}

enum NetworkServiceError: LocalizedError, Equatable {
    case syncUnavailable
    case invalidResponse
    case statusCode(Int)

    var isRetryable: Bool {
        switch self {
        case .syncUnavailable:
            return false
        case .invalidResponse:
            return true
        case let .statusCode(code):
            if code == 408 || code == 429 {
                return true
            }
            return (500 ... 599).contains(code)
        }
    }

    var errorDescription: String? {
        switch self {
        case .syncUnavailable:
            return "Sync is unavailable because the API base URL is missing or invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .statusCode(code):
            return "Upload failed with status code \(code)."
        }
    }
}
