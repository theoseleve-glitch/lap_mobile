import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var appModel: LapCoachAppModel

    @State private var selectedMode: SessionSourceMode = .phone
    @State private var selectedTrackID: String? = Track.defaultLibrary.first?.id
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var showingTrackEditor = false

    private var selectedTrack: Track? {
        appModel.availableTracks.first(where: { $0.id == selectedTrackID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("New Session")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(BrandTheme.ink)
                        Text("Pick the capture source, choose a track for lap timing, and launch straight into the live dashboard.")
                            .foregroundStyle(BrandTheme.muted)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Source")
                            .font(.headline)

                        Picker("Mode", selection: $selectedMode) {
                            ForEach(SessionSourceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(selectedMode == .phone
                            ? "Phone mode records GPS plus motion directly from the device."
                            : "RaceBox mode uses BLE GNSS from the accessory and merges in phone IMU data.")
                            .font(.footnote)
                            .foregroundStyle(BrandTheme.muted)
                    }
                    .appCard()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Track")
                            .font(.headline)

                        Picker("Track", selection: $selectedTrackID) {
                            ForEach(appModel.availableTracks) { track in
                                Text(track.name).tag(track.id as String?)
                            }
                        }
                        .pickerStyle(.menu)

                        if let selectedTrack {
                            Text(selectedTrack.notes ?? "No notes")
                                .font(.footnote)
                                .foregroundStyle(BrandTheme.muted)
                        }

                        Button("Edit Custom Start-Finish") {
                            showingTrackEditor = true
                        }
                        .buttonStyle(.bordered)
                        .tint(BrandTheme.accent)
                    }
                    .appCard()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BrandTheme.danger)
                    }

                    Button {
                        Task {
                            await startSession()
                        }
                    } label: {
                        HStack {
                            if isStarting {
                                ProgressView().tint(.white)
                            }
                            Text(isStarting ? "Starting..." : "Start Recording")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(BrandTheme.ink)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .disabled(isStarting)
                }
                .padding(20)
            }
            .background(BrandTheme.canvas.ignoresSafeArea())
            .navigationTitle("Start")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingTrackEditor) {
                TrackEditorView(track: selectedTrack) { track in
                    appModel.addCustomTrack(track)
                    selectedTrackID = track.id
                }
            }
        }
    }

    private func startSession() async {
        isStarting = true
        errorMessage = nil

        do {
            try await appModel.startSession(mode: selectedMode, track: selectedTrack)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isStarting = false
    }
}
