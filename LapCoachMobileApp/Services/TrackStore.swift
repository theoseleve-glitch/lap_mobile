import Foundation

actor TrackStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, storageKey: String = "lapcoach.custom-tracks") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func loadCustomTracks() -> [Track] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? decoder.decode([Track].self, from: data)) ?? []
    }

    func saveCustomTracks(_ tracks: [Track]) throws {
        let customTracks = tracks.filter { track in
            Track.defaultLibrary.contains(where: { $0.id == track.id }) == false
        }
        let data = try encoder.encode(customTracks)
        defaults.set(data, forKey: storageKey)
    }
}
