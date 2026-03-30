import SwiftUI

struct TrackEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Track) -> Void
    private let existingTrack: Track?

    @State private var name: String
    @State private var city: String
    @State private var startLatitude: String
    @State private var startLongitude: String
    @State private var endLatitude: String
    @State private var endLongitude: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(track: Track?, onSave: @escaping (Track) -> Void) {
        self.existingTrack = track
        self.onSave = onSave
        _name = State(initialValue: track?.name ?? "Custom Track")
        _city = State(initialValue: track?.city ?? "")
        _startLatitude = State(initialValue: track?.startFinishLine?.start.latitude.description ?? "")
        _startLongitude = State(initialValue: track?.startFinishLine?.start.longitude.description ?? "")
        _endLatitude = State(initialValue: track?.startFinishLine?.end.latitude.description ?? "")
        _endLongitude = State(initialValue: track?.startFinishLine?.end.longitude.description ?? "")
        _notes = State(initialValue: track?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Track") {
                    TextField("Track Name", text: $name)
                    TextField("City", text: $city)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("Start / Finish Line") {
                    TextField("Start Latitude", text: $startLatitude)
                        .keyboardType(.decimalPad)
                    TextField("Start Longitude", text: $startLongitude)
                        .keyboardType(.decimalPad)
                    TextField("End Latitude", text: $endLatitude)
                        .keyboardType(.decimalPad)
                    TextField("End Longitude", text: $endLongitude)
                        .keyboardType(.decimalPad)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BrandTheme.danger)
                    }
                }
            }
            .navigationTitle("Track Editor")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        guard
            let startLat = Double(startLatitude),
            let startLon = Double(startLongitude),
            let endLat = Double(endLatitude),
            let endLon = Double(endLongitude)
        else {
            errorMessage = "Enter valid coordinates for the full start-finish line."
            return
        }

        let track = Track(
            id: {
                if let existingTrack, existingTrack.id != "custom-track" {
                    return existingTrack.id
                }
                return UUID().uuidString
            }(),
            name: name.isEmpty ? "Custom Track" : name,
            city: city.isEmpty ? "Unknown" : city,
            startFinishLine: StartFinishLine(
                start: GeoPoint(latitude: startLat, longitude: startLon),
                end: GeoPoint(latitude: endLat, longitude: endLon)
            ),
            notes: notes.isEmpty ? nil : notes
        )

        onSave(track)
        dismiss()
    }
}
