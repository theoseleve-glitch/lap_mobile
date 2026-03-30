import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: LapCoachAppModel

    var body: some View {
        ZStack {
            BrandTheme.canvas.ignoresSafeArea()
            content
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { appModel.sessionManager.isDashboardPresented },
                set: { isPresented in
                    if isPresented == false, appModel.sessionManager.isDashboardPresented {
                        Task {
                            await appModel.stopActiveSession()
                        }
                    }
                }
            )
        ) {
            DashboardView(sessionManager: appModel.sessionManager) {
                Task {
                    await appModel.stopActiveSession()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appModel.isBootstrapping {
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(BrandTheme.accent)
                Text("Preparing telemetry workspace")
                    .foregroundStyle(BrandTheme.ink)
            }
        } else if appModel.authSession == nil {
            LoginView(appModel: appModel)
        } else {
            SessionListView(appModel: appModel)
        }
    }
}
