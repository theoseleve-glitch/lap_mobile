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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        MetricCard(title: "Speed", value: viewModel.speedText, tint: BrandTheme.accentWarm)
                        MetricCard(title: "Accel", value: viewModel.accelerationText, tint: BrandTheme.accent)
                        MetricCard(title: "Laps", value: viewModel.lapText, tint: BrandTheme.success)
                        MetricCard(title: "Source", value: viewModel.sourceText, tint: BrandTheme.warning)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Status")
                            .font(.headline)
                            .foregroundStyle(BrandTheme.ink)

                        StatusLine(
                            title: "Location",
                            value: sessionManager.gpsAuthorizationState.rawValue.replacingOccurrences(of: "authorized", with: "authorized ")
                        )
                        StatusLine(title: "RaceBox", value: sessionManager.bleConnectionState.rawValue.capitalized)

                        if let connectedPeripheralName = sessionManager.connectedPeripheralName {
                            StatusLine(title: "Device", value: connectedPeripheralName)
                        }

                        if let lastErrorMessage = sessionManager.lastErrorMessage {
                            Text(lastErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(BrandTheme.danger)
                        }
                    }
                    .appCard()

                    Button(role: .destructive, action: stopAction) {
                        Text(sessionManager.state == .finalizing ? "Finalizing..." : "Stop Recording")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .disabled(sessionManager.state == .finalizing)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.danger)
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Dashboard")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(elapsedText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            if let activeSession = sessionManager.activeSession {
                Gauge(
                    value: min((activeSession.summary?.maxSpeedMps ?? latestSpeedMps) * 3.6, 200.0),
                    in: 0.0 ... 200.0
                ) {
                    Text("Speed")
                } currentValueLabel: {
                    Text(viewModel.speedText)
                }
                .tint(Gradient(colors: [BrandTheme.accentWarm, BrandTheme.accent]))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.14))
        )
    }

    private var elapsedText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: sessionManager.elapsedTime) ?? "0s"
    }

    private var latestSpeedMps: Double {
        sessionManager.latestSample?.speedMps ?? 0.0
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrandTheme.muted)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(BrandTheme.ink)
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint)
                .frame(height: 6)
        }
        .appCard()
    }
}

private struct StatusLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(BrandTheme.muted)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(BrandTheme.ink)
        }
    }
}
