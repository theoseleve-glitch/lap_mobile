import Foundation

protocol NetworkServiceType: AnyObject {
    func upload(session: RecordedSession, fileURL: URL, authSession: AuthSession) async throws -> String
}

final class NetworkService: NetworkServiceType {
    private let apiConfiguration: APIConfiguration
    private let session: URLSession
    private let injectedUploadSession: URLSession?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(apiConfiguration: APIConfiguration, session: URLSession? = nil) {
        self.apiConfiguration = apiConfiguration

        if let session {
            self.session = session
            self.injectedUploadSession = session
        } else {
            self.session = URLSession(configuration: .default)
            self.injectedUploadSession = nil
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func upload(session: RecordedSession, fileURL: URL, authSession: AuthSession) async throws -> String {
        let remoteSessionID = try await register(session: session, authSession: authSession)
        let chunkPayloads = try CSVSampleFileReader.makeChunks(from: fileURL, chunkSize: 250)
        let uploadSession = makeUploadSession(for: session.id.uuidString)

        for chunk in chunkPayloads {
            try await upload(chunk: chunk, remoteSessionID: remoteSessionID, authSession: authSession, uploadSession: uploadSession)
        }

        try await finalize(remoteSessionID: remoteSessionID, authSession: authSession)
        return remoteSessionID
    }

    private func register(session: RecordedSession, authSession: AuthSession) async throws -> String {
        let payload = SessionRegistrationPayload(
            sessionID: session.id.uuidString,
            source: session.sourceMode.rawValue,
            startedAt: session.startedAt,
            trackID: session.trackID,
            totalSamples: session.totalSamples
        )

        var request = URLRequest(url: apiConfiguration.endpoint(apiConfiguration.sessionsPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let createResponse = try decoder.decode(SessionCreateResponse.self, from: data)
        return createResponse.sessionID
    }

    private func upload(
        chunk: SessionChunkPayload,
        remoteSessionID: String,
        authSession: AuthSession,
        uploadSession: URLSession
    ) async throws {
        let tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lapcoach-\(remoteSessionID)-\(chunk.chunkIndex).json")
        let body = try encoder.encode(chunk)
        try body.write(to: tempFileURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        var request = URLRequest(url: apiConfiguration.endpoint("\(apiConfiguration.sessionsPath)/\(remoteSessionID)/chunks"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await uploadSession.upload(for: request, fromFile: tempFileURL)
        try validate(response: response)
    }

    private func finalize(remoteSessionID: String, authSession: AuthSession) async throws {
        let payload = SessionFinalizePayload(sessionID: remoteSessionID)

        var request = URLRequest(url: apiConfiguration.endpoint("\(apiConfiguration.sessionsPath)/\(remoteSessionID)/finalize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw NetworkServiceError.invalidResponse
        }

        guard (200 ... 299).contains(response.statusCode) else {
            throw NetworkServiceError.statusCode(response.statusCode)
        }
    }

    private func makeUploadSession(for sessionID: String) -> URLSession {
        if let injectedUploadSession {
            return injectedUploadSession
        }

        let configuration = URLSessionConfiguration.background(withIdentifier: "com.lapcoach.upload.\(sessionID)")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }
}

enum NetworkServiceError: LocalizedError {
    case invalidResponse
    case statusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .statusCode(code):
            return "Upload failed with status code \(code)."
        }
    }
}
