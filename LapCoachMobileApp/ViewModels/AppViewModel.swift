import Foundation
import SwiftUI

enum LapCoachAppModelError: LocalizedError {
    case syncUnavailable

    var errorDescription: String? {
        switch self {
        case .syncUnavailable:
            return "Sync is unavailable right now. You can still record locally."
        }
    }
}

@MainActor
final class LapCoachAppModel: ObservableObject {
    @Published private(set) var authSession: AuthSession?
    @Published private(set) var sessions: [RecordedSession] = []
    @Published var availableTracks: [Track]
    @Published var isBootstrapping = true
    @Published var globalErrorMessage: String?
    @Published var syncNotice: String?
    @Published var isLoginPresented = false

    let sessionManager: SessionManager

    private let authService: AuthService?
    private let storageService: StorageService
    private let trackStore: TrackStore
    private let uploadCoordinator: UploadCoordinator
    private let isSyncConfigured: Bool
    private var isStoppingActiveSession = false
    private var didBootstrap = false

    var isSyncAvailable: Bool {
        isSyncConfigured
    }

    static func live() -> LapCoachAppModel {
        let resolvedBaseURL = ProcessInfo.processInfo.environment["LAPCOACH_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiConfiguration: APIConfiguration?
        let syncNotice: String?

        if let resolvedBaseURL, resolvedBaseURL.isEmpty == false, let url = URL(string: resolvedBaseURL), url.scheme != nil {
            apiConfiguration = APIConfiguration(baseURL: url)
            syncNotice = nil
        } else {
            apiConfiguration = nil
            syncNotice = "Sync is unavailable until a valid LAPCOACH_API_BASE_URL is configured. Local recording still works."
        }

        let storageResult = makeStorageService()
        let model = LapCoachAppModel(
            apiConfiguration: apiConfiguration,
            storageService: storageResult.storageService,
            storageNotice: storageResult.notice,
            syncNotice: syncNotice,
            session: nil
        )
        return model
    }

    init(
        apiConfiguration: APIConfiguration?,
        storageService: StorageService,
        storageNotice: String? = nil,
        syncNotice: String? = nil,
        session: URLSession? = nil
    ) {
        self.storageService = storageService
        self.trackStore = TrackStore()
        self.authService = apiConfiguration.map { AuthService(apiConfiguration: $0, session: session ?? .shared) }
        let networkService = NetworkService(apiConfiguration: apiConfiguration, session: session)
        self.uploadCoordinator = UploadCoordinator(storageService: storageService, networkService: networkService)
        self.sessionManager = SessionManager(
            storageService: storageService,
            locationService: LocationService(),
            motionService: MotionService(),
            bleService: BLEService()
        )
        self.availableTracks = Track.defaultLibrary
        self.isSyncConfigured = apiConfiguration != nil
        self.syncNotice = [storageNotice, syncNotice].compactMap { $0 }.joined(separator: "\n")
        if self.syncNotice?.isEmpty == true {
            self.syncNotice = nil
        }

        sessionManager.onSessionPersisted = { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSessions()
            }
        }

    }

    func bootstrap() async {
        guard didBootstrap == false else { return }
        didBootstrap = true
        await uploadCoordinator.setObserver(self)
        authSession = authService?.restoreSession()
        await uploadCoordinator.updateAuthenticationSession(authSession)
        await refreshSessions()
        await loadTracks()

        if let authSession, isSyncAvailable {
            await uploadCoordinator.resumeQueuedUploads(authSession: authSession)
            await refreshSessions()
        }

        isBootstrapping = false
    }

    func signIn(email: String, password: String) async throws {
        guard let authService else {
            throw LapCoachAppModelError.syncUnavailable
        }

        let restoredSession = try await authService.signIn(email: email, password: password)
        authSession = restoredSession
        isLoginPresented = false
        await uploadCoordinator.updateAuthenticationSession(restoredSession)
        await uploadCoordinator.resumeQueuedUploads(authSession: restoredSession)
        await refreshSessions()
    }

