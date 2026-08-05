import AuroraUI
import SwiftUI

/// Production root (UI-02) — Build Option A, Perform seed, welcome empty.
struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    /// True when there is nothing useful to show in Build (empty new show).
    private var showWelcome: Bool {
        appModel.workspace.mode == .build
            && appModel.session.project.fixtures.isEmpty
            && appModel.session.project.cueLists.isEmpty
            && appModel.documentURL == nil
    }

    var body: some View {
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
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 640)
        .navigationTitle(appModel.windowTitle)
    }
}

#if DEBUG
#Preview("Aurora Workspace") {
    ContentView()
        .environmentObject(AppModel())
}
#endif
