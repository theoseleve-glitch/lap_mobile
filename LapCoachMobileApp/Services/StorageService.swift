import Foundation
import SQLite3

struct SessionArtifacts: Sendable {
    let session: RecordedSession
    let writer: CSVWriter
    let temporaryFileURL: URL
    let finalFileURL: URL
}

actor StorageService {
    private let fileManager: FileManager
    private let rootURL: URL
    private let sessionsDirectoryURL: URL
    private let store: SQLiteSessionStore

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        let defaultRoot = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LapCoachMobile", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("LapCoachMobile", isDirectory: true)
        let resolvedRoot = rootURL ?? defaultRoot

        self.rootURL = resolvedRoot
        self.sessionsDirectoryURL = resolvedRoot.appendingPathComponent("Sessions", isDirectory: true)
        let databaseURL = resolvedRoot.appendingPathComponent("session-index.sqlite")

        try fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        store = try SQLiteSessionStore(databaseURL: databaseURL)
    }

    func createSession(mode: SessionSourceMode, track: Track?) throws -> SessionArtifacts {
        let sessionID = UUID()
        let finalURL = fileURL(for: sessionID)
        let temporaryURL = temporaryFileURL(for: sessionID)
        let session = RecordedSession(
            id: sessionID,
            startedAt: Date(),
            endedAt: nil,
            status: .recording,
            uploadState: .pending,
            sourceMode: mode,
            trackID: track?.id,
            totalSamples: 0,
            localFilePath: finalURL.path,
            remoteSessionID: nil,
            totalChunkCount: 0,
            lastUploadedChunkIndex: -1,
            retryCount: 0,
            lastUploadAttemptAt: nil,
            nextRetryAt: nil,
            lastError: nil,
            summary: nil
        )

        try store.upsert(session)
        let writer = try CSVWriter(fileURL: temporaryURL)
        return SessionArtifacts(session: session, writer: writer, temporaryFileURL: temporaryURL, finalFileURL: finalURL)
    }

    func finalizeSession(_ session: RecordedSession) throws -> RecordedSession {
        let temporaryURL = temporaryFileURL(for: session.id)
        let finalURL = URL(fileURLWithPath: session.localFilePath)

        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        }

        try store.upsert(session)
        return session
    }

    func save(session: RecordedSession) throws {
        try store.upsert(session)
    }

    func listSessions() throws -> [RecordedSession] {
        try store.fetchSessions()
    }

    func session(id: UUID) throws -> RecordedSession? {
        try store.fetchSession(id: id)
    }

    func sessionsReadyForUpload(at date: Date) throws -> [RecordedSession] {
        try store.fetchSessionsReadyForUpload(at: date)
    }

    func fileURL(for session: RecordedSession) -> URL {
        URL(fileURLWithPath: session.localFilePath)
    }

    func fileURL(for sessionID: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(sessionID.uuidString).csv")
    }

    private func temporaryFileURL(for sessionID: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent("\(sessionID.uuidString).tmp.csv")
    }
}

