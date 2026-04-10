import SwiftUI
import UIKit

final class LapCoachAppDelegate: NSObject, UIApplicationDelegate {
    var backgroundUploadHandler: ((String, @escaping () -> Void) -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        backgroundUploadHandler?(identifier, completionHandler)
    }
}

@main
struct LapCoachMobileApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: LapCoachAppDelegate
    @StateObject private var appModel = LapCoachAppModel.live()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .task {
                    appDelegate.backgroundUploadHandler = { identifier, completionHandler in
                        Task {
                            await appModel.handleBackgroundUploadEvents(identifier: identifier, completionHandler: completionHandler)
                        }
                    }
                    await appModel.bootstrap()
                }
        }
    }
}
