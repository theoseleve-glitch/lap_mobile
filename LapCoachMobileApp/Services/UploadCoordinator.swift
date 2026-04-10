import Foundation

@MainActor
protocol UploadCoordinatorObserver: AnyObject {
    func uploadCoordinatorDidChangeSessions() async
    func uploadCoordinatorDidSurfaceError(_ message: String) async
}

actor UploadCoordinator {
    private let maxConcurrentUploads = 2
    private let retryScheduleSeconds: [TimeInterval] = [15, 60, 300, 900, 3_600]

    private let storageService: StorageService
    private let networkService: NetworkServiceType

    private weak var observer: (any UploadCoordinatorObserver)?

    private var queuedSessionIDs: [UUID] = []
    private var activeSessionIDs = Set<UUID>()
    private var currentAuthSession: AuthSession?
    private var backgroundCompletionHandlers: [String: [() -> Void]] = [:]

    init(storageService: StorageService, networkService: NetworkServiceType) {
        self.storageService = storageService
        self.networkService = networkService
    }

    func setObserver(_ observer: (any UploadCoordinatorObserver)?) {
        self.observer = observer
    }

    func updateAuthenticationSession(_ authSession: AuthSession?) {
        currentAuthSession = authSession
    }

    func enqueue(sessionID: UUID, authSession: AuthSession?) async {
        currentAuthSession = authSession

        guard authSession != nil else {
            return
        }

        do {
            guard var session = try await storageService.session(id: sessionID) else {
                return
            }
            guard session.uploadState != .uploaded else {
                return
            }

            session = normalizeForEnqueue(session)
            try await storageService.save(session: session)
            await notifySessionsChanged()
            appendToQueueIfNeeded(sessionID)
            await pumpQueue()
        } catch {
            await notifyObserverError(error.localizedDescription)
        }
    }

    func resumeQueuedUploads(authSession: AuthSession?) async {
        currentAuthSession = authSession

        guard authSession != nil else {
            return
        }

        do {
            let readySessions = try await storageService.sessionsReadyForUpload(at: Date())
            for session in readySessions where session.uploadState != .uploaded {
                appendToQueueIfNeeded(session.id)
            }
            await pumpQueue()
        } catch {
            await notifyObserverError(error.localizedDescription)
        }
    }

    func handleBackgroundSessionEvents(identifier: String, completionHandler: @escaping () -> Void) async {
        guard identifier == networkService.backgroundSessionIdentifier else {
            completionHandler()
            return
        }

        backgroundCompletionHandlers[identifier, default: []].append(completionHandler)
        await flushBackgroundCompletionHandlersIfIdle()
    }

    private func pumpQueue() async {
        guard currentAuthSession != nil else {
            return
        }

        while activeSessionIDs.count < maxConcurrentUploads, queuedSessionIDs.isEmpty == false {
            let sessionID = queuedSessionIDs.removeFirst()
            guard activeSessionIDs.insert(sessionID).inserted else {
                continue
            }

            Task {
                await self.processUpload(sessionID: sessionID)
            }
        }

        await flushBackgroundCompletionHandlersIfIdle()
    }

    private func processUpload(sessionID: UUID) async {
        defer {
            activeSessionIDs.remove(sessionID)
            Task {
                await self.pumpQueue()
            }
        }

        guard let authSession = currentAuthSession else {
            return
        }

        do {
            guard var session = try await storageService.session(id: sessionID) else {
                return
            }
            guard session.uploadState != .uploaded else {
                return
            }

            let fileURL = await storageService.fileURL(for: session)
            let chunks = try networkService.makeChunkPayloads(from: fileURL, chunkSize: networkService.defaultChunkSize)

            if session.totalChunkCount != chunks.count {
                session.totalChunkCount = chunks.count
                if session.lastUploadedChunkIndex >= chunks.count {
                    session.lastUploadedChunkIndex = max(-1, chunks.count - 1)
                }
                try await storageService.save(session: session)
                await notifySessionsChanged()
            }

            if session.remoteSessionID == nil {
                session.uploadState = .registering
                session.lastUploadAttemptAt = Date()
                session.nextRetryAt = nil
                session.lastError = nil
                try await storageService.save(session: session)
                await notifySessionsChanged()

                let remoteSessionID = try await networkService.register(session: session, authSession: authSession)
                session.remoteSessionID = remoteSessionID
                session.uploadState = .uploadingChunks
                try await storageService.save(session: session)
                await notifySessionsChanged()
            } else {
                session.uploadState = .uploadingChunks
                session.lastUploadAttemptAt = Date()
                session.nextRetryAt = nil
                session.lastError = nil
                try await storageService.save(session: session)
                await notifySessionsChanged()
            }

            if let remoteSessionID = session.remoteSessionID {
                let startIndex = max(0, session.lastUploadedChunkIndex + 1)
                if startIndex < chunks.count {
                    for index in startIndex ..< chunks.count {
                        try await networkService.upload(chunk: chunks[index], remoteSessionID: remoteSessionID, authSession: authSession)
                        session.lastUploadedChunkIndex = index
                        session.uploadState = .uploadingChunks
                        session.lastUploadAttemptAt = Date()
                        session.nextRetryAt = nil
                        session.lastError = nil
                        try await storageService.save(session: session)
                        await notifySessionsChanged()
                    }
                }

                session.uploadState = .finalizing
                session.lastUploadAttemptAt = Date()
                try await storageService.save(session: session)
                await notifySessionsChanged()

                try await networkService.finalize(remoteSessionID: remoteSessionID, authSession: authSession)
                session.uploadState = .uploaded
                session.retryCount = 0
                session.nextRetryAt = nil
                session.lastError = nil
                try await storageService.save(session: session)
                await notifySessionsChanged()
            }
        } catch {
            await handleUploadFailure(for: sessionID, error: error)
        }
    }

    private func handleUploadFailure(for sessionID: UUID, error: Error) async {
        do {
            guard var session = try await storageService.session(id: sessionID) else {
                return
            }

            session.lastUploadAttemptAt = Date()
            session.lastError = error.localizedDescription

            if shouldRetry(error), session.retryCount < retryScheduleSeconds.count {
                let retryDelay = retryScheduleSeconds[session.retryCount]
                session.retryCount += 1
                session.nextRetryAt = Date().addingTimeInterval(retryDelay)
                try await storageService.save(session: session)
                await notifySessionsChanged()
                scheduleRetryIfPossible(after: retryDelay)
            } else {
                session.uploadState = .failed
                session.retryCount = min(session.retryCount + 1, retryScheduleSeconds.count)
                session.nextRetryAt = nil
                try await storageService.save(session: session)
                await notifySessionsChanged()
                await notifyObserverError(error.localizedDescription)
            }
        } catch {
            await notifyObserverError(error.localizedDescription)
        }
    }

    private func scheduleRetryIfPossible(after delay: TimeInterval) {
        guard let authSession = currentAuthSession else {
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self.resumeQueuedUploads(authSession: authSession)
        }
    }

    private func normalizeForEnqueue(_ session: RecordedSession) -> RecordedSession {
        var normalized = session
        normalized.lastError = nil
        normalized.nextRetryAt = nil

        if normalized.remoteSessionID == nil {
            normalized.uploadState = .pending
        } else if normalized.totalChunkCount > 0 && normalized.lastUploadedChunkIndex >= normalized.totalChunkCount - 1 {
            normalized.uploadState = .finalizing
        } else {
            normalized.uploadState = .uploadingChunks
        }

        return normalized
    }

    private func appendToQueueIfNeeded(_ sessionID: UUID) {
        guard activeSessionIDs.contains(sessionID) == false else {
            return
        }
        guard queuedSessionIDs.contains(sessionID) == false else {
            return
        }
        queuedSessionIDs.append(sessionID)
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let networkError = error as? NetworkServiceError {
            return networkError.isRetryable
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return false
            default:
                return true
            }
        }

        return true
    }

    private func notifySessionsChanged() async {
        await observer?.uploadCoordinatorDidChangeSessions()
    }

    private func notifyObserverError(_ message: String) async {
        await observer?.uploadCoordinatorDidSurfaceError(message)
    }

    private func flushBackgroundCompletionHandlersIfIdle() async {
        guard activeSessionIDs.isEmpty, queuedSessionIDs.isEmpty else {
            return
        }

        let handlers = backgroundCompletionHandlers.removeValue(forKey: networkService.backgroundSessionIdentifier) ?? []
        for handler in handlers {
            handler()
        }
    }
}
