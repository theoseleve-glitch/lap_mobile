import Foundation
import SwiftUI

@MainActor
final class LapCoachAppModel: ObservableObject {
    @Published private(set) var authSession: AuthSession?
    @Published private(set) var sessions: [RecordedSession] = []
    @Published var availableTracks: [Track]
    @Published var isBootstrapping = true
    @Published var globalErrorMessage: String?

    let sessionManager: SessionManager

    private let authService: AuthService
    private let storageService: StorageService

    static func live() -> LapCoachAppModel {
        let baseURLString = ProcessInfo.processInfo.environment["LAPCOACH_API_BASE_URL"] ?? "https://api.example.com"
        let apiConfiguration = APIConfiguration(baseURL: URL(string: baseURLString)!)
        return LapCoachAppModel(apiConfiguration: apiConfiguration)
    }

    init(apiConfiguration: APIConfiguration, session: URLSession? = nil) {
        let storageService = try! StorageService()
        self.storageService = storageService
        self.authService = AuthService(apiConfiguration: apiConfiguration, session: session ?? .shared)
        let networkService = NetworkService(apiConfiguration: apiConfiguration, session: session)
        self.sessionManager = SessionManager(
            storageService: storageService,
            networkService: networkService,
            locationService: LocationService(),
            motionService: MotionService(),
            bleService: BLEService()
        )
        self.availableTracks = Track.defaultLibrary

        sessionManager.onSessionPersisted = { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSessions()
            }
        }
    }

    func bootstrap() async {
        authSession = authService.restoreSession()
        await refreshSessions()
        isBootstrapping = false
    }

    func signIn(email: String, password: String) async throws {
        authSession = try await authService.signIn(email: email, password: password)
    }

    func signOut() {
        authService.signOut()
        authSession = nil
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
        await sessionManager.stopRecording(authSession: authSession)
        await refreshSessions()
    }

    func retryUpload(for session: RecordedSession) async {
        guard let authSession else {
            globalErrorMessage = "Sign in to upload recorded sessions."
            return
        }

        await sessionManager.uploadExistingSession(session, authSession: authSession)
        await refreshSessions()
    }

    func addCustomTrack(_ track: Track) {
        availableTracks.removeAll { $0.id == track.id }
        availableTracks.append(track)
    }
}