private final class SQLiteSessionStore {
    private let database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL) throws {
        var db: OpaquePointer?
        let result = sqlite3_open(databaseURL.path, &db)
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.open(result)
        }

        database = db
        try execute(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                start_time REAL NOT NULL,
                end_time REAL,
                status TEXT NOT NULL,
                upload_state TEXT NOT NULL,
                source_mode TEXT NOT NULL,
                track_id TEXT,
                total_samples INTEGER NOT NULL,
                local_filepath TEXT NOT NULL,
                remote_session_id TEXT,
                total_chunk_count INTEGER NOT NULL DEFAULT 0,
                last_uploaded_chunk_index INTEGER NOT NULL DEFAULT -1,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_upload_attempt_at REAL,
                next_retry_at REAL,
                last_error TEXT,
                summary_json TEXT
            );
            """
        )
        try migrateIfNeeded()
    }

    deinit {
        sqlite3_close(database)
    }

    func upsert(_ session: RecordedSession) throws {
        let sql =
            """
            INSERT INTO sessions (
                id, start_time, end_time, status, upload_state, source_mode,
                track_id, total_samples, local_filepath, remote_session_id, total_chunk_count,
                last_uploaded_chunk_index, retry_count, last_upload_attempt_at, next_retry_at, last_error, summary_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                start_time = excluded.start_time,
                end_time = excluded.end_time,
                status = excluded.status,
                upload_state = excluded.upload_state,
                source_mode = excluded.source_mode,
                track_id = excluded.track_id,
                total_samples = excluded.total_samples,
                local_filepath = excluded.local_filepath,
                remote_session_id = excluded.remote_session_id,
                total_chunk_count = excluded.total_chunk_count,
                last_uploaded_chunk_index = excluded.last_uploaded_chunk_index,
                retry_count = excluded.retry_count,
                last_upload_attempt_at = excluded.last_upload_attempt_at,
                next_retry_at = excluded.next_retry_at,
                last_error = excluded.last_error,
                summary_json = excluded.summary_json;
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(session.id.uuidString, to: 1, in: statement)
        sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
        if let endedAt = session.endedAt {
            sqlite3_bind_double(statement, 3, endedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        try bind(session.status.rawValue, to: 4, in: statement)
        try bind(session.uploadState.rawValue, to: 5, in: statement)
        try bind(session.sourceMode.rawValue, to: 6, in: statement)
        try bind(session.trackID, to: 7, in: statement)
        sqlite3_bind_int64(statement, 8, sqlite3_int64(session.totalSamples))
        try bind(session.localFilePath, to: 9, in: statement)
        try bind(session.remoteSessionID, to: 10, in: statement)
        sqlite3_bind_int64(statement, 11, sqlite3_int64(session.totalChunkCount))
        sqlite3_bind_int64(statement, 12, sqlite3_int64(session.lastUploadedChunkIndex))
        sqlite3_bind_int64(statement, 13, sqlite3_int64(session.retryCount))
        if let lastUploadAttemptAt = session.lastUploadAttemptAt {
            sqlite3_bind_double(statement, 14, lastUploadAttemptAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 14)
        }
        if let nextRetryAt = session.nextRetryAt {
            sqlite3_bind_double(statement, 15, nextRetryAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 15)
        }
        try bind(session.lastError, to: 16, in: statement)

        if let summary = session.summary {
            let data = try encoder.encode(summary)
            try bind(String(decoding: data, as: UTF8.self), to: 17, in: statement)
        } else {
            sqlite3_bind_null(statement, 17)
        }

        try step(statement)
    }

    func fetchSessions() throws -> [RecordedSession] {
        let statement = try prepare(
            """
            SELECT id, start_time, end_time, status, upload_state, source_mode,
                   track_id, total_samples, local_filepath, remote_session_id, total_chunk_count,
                   last_uploaded_chunk_index, retry_count, last_upload_attempt_at, next_retry_at, last_error, summary_json
            FROM sessions
            ORDER BY start_time DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        var sessions: [RecordedSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            sessions.append(try decodeSession(from: statement))
        }

        return sessions
    }

    func fetchSession(id: UUID) throws -> RecordedSession? {
        let statement = try prepare(
            """
            SELECT id, start_time, end_time, status, upload_state, source_mode,
                   track_id, total_samples, local_filepath, remote_session_id, total_chunk_count,
                   last_uploaded_chunk_index, retry_count, last_upload_attempt_at, next_retry_at, last_error, summary_json
            FROM sessions
            WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(id.uuidString, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodeSession(from: statement)
    }

    func fetchSessionsReadyForUpload(at date: Date) throws -> [RecordedSession] {
        let statement = try prepare(
            """
            SELECT id, start_time, end_time, status, upload_state, source_mode,
                   track_id, total_samples, local_filepath, remote_session_id, total_chunk_count,
                   last_uploaded_chunk_index, retry_count, last_upload_attempt_at, next_retry_at, last_error, summary_json
            FROM sessions
            WHERE upload_state IN ('pending', 'registering', 'uploading_chunks', 'finalizing')
              AND (next_retry_at IS NULL OR next_retry_at <= ?)
            ORDER BY start_time ASC;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)

        var sessions: [RecordedSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            sessions.append(try decodeSession(from: statement))
        }
        return sessions
    }

    private func decodeSession(from statement: OpaquePointer?) throws -> RecordedSession {
        let id = UUID(uuidString: string(statement, index: 0)) ?? UUID()
        let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let endedAt = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let status = RecordedSessionStatus(rawValue: string(statement, index: 3)) ?? .completed
        let uploadState = SessionUploadState(storageValue: string(statement, index: 4))
        let sourceMode = SessionSourceMode(rawValue: string(statement, index: 5)) ?? .phone
        let trackID = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : string(statement, index: 6)
        let totalSamples = Int(sqlite3_column_int64(statement, 7))
        let localFilePath = string(statement, index: 8)
        let remoteSessionID = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : string(statement, index: 9)
        let totalChunkCount = Int(sqlite3_column_int64(statement, 10))
        let lastUploadedChunkIndex = Int(sqlite3_column_int64(statement, 11))
        let retryCount = Int(sqlite3_column_int64(statement, 12))
        let lastUploadAttemptAt = sqlite3_column_type(statement, 13) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 13))
        let nextRetryAt = sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 14))
        let lastError = sqlite3_column_type(statement, 15) == SQLITE_NULL ? nil : string(statement, index: 15)
        let summaryJSON = sqlite3_column_type(statement, 16) == SQLITE_NULL ? nil : string(statement, index: 16)
        let summary = try summaryJSON.map {
            try decoder.decode(SessionSummary.self, from: Data($0.utf8))
        }

        return RecordedSession(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            uploadState: uploadState,
            sourceMode: sourceMode,
            trackID: trackID,
            totalSamples: totalSamples,
            localFilePath: localFilePath,
            remoteSessionID: remoteSessionID,
            totalChunkCount: totalChunkCount,
            lastUploadedChunkIndex: lastUploadedChunkIndex,
            retryCount: retryCount,
            lastUploadAttemptAt: lastUploadAttemptAt,
            nextRetryAt: nextRetryAt,
            lastError: lastError,
            summary: summary
        )
    }

    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.execute(result)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.prepare(result)
        }
        return statement
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer?) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
        guard result == SQLITE_OK else {
            throw SQLiteStoreError.bind(result)
        }
    }

    private func step(_ statement: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw SQLiteStoreError.step(result)
        }
    }

    private func string(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func migrateIfNeeded() throws {
        let existingColumns = try tableColumns()
        if existingColumns.contains("total_chunk_count") == false {
            try execute("ALTER TABLE sessions ADD COLUMN total_chunk_count INTEGER NOT NULL DEFAULT 0;")
        }
        if existingColumns.contains("last_uploaded_chunk_index") == false {
            try execute("ALTER TABLE sessions ADD COLUMN last_uploaded_chunk_index INTEGER NOT NULL DEFAULT -1;")
        }
        if existingColumns.contains("retry_count") == false {
            try execute("ALTER TABLE sessions ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;")
        }
        if existingColumns.contains("last_upload_attempt_at") == false {
            try execute("ALTER TABLE sessions ADD COLUMN last_upload_attempt_at REAL;")
        }
        if existingColumns.contains("next_retry_at") == false {
            try execute("ALTER TABLE sessions ADD COLUMN next_retry_at REAL;")
        }
    }

    private func tableColumns() throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(sessions);")
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(string(statement, index: 1))
        }
        return columns
    }
}

private enum SQLiteStoreError: Error {
    case open(Int32)
    case execute(Int32)
    case prepare(Int32)
    case bind(Int32)
    case step(Int32)
}
