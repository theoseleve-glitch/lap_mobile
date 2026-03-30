import Foundation

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var state: SessionLifecycleState = .idle
    @Published private(set) var activeSession: RecordedSession?
    @Published private(set) var latestSample: SensorSample?
    @Published private(set) var gpsAuthorizationState: GPSAuthorizationState = .unknown
    @Published private(set) var bleConnectionState: BLEConnectionState = .idle
    @Published private(set) var connectedPeripheralName: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lapCount = 0
    @Published private(set) var isUploading = false

    var onSessionPersisted: ((RecordedSession) -> Void)?

    private let storageService: StorageService
    private let networkService: NetworkServiceType
    private let locationService: LocationServiceType
    private let motionService: MotionServiceType
    private let bleService: BLEServiceType

    private var latestLocation: LocationSnapshot?
    private var latestMotion: MotionSnapshot?
    private var statistics = SessionStatisticsAccumulator(track: nil)
    private var writerArtifacts: SessionArtifacts?
    private var sampleContinuation: AsyncStream<SensorSample>.Continuation?
    private var writerLoopTask: Task<Void, Never>?

    init(
        storageService: StorageService,
        networkService: NetworkServiceType,
        locationService: LocationServiceType,
        motionService: MotionServiceType,
        bleService: BLEServiceType
    ) {
        self.storageService = storageService
        self.networkService = networkService
        self.locationService = locationService
        self.motionService = motionService
        self.bleService = bleService
        bindServices()
    }

    var isDashboardPresented: Bool {
        state == .recording || state == .finalizing
    }

    var elapsedTime: TimeInterval {
        guard let activeSession else { return 0.0 }
        return Date().timeIntervalSince(activeSession.startedAt)
    }

    func startRecording(mode: SessionSourceMode, track: Track?) async throws {
        guard state != .recording else { return }

        stopSensors()
        resetSessionState(track: track)

        let artifacts = try await storageService.createSession(mode: mode, track: track)
        writerArtifacts = artifacts
        activeSession = artifacts.session
        state = .recording

        configureWriterLoop(with: artifacts.writer)

        switch mode {
        case .phone:
            locationService.requestAuthorization()
            locationService.start()
            motionService.start()
        case .racebox:
            motionService.start()
            bleService.startScanning()
        }
    }

    func stopRecording(authSession: AuthSession?) async {
        guard var session = activeSession else { return }

        state = .finalizing
        stopSensors()
        sampleContinuation?.finish()
        sampleContinuation = nil
        await writerLoopTask?.value
        writerLoopTask = nil

        session.totalSamples = statistics.sampleCount
        session.endedAt = Date()
        session.status = lastErrorMessage == nil ? .completed : .failed
        session.summary = statistics.makeSummary()

        do {
            let finalizedSession = try await storageService.finalizeSession(session)
            activeSession = finalizedSession
            state = finalizedSession.status == .failed ? .failed : .completed
            onSessionPersisted?(finalizedSession)

            if let authSession {
                Task { [weak self] in
                    await self?.uploadExistingSession(finalizedSession, authSession: authSession)
                }
            }
        } catch {
            state = .failed
            lastErrorMessage = error.localizedDescription
        }
    }

    func uploadExistingSession(_ session: RecordedSession, authSession: AuthSession) async {
        isUploading = true
        var uploadingSession = session
        uploadingSession.uploadState = .uploading
        uploadingSession.lastError = nil

        do {
            try await storageService.save(session: uploadingSession)
            onSessionPersisted?(uploadingSession)

            let fileURL = await storageService.fileURL(for: session)
            let remoteSessionID = try await networkService.upload(
                session: uploadingSession,
                fileURL: fileURL,
                authSession: authSession
            )

            uploadingSession.remoteSessionID = remoteSessionID
            uploadingSession.uploadState = .uploaded
            try await storageService.save(session: uploadingSession)
            onSessionPersisted?(uploadingSession)
        } catch {
            uploadingSession.uploadState = .failed
            uploadingSession.lastError = error.localizedDescription
            try? await storageService.save(session: uploadingSession)
            onSessionPersisted?(uploadingSession)
            lastErrorMessage = error.localizedDescription
        }

        isUploading = false
    }

    private func bindServices() {
        locationService.onAuthorizationChange = { [weak self] state in
            Task { @MainActor in
                self?.gpsAuthorizationState = state
            }
        }

        locationService.onLocationUpdate = { [weak self] snapshot in
            Task { @MainActor in
                self?.handleLocation(snapshot)
            }
        }

        motionService.onMotionUpdate = { [weak self] snapshot in
            Task { @MainActor in
                self?.handleMotion(snapshot)
            }
        }

        bleService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                self?.bleConnectionState = state
            }
        }

        bleService.onPeripheralNameChange = { [weak self] name in
            Task { @MainActor in
                self?.connectedPeripheralName = name
            }
        }

        bleService.onTelemetry = { [weak self] sample in
            Task { @MainActor in
                self?.handleRaceBoxTelemetry(sample)
            }
        }
    }

    private func handleLocation(_ snapshot: LocationSnapshot) {
        latestLocation = snapshot
        guard activeSession?.sourceMode == .phone else { return }

        if latestMotion == nil {
            enqueueSample(
                SensorSample.from(
                    sessionID: activeSession?.id ?? UUID(),
                    mode: .phone,
                    location: snapshot,
                    motion: nil,
                    timestampMs: snapshot.timestampMs
                )
            )
        }
    }

    private func handleMotion(_ snapshot: MotionSnapshot) {
        latestMotion = snapshot

        guard let activeSession else { return }
        switch activeSession.sourceMode {
        case .phone:
            let sample = SensorSample.from(
                sessionID: activeSession.id,
                mode: .phone,
                location: latestLocation,
                motion: snapshot,
                timestampMs: snapshot.timestampMs
            )
            enqueueSample(sample)
        case .racebox:
            break
        }
    }

    private func handleRaceBoxTelemetry(_ telemetry: RaceBoxTelemetrySample) {
        guard let activeSession, activeSession.sourceMode == .racebox else { return }

        let sample = SensorSample(
            sessionID: activeSession.id,
            timestampMs: telemetry.timestampMs,
            source: .racebox,
            latDeg: telemetry.latitude,
            lonDeg: telemetry.longitude,
            speedMps: telemetry.speedMps,
            headingDeg: telemetry.headingDeg,
            ax: latestMotion?.ax,
            ay: latestMotion?.ay,
            az: latestMotion?.az,
            gx: latestMotion?.gx,
            gy: latestMotion?.gy,
            gz: latestMotion?.gz,
            horizontalAccuracy: nil
        )
        enqueueSample(sample)
    }

    private func enqueueSample(_ sample: SensorSample) {
        guard state == .recording else { return }

        latestSample = sample
        statistics.consume(sample)
        lapCount = statistics.laps.count

        if var session = activeSession {
            session.totalSamples = statistics.sampleCount
            activeSession = session
        }

        sampleContinuation?.yield(sample)
    }

    private func configureWriterLoop(with writer: CSVWriter) {
        let stream = AsyncStream(SensorSample.self) { continuation in
            self.sampleContinuation = continuation
        }

        writerLoopTask = Task(priority: .utility) { [weak self] in
            do {
                for await sample in stream {
                    try await writer.append(sample)
                }
                try await writer.close()
            } catch {
                await MainActor.run {
                    self?.lastErrorMessage = error.localizedDescription
                    self?.state = .failed
                }
            }
        }
    }

    private func resetSessionState(track: Track?) {
        latestLocation = nil
        latestMotion = nil
        latestSample = nil
        lapCount = 0
        lastErrorMessage = nil
        connectedPeripheralName = nil
        bleConnectionState = .idle
        statistics = SessionStatisticsAccumulator(track: track)
        writerArtifacts = nil
    }

    private func stopSensors() {
        locationService.stop()
        motionService.stop()
        bleService.stop()
    }
}