    func signOut() {
        authService?.signOut()
        authSession = nil

        let uploadCoordinator = self.uploadCoordinator
        Task {
            await uploadCoordinator.updateAuthenticationSession(nil)
        }
    }

    func refreshSessions() async {
        do {
            sessions = try await storageService.listSessions()
        } catch {
            globalErrorMessage = error.localizedDescription
        }
    }

    func startSession(mode: SessionSourceMode, track: Track?) async throws {
        try await sessionManager.startRecording(mode: mode, track: track)
    }

    func stopActiveSession() async {
        guard isStoppingActiveSession == false else { return }
        isStoppingActiveSession = true
        defer { isStoppingActiveSession = false }

        let finalizedSession = await sessionManager.stopRecording()
        await refreshSessions()

        if let finalizedSession, let authSession, isSyncAvailable {
            await uploadCoordinator.enqueue(sessionID: finalizedSession.id, authSession: authSession)
            await refreshSessions()
        }
    }

    func retryUpload(for session: RecordedSession) async {
        guard isSyncAvailable else {
            globalErrorMessage = LapCoachAppModelError.syncUnavailable.localizedDescription
            return
        }

        guard let authSession else {
            globalErrorMessage = "Sign in to upload recorded sessions."
            isLoginPresented = true
            return
        }

        await uploadCoordinator.enqueue(sessionID: session.id, authSession: authSession)
        await refreshSessions()
    }

    func addCustomTrack(_ track: Track) {
        var mergedTracks = availableTracks.filter { $0.id != track.id && $0.id != "custom-track" }
        mergedTracks.append(track)
        mergedTracks.append(contentsOf: Track.defaultLibrary.filter { defaultTrack in
            mergedTracks.contains(where: { $0.id == defaultTrack.id }) == false
        })
        availableTracks = sortTracks(mergedTracks)

        let tracksToPersist = availableTracks
        let trackStore = self.trackStore
        Task {
            do {
                try await trackStore.saveCustomTracks(tracksToPersist)
            } catch {
                await MainActor.run {
                    self.globalErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func presentLogin() {
        isLoginPresented = true
    }

    func dismissLogin() {
        isLoginPresented = false
    }

    func handleBackgroundUploadEvents(identifier: String, completionHandler: @escaping () -> Void) async {
        await uploadCoordinator.handleBackgroundSessionEvents(identifier: identifier, completionHandler: completionHandler)
    }

    private func loadTracks() async {
        let customTracks = await trackStore.loadCustomTracks()
        availableTracks = sortTracks(Track.defaultLibrary + customTracks)
    }

    private func sortTracks(_ tracks: [Track]) -> [Track] {
        tracks.sorted { lhs, rhs in
            if lhs.id == "custom-track" { return false }
            if rhs.id == "custom-track" { return true }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func makeStorageService() -> (storageService: StorageService, notice: String?) {
        let candidates: [(URL?, String?)] = [
            (nil, nil),
            (
                FileManager.default.temporaryDirectory
                    .appendingPathComponent("LapCoachMobileFallback", isDirectory: true),
                "Persistent app storage was unavailable, so the app fell back to a temporary local store."
            ),
            (
                FileManager.default.temporaryDirectory
                    .appendingPathComponent("LapCoachMobile-\(UUID().uuidString)", isDirectory: true),
                "Persistent app storage was unavailable, so the app started in a temporary local store."
            ),
            (
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                    .appendingPathComponent("LapCoachMobileLocal", isDirectory: true),
                "Persistent app storage was unavailable, so the app started from the current working directory."
            )
        ]

        for (rootURL, notice) in candidates {
            if let storageService = try? StorageService(rootURL: rootURL) {
                return (storageService, notice)
            }
        }

        fatalError("Unable to initialize local storage for Lap Coach Mobile.")
    }
}

extension LapCoachAppModel: UploadCoordinatorObserver {
    func uploadCoordinatorDidChangeSessions() async {
        await refreshSessions()
    }

    func uploadCoordinatorDidSurfaceError(_ message: String) async {
        globalErrorMessage = message
    }
}
