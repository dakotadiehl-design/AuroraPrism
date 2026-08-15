import AuroraUI
import SwiftUI

/// Production root (UI-02) — Build Option A, Perform seed, explicit Welcome (DOC-01).
struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    /// Explicit application Welcome state — not inferred from empty project contents (DOC-01).
    private var showWelcome: Bool {
        appModel.workspace.showsWelcomeScreen && appModel.workspace.mode == .build
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                AuroraBuildToolbar()
                Group {
                    if appModel.workspace.mode == .perform {
                        PerformWorkspaceShell()
                    } else if showWelcome {
                        WelcomeEmptyView(
                            onNew: { appModel.newShow() },
                            onOpen: { appModel.openShow() },
                            onDemo: { appModel.openDemoSummerNight() }
                        )
                    } else {
                        BuildWorkspaceHost()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if appModel.workspace.mode == .build && !showWelcome {
                    AuroraAppStatusBar()
                }
            }
            .background(AuroraColor.surfaceBase)

            // Process-launch splash (once). Workspace initializes underneath.
            if appModel.launchSplash.isVisible {
                AuroraSplashView(model: appModel.launchSplash)
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 640)
        .navigationTitle(appModel.windowTitle)
        .animation(.easeOut(duration: 0.32), value: appModel.launchSplash.isVisible)
        .onAppear {
            appModel.launchSplash.beginIfNeeded()
        }
    }
}

#if DEBUG
#Preview("Aurora Workspace") {
    ContentView()
        .environmentObject(AppModel())
}
#endif
