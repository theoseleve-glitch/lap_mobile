import Combine
import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var liveDeltaText = "--"
    @Published private(set) var liveDeltaColor: Color = .white
    @Published private(set) var currentLapTimeText = "0.00"
    @Published private(set) var currentLapLabel = "Lap 0"
    @Published private(set) var speedText = "0"
    @Published private(set) var accelerationText = "0.0 g"
    @Published private(set) var sourceText = "Phone"
    @Published private(set) var bestLap: LapRecord?
    @Published private(set) var sortedLaps: [LapRecord] = []
    @Published private(set) var isStatusBarVisible = true

    private var cancellables: Set<AnyCancellable> = []
    private var statusBarHideTask: Task<Void, Never>?

    init(sessionManager: SessionManager) {
        // Speed, accel, source, lap label
        sessionManager.$latestSample
            .combineLatest(sessionManager.$lapCount, sessionManager.$activeSession)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample, lapCount, session in
                let speedKph = (sample?.speedMps ?? 0.0) * 3.6
                self?.speedText = "\(Int(speedKph.rounded()))"
                self?.accelerationText = String(format: "%.1f g", sample?.accelerationMagnitudeG ?? 0.0)
                self?.sourceText = session?.sourceMode.title ?? "Phone"
                self?.currentLapLabel = "Lap \(lapCount + 1)"
            }
            .store(in: &cancellables)

        // Live delta
        sessionManager.$liveDelta
            .receive(on: DispatchQueue.main)
            .sink { [weak self] delta in
                guard let self else { return }
                if let delta {
                    let sign = delta >= 0 ? "+" : ""
                    self.liveDeltaText = "\(sign)\(String(format: "%.2f", delta))"
                    self.liveDeltaColor = delta <= 0 ? BrandTheme.success : BrandTheme.danger
                } else {
                    self.liveDeltaText = "--"
                    self.liveDeltaColor = .white
                }
            }
            .store(in: &cancellables)

        // Current lap time
        sessionManager.$currentLapTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] elapsed in
                let minutes = Int(elapsed) / 60
                let seconds = elapsed.truncatingRemainder(dividingBy: 60.0)
                if minutes > 0 {
                    self?.currentLapTimeText = String(format: "%d:%05.2f", minutes, seconds)
                } else {
                    self?.currentLapTimeText = String(format: "%.2f", seconds)
                }
            }
            .store(in: &cancellables)

        // Lap table: pinned best + reverse chronological (temporary: uses summary laps until completedLaps is wired)
        sessionManager.$lapCount
            .combineLatest(sessionManager.$activeSession)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, session in
                guard let self else { return }
                let laps = session?.summary?.laps ?? []
                self.bestLap = laps.min(by: { $0.durationSeconds < $1.durationSeconds })
                self.sortedLaps = laps
                    .filter { $0.index != self.bestLap?.index }
                    .sorted { $0.index > $1.index }
            }
            .store(in: &cancellables)

        // Status bar: show on connection state change, auto-hide after GPS fix
        sessionManager.$bleConnectionState
            .combineLatest(sessionManager.$gpsAuthorizationState, sessionManager.$latestSample)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bleState, gpsState, sample in
                guard let self else { return }
                let hasSignalIssue = bleState == .disconnected || bleState == .failed || bleState == .poweredOff
                if hasSignalIssue {
                    self.isStatusBarVisible = true
                    self.statusBarHideTask?.cancel()
                } else if sample != nil, self.isStatusBarVisible {
                    self.scheduleStatusBarHide()
                }
            }
            .store(in: &cancellables)

        scheduleStatusBarHide()
    }

    private func scheduleStatusBarHide() {
        statusBarHideTask?.cancel()
        statusBarHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard Task.isCancelled == false else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.isStatusBarVisible = false
            }
        }
    }
}
