import SwiftUI

struct SessionListView: View {
    @ObservedObject var appModel: LapCoachAppModel
    @State private var showingNewSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroSection

                    if let globalErrorMessage = appModel.globalErrorMessage {
                        Text(globalErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(BrandTheme.danger)
                            .appCard()
                    }

                    if appModel.sessions.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(appModel.sessions) { session in
                                NavigationLink {
                                    SessionDetailView(session: session)
                                        .environmentObject(appModel)
                                } label: {
                                    SessionRowCard(
                                        session: session,
                                        trackName: appModel.availableTracks.first(where: { $0.id == session.trackID })?.name
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(BrandTheme.canvas.ignoresSafeArea())
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        appModel.signOut()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewSession = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(BrandTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingNewSession) {
                NewSessionView(appModel: appModel)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready for the next stint")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Your sessions are written locally first, then uploaded in chunks so you do not lose a run to a flaky connection.")
                .foregroundStyle(.white.opacity(0.88))
            HStack(spacing: 12) {
                StatusPill(title: "\(appModel.sessions.count) total", color: .white.opacity(0.2))
                StatusPill(
                    title: "\(appModel.sessions.filter { $0.uploadState == .uploaded }.count) synced",
                    color: Color.white.opacity(0.15)
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(BrandTheme.heroGradient)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sessions yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(BrandTheme.ink)
            Text("Start a phone or RaceBox recording to create your first local telemetry file.")
                .foregroundStyle(BrandTheme.muted)
            Button("Start New Session") {
                showingNewSession = true
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandTheme.accent)
        }
        .appCard()
    }
}

private struct SessionRowCard: View {
    let session: RecordedSession
    let trackName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                        .foregroundStyle(BrandTheme.ink)
                    Text(trackName ?? "No track selected")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.muted)
                }
                Spacer()
                StatusPill(title: session.uploadState.label, color: uploadColor)
            }

            HStack(spacing: 12) {
                Label(session.sourceMode.title, systemImage: session.sourceMode == .phone ? "iphone" : "dot.radiowaves.left.and.right")
                Label(session.durationText, systemImage: "timer")
                Label("\(session.totalSamples) samples", systemImage: "waveform.path.ecg")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(BrandTheme.muted)
        }
        .appCard()
    }

    private var uploadColor: Color {
        switch session.uploadState {
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

struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
