import AppKit
import AuroraUI
import SwiftUI

extension Notification.Name {
    static let auroraOpenAbout = Notification.Name("aurora.openAbout")
    static let openAMEEngineWindow = Notification.Name("aurora.openAMEEngine")
    static let openLightKeyFixtureImporter = Notification.Name("prism.openLightKeyFixtureImporter")
    static let openUserFixtureLibrary = Notification.Name("prism.openUserFixtureLibrary")
    static let prismBringMainWindowForward = Notification.Name("prism.bringMainWindowForward")
}

/// Production root (UI-02) — Build Option A, Perform seed, explicit Welcome (DOC-01).
struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

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
                            onDemo: { appModel.openDemoSummerNight() },
                            onOpenRecent: { appModel.openShow(at: $0) }
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

            // Process-launch splash (once, main window only). Workspace initializes underneath.
            // C6C: never mounted on float WindowGroups — avoids duplicate/stranded splash.
            if appModel.launchSplash.isVisible {
                AuroraSplashView(model: appModel.launchSplash)
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
        .preferredColorScheme(.dark)
        .buttonStyle(AuroraButtonStyle())
        .frame(minWidth: 1000, minHeight: 640)
        .background(
            MainPrismWindowCloseObserver {
                guard !appModel.isTerminating else { return }
                NSApp.terminate(nil)
            }
        )
        .navigationTitle(appModel.windowTitle)
        .animation(.easeInOut(duration: 0.36), value: appModel.launchSplash.isVisible)
        .onAppear {
            appModel.launchSplash.beginIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .auroraOpenAbout)) { _ in
            openWindow(id: "about-aurora")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAMEEngineWindow)) { _ in
            openWindow(id: "ame-engine")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLightKeyFixtureImporter)) { _ in
            openWindow(id: "lightkey-fixture-importer")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUserFixtureLibrary)) { _ in
            openWindow(id: "user-fixture-library")
        }
    }
}

/// SwiftUI keeps the process alive while auxiliary Window scenes remain open. Observe the
/// exact primary Prism window so closing it initiates the normal AppKit termination flow,
/// including the dirty-document prompt and orderly hardware/window shutdown.
private struct MainPrismWindowCloseObserver: NSViewRepresentable {
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClose = onClose
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onClose: () -> Void
        private weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []
        private var configuredWindowID: ObjectIdentifier?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            detach()
            self.window = window
            let windowID = ObjectIdentifier(window)
            if configuredWindowID != windowID {
                configuredWindowID = windowID
                restorePlacement(of: window)
                // SwiftUI may perform one final scene placement after the representable
                // resolves its window. Reapply once on the following launch turn.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak window] in
                    guard let self, let window, self.window === window else { return }
                    self.restorePlacement(of: window)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak window] in
                    guard let self, let window, self.window === window else { return }
                    MainPrismWindowPlacementStore.save(window: window)
                }
            }
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let self, let window else { return }

                // AppKit already asks the application delegate to terminate when the
                // last window closes. Sending another terminate request here races that
                // request: cancelling the dirty-document alert can cancel one request
                // while the duplicate still quits the app. Only intervene when another
                // visible window means this is not the application's last window.
                let anotherWindowRemainsVisible = NSApp.windows.contains {
                    $0 !== window && $0.isVisible
                }
                if anotherWindowRemainsVisible {
                    self.onClose()
                }
            })
            tokens.append(NotificationCenter.default.addObserver(
                forName: .prismBringMainWindowForward,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let window = self?.window, window.isVisible else { return }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            })
            for name in [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
            ] {
                tokens.append(NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window, self.window === window else { return }
                    MainPrismWindowPlacementStore.save(window: window)
                })
            }
        }

        private func restorePlacement(of window: NSWindow) {
            guard let placement = MainPrismWindowPlacementStore.load() else { return }
            let recovered = WorkspaceFloatState.recoverFrame(
                placement.frame,
                preferredScreenID: placement.screenID,
                screens: AuroraScreenIdentity.currentVisibleScreens()
            )
            window.setFrame(recovered.frame, display: true)
        }

        func detach() {
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            tokens.removeAll()
            window = nil
        }

        deinit { detach() }
    }
}

private struct MainPrismWindowPlacement: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var screenID: String?

    var frame: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum MainPrismWindowPlacementStore {
    private static let key = "prism.main-window.placement.v1"

    static func load(from defaults: UserDefaults = .standard) -> MainPrismWindowPlacement? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MainPrismWindowPlacement.self, from: data)
    }

    static func save(window: NSWindow, to defaults: UserDefaults = .standard) {
        let frame = window.frame
        guard frame.width > 100, frame.height > 100 else { return }
        let placement = MainPrismWindowPlacement(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height,
            screenID: window.screen.map(AuroraScreenIdentity.identifier(for:))
        )
        guard let data = try? JSONEncoder().encode(placement) else { return }
        defaults.set(data, forKey: key)
    }
}

#if DEBUG
#Preview("Prism Workspace") {
    ContentView()
        .environmentObject(AppModel())
}
#endif
