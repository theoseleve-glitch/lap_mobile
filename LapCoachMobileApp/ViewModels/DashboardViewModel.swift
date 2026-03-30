import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var speedText = "0 km/h"
    @Published private(set) var accelerationText = "0.00 g"
    @Published private(set) var lapText = "0 laps"
    @Published private(set) var sourceText = "Phone"

    private var cancellables: Set<AnyCancellable> = []

    init(sessionManager: SessionManager) {
        sessionManager.$latestSample
            .combineLatest(sessionManager.$lapCount, sessionManager.$activeSession)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample, lapCount, session in
                let speedKph = (sample?.speedMps ?? 0.0) * 3.6
                self?.speedText = "\(Int(speedKph.rounded())) km/h"
                self?.accelerationText = String(format: "%.2f g", sample?.accelerationMagnitudeG ?? 0.0)
                self?.lapText = "\(lapCount) lap" + (lapCount == 1 ? "" : "s")
                self?.sourceText = session?.sourceMode.title ?? "Phone"
            }
            .store(in: &cancellables)
    }
}
