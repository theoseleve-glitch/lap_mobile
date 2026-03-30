import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject private var appModel: LapCoachAppModel

    let session: RecordedSession

    private var currentSession: RecordedSession {
        appModel.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overviewCard
                summaryCard
                lapCard

                if currentSession.uploadState != .uploaded {
                    Button("Retry Upload") {
                        Task {
                            await appModel.retryUpload(for: currentSession)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandTheme.accent)
                }
            }
            .padding(20)
        }
        .background(BrandTheme.canvas.ignoresSafeArea())
        .navigationTitle("Session")
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentSession.startedAt.formatted(date: .abbreviated, time: .standard))
                .font(.title3.weight(.semibold))
                .foregroundStyle(BrandTheme.ink)
            Text(appModel.availableTracks.first(where: { $0.id == currentSession.trackID })?.name ?? "No track selected")
                .foregroundStyle(BrandTheme.muted)

            HStack(spacing: 10) {
                StatusPill(title: currentSession.sourceMode.title, color: BrandTheme.accent)
                StatusPill(title: currentSession.uploadState.label, color: uploadColor)
            }

            Text(currentSession.localFilePath)
                .font(.footnote)
                .foregroundStyle(BrandTheme.muted)
                .textSelection(.enabled)
        }
        .appCard()
    }

    private var summaryCard: some View {
        let summary = currentSession.summary
        return VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.headline)
                .foregroundStyle(BrandTheme.ink)

            SummaryLine(title: "Duration", value: currentSession.durationText)
            SummaryLine(title: "Samples", value: "\(currentSession.totalSamples)")
            SummaryLine(title: "Distance", value: String(format: "%.0f m", summary?.distanceMeters ?? 0.0))
            SummaryLine(title: "Top Speed", value: String(format: "%.1f km/h", (summary?.maxSpeedMps ?? 0.0) * 3.6))

            if let bestLap = summary?.bestLap {
                SummaryLine(title: "Best Lap", value: String(format: "%.2f s", bestLap.durationSeconds))
            }
        }
        .appCard()
    }

    private var lapCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Laps")
                .font(.headline)
                .foregroundStyle(BrandTheme.ink)

            if let laps = currentSession.summary?.laps, laps.isEmpty == false {
                ForEach(laps) { lap in
                    HStack {
                        Text("Lap \(lap.index)")
                        Spacer()
                        Text(String(format: "%.2f s", lap.durationSeconds))
                            .fontWeight(.semibold)
                        if let delta = lap.deltaToBestSeconds {
                            Text(String(format: "%+.2f", delta))
                                .foregroundStyle(delta > 0 ? BrandTheme.warning : BrandTheme.success)
                        }
                    }
                    .foregroundStyle(BrandTheme.ink)
                }
            } else {
                Text("No lap crossings detected for this session.")
                    .foregroundStyle(BrandTheme.muted)
            }
        }
        .appCard()
    }

    private var uploadColor: Color {
        switch currentSession.uploadState {
        case .uploaded:
            return BrandTheme.success
        case .uploading:
            return BrandTheme.warning
        case .pending:
            return BrandTheme.accent
        case .failed:
            return BrandTheme.danger
        }
    }
}

private struct SummaryLine: View {
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
