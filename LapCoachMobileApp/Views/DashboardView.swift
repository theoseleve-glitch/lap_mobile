import SwiftUI

struct DashboardView: View {
    @ObservedObject var sessionManager: SessionManager
    @StateObject private var viewModel: DashboardViewModel

    let stopAction: () -> Void

    init(sessionManager: SessionManager, stopAction: @escaping () -> Void) {
        self.sessionManager = sessionManager
        self.stopAction = stopAction
        _viewModel = StateObject(wrappedValue: DashboardViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        ZStack {
            BrandTheme.heroGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                heroZone
                lapTable
                if viewModel.isStatusBarVisible {
                    statusBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Hero Zone

    private var heroZone: some View {
        HStack(spacing: 0) {
            // Left: Live delta
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.liveDeltaText)
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.liveDeltaColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    Text(viewModel.currentLapLabel)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(viewModel.currentLapTimeText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                    Text(viewModel.accelerationText)
                        .font(.title3.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)

            // Right: Speed + stop
            VStack(alignment: .trailing, spacing: 4) {
                Button(role: .destructive) {
                    stopAction()
                } label: {
                    Text(sessionManager.state == .finalizing ? "Finalizing" : "Stop")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrandTheme.danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                .disabled(sessionManager.state == .finalizing)

                Spacer()

                Text(viewModel.speedText)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("km/h")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 28)
        }
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.08))
    }

    // MARK: - Lap Table

    private var lapTable: some View {
        VStack(spacing: 0) {
            if let best = viewModel.bestLap {
                bestLapRow(best)
            }

            if viewModel.bestLap == nil && viewModel.sortedLaps.isEmpty {
                Text("Waiting for first lap crossing...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.sortedLaps) { lap in
                            lapRow(lap)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.3), value: viewModel.sortedLaps.map(\.index))
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func bestLapRow(_ lap: LapRecord) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(BrandTheme.warning)
                Text("Lap \(lap.index)")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(formatLapTime(lap.durationSeconds))
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text("BEST")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(BrandTheme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(BrandTheme.warning.opacity(0.2))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(BrandTheme.warning.opacity(0.1))
    }

    private func lapRow(_ lap: LapRecord) -> some View {
        HStack {
            Text("Lap \(lap.index)")
                .font(.subheadline)
            Spacer()
            Text(formatLapTime(lap.durationSeconds))
                .font(.subheadline.monospacedDigit())
            if let delta = lap.deltaToBestSeconds {
                Text(String(format: "%+.2f", delta))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(delta <= 0 ? BrandTheme.success : BrandTheme.danger)
                    .frame(width: 80, alignment: .trailing)
            } else {
                Text("--")
                    .font(.subheadline)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(sessionElapsedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    private var statusDotColor: Color {
        switch sessionManager.bleConnectionState {
        case .connected:
            return BrandTheme.success
        case .scanning, .connecting:
            return BrandTheme.warning
        default:
            return sessionManager.activeSession?.sourceMode == .phone ? BrandTheme.success : BrandTheme.danger
        }
    }

    private var statusText: String {
        if let name = sessionManager.connectedPeripheralName {
            return name
        }
        switch sessionManager.bleConnectionState {
        case .scanning:
            return "Scanning for RaceBox..."
        case .connecting:
            return "Connecting..."
        case .disconnected, .failed:
            return "RaceBox disconnected — reconnecting..."
        case .poweredOff:
            return "Bluetooth is off"
        default:
            return sessionManager.activeSession?.sourceMode == .phone ? "Phone GPS" : "Idle"
        }
    }

    private var sessionElapsedText: String {
        let elapsed = sessionManager.elapsedTime
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatLapTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = seconds.truncatingRemainder(dividingBy: 60.0)
        if minutes > 0 {
            return String(format: "%d:%05.2f", minutes, secs)
        }
        return String(format: "%.2f", secs)
    }
}
