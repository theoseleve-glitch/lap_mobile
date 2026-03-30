import Foundation

struct SessionRegistrationPayload: Codable, Sendable {
    let sessionID: String
    let source: String
    let startedAt: Date
    let trackID: String?
    let totalSamples: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case source
        case startedAt = "started_at"
        case trackID = "track_id"
        case totalSamples = "total_samples"
    }
}

struct SessionChunkPayload: Codable, Hashable, Sendable {
    let sessionID: String
    let chunkIndex: Int
    let chunkSize: Int
    let samples: [SensorSample]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case chunkIndex = "chunk_index"
        case chunkSize = "chunk_size"
        case samples
    }
}

struct SessionFinalizePayload: Codable, Sendable {
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

struct SessionCreateResponse: Codable, Sendable {
    let sessionID: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let value = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("session_id")) {
            sessionID = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("id")) {
            sessionID = value
        } else {
            throw DecodingError.keyNotFound(
                DynamicCodingKey("session_id"),
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing session id.")
            )
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
