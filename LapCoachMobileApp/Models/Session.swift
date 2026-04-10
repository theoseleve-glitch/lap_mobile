import Foundation

enum SessionSourceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case phone
    case racebox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone:
            return "Phone"
        case .racebox:
            return "RaceBox"
        }
    }
}

enum RecordedSessionStatus: String, Codable, Sendable {
    case recording
    case completed
    case failed
}

enum SessionUploadState: String, Codable, Sendable {
    case pending
    case registering = "registering"
    case uploadingChunks = "uploading_chunks"
    case finalizing
    case uploaded
    case failed

    var label: String {
        switch self {
        case .pending:
            return "Pending"
        case .registering:
            return "Registering"
        case .uploadingChunks:
            return "Uploading"
        case .finalizing:
            return "Finalizing"
        case .uploaded:
            return "Uploaded"
        case .failed:
            return "Failed"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .uploaded, .failed:
            return true
        case .pending, .registering, .uploadingChunks, .finalizing:
            return false
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case SessionUploadState.pending.rawValue:
            self = .pending
        case SessionUploadState.registering.rawValue:
            self = .registering
        case SessionUploadState.uploadingChunks.rawValue, "uploading":
            self = .uploadingChunks
        case SessionUploadState.finalizing.rawValue:
            self = .finalizing
        case SessionUploadState.uploaded.rawValue:
            self = .uploaded
        case SessionUploadState.failed.rawValue:
            self = .failed
        default:
            self = .pending
        }
    }
}

enum SessionLifecycleState: String, Sendable {
    case idle
    case recording
    case finalizing
    case completed
    case failed
}

enum GPSAuthorizationState: String, Sendable {
    case unknown
    case authorizedWhenInUse
    case authorizedAlways
    case denied
    case restricted
}

enum BLEConnectionState: String, Sendable {
    case idle
    case poweredOff
    case scanning
    case connecting
    case connected
    case disconnected
    case failed
}

struct LapRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let index: Int
    let durationSeconds: Double
    let deltaToBestSeconds: Double?

    init(index: Int, durationSeconds: Double, deltaToBestSeconds: Double?) {
        self.id = UUID()
        self.index = index
        self.durationSeconds = durationSeconds
        self.deltaToBestSeconds = deltaToBestSeconds
    }
}

struct SessionSummary: Codable, Hashable, Sendable {
    let durationSeconds: Double
    let totalSamples: Int
    let distanceMeters: Double
    let maxSpeedMps: Double
    let laps: [LapRecord]

    var bestLap: LapRecord? {
        laps.min(by: { $0.durationSeconds < $1.durationSeconds })
    }
}

struct RecordedSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var status: RecordedSessionStatus
    var uploadState: SessionUploadState
    var sourceMode: SessionSourceMode
    var trackID: String?
    var totalSamples: Int
    var localFilePath: String
    var remoteSessionID: String?
    var totalChunkCount: Int
    var lastUploadedChunkIndex: Int
    var retryCount: Int
    var lastUploadAttemptAt: Date?
    var nextRetryAt: Date?
    var lastError: String?
    var summary: SessionSummary?

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

extension RecordedSession {
    var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }

    var isReadyForRetry: Bool {
        guard uploadState != .uploaded else { return false }
        guard let nextRetryAt else { return true }
        return nextRetryAt <= Date()
    }
}
