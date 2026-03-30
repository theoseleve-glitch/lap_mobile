import SwiftUI

@main
struct LapCoachMobileApp: App {
    @StateObject private var appModel = LapCoachAppModel.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .task {
                    await appModel.bootstrap()
                }
        }
    }
}
