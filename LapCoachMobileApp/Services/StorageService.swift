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
    private let sessionsDirectoryURL: URL
    private let store: SQLiteSessionStore

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        let resolvedRoot = rootURL ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("LapCoachMobile", isDirectory: true)

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
                last_error TEXT,
                summary_json TEXT
            );
            """
        )
    }

    deinit {
        sqlite3_close(database)
    }

    func upsert(_ session: RecordedSession) throws {
        let sql =
            """
            INSERT INTO sessions (
                id, start_time, end_time, status, upload_state, source_mode,
                track_id, total_samples, local_filepath, remote_session_id, last_error, summary_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        try bind(session.lastError, to: 11, in: statement)

        if let summary = session.summary {
            let data = try encoder.encode(summary)
            try bind(String(decoding: data, as: UTF8.self), to: 12, in: statement)
        } else {
            sqlite3_bind_null(statement, 12)
        }

        try step(statement)
    }

    func fetchSessions() throws -> [RecordedSession] {
        let statement = try prepare(
            """
            SELECT id, start_time, end_time, status, upload_state, source_mode,
                   track_id, total_samples, local_filepath, remote_session_id, last_error, summary_json
            FROM sessions
            ORDER BY start_time DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        var sessions: [RecordedSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = UUID(uuidString: string(statement, index: 0)) ?? UUID()
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let endedAt = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let status = RecordedSessionStatus(rawValue: string(statement, index: 3)) ?? .completed
            let uploadState = SessionUploadState(rawValue: string(statement, index: 4)) ?? .pending
            let sourceMode = SessionSourceMode(rawValue: string(statement, index: 5)) ?? .phone
            let trackID = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : string(statement, index: 6)
            let totalSamples = Int(sqlite3_column_int64(statement, 7))
            let localFilePath = string(statement, index: 8)
            let remoteSessionID = sqlite3_column_type(statement, 9) == SQLITE_NULL ? nil : string(statement, index: 9)
            let lastError = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : string(statement, index: 10)
            let summaryJSON = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : string(statement, index: 11)
            let summary = try summaryJSON.map {
                try decoder.decode(SessionSummary.self, from: Data($0.utf8))
            }

            sessions.append(
                RecordedSession(
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
                    lastError: lastError,
                    summary: summary
                )
            )
        }

        return sessions
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
}

private enum SQLiteStoreError: Error {
    case open(Int32)
    case execute(Int32)
    case prepare(Int32)
    case bind(Int32)
    case step(Int32)
}
