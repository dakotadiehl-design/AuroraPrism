import Combine
import Foundation

// MARK: - Animation (visual only)

/// Splash visual sequencer — independent of engine/MIDI readiness.
enum SplashAnimationPhase: Equatable, Sendable {
    case initial
    case logoIgnition
    case auroraReveal
    case brandingReveal
    case engineActivity
    case ambient
    case ready
    case exiting
}

// MARK: - Bootstrap (maps real AppModel composition steps)

/// Launch milestones that mirror real work in `AppModel.init`.
/// Not a second engine of truth for runtime I/O.
enum LaunchBootstrapPhase: Equatable, Sendable {
    case launching
    case loadingFixtureLibrary
    case startingEngine
    case startingMIDI
    case startingOutput
    case preparingWorkspace
    case ready
    case failed(String)

    var statusText: String {
        switch self {
        case .launching:
            return "INITIALIZING LIGHTING ENGINE"
        case .loadingFixtureLibrary:
            return "LOADING FIXTURE LIBRARY"
        case .startingEngine:
            return "STARTING LIGHTING ENGINE"
        case .startingMIDI:
            return "STARTING MIDI ENGINE"
        case .startingOutput:
            return "STARTING DMX OUTPUT"
        case .preparingWorkspace:
            return "PREPARING WORKSPACE"
        case .ready:
            return "READY"
        case .failed:
            return "STARTUP ERROR"
        }
    }

    var failureDetail: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var isTerminalSuccess: Bool {
        if case .ready = self { return true }
        return false
    }

    var isTerminalFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - Controller

/// Process-launch splash: animation phases + bootstrap status.
/// Shown once per app process; never on project open / mode switch.
@MainActor
final class LaunchSplashController: ObservableObject {
    /// Full-window overlay visibility.
    @Published private(set) var isVisible: Bool = true
    @Published private(set) var animationPhase: SplashAnimationPhase = .initial
    @Published private(set) var bootstrap: LaunchBootstrapPhase = .launching
    /// 0…1 for subtle exit scale / opacity.
    @Published private(set) var exitProgress: Double = 0
    /// Logo READY pulse (brief).
    @Published private(set) var readyPulse: Bool = false

    /// Minimum time splash remains visible after appear (visual hold for brand sequence).
    static let minimumVisibleSeconds: TimeInterval = 5.0

    private var introTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var appearDate: Date?
    private var introComplete = false
    private var bootstrapReady = false
    private var didBegin = false
    private var didDismiss = false

    /// For previews / tests.
    static func preview(
        phase: SplashAnimationPhase = .engineActivity,
        bootstrap: LaunchBootstrapPhase = .startingMIDI,
        visible: Bool = true
    ) -> LaunchSplashController {
        let c = LaunchSplashController()
        c.animationPhase = phase
        c.bootstrap = bootstrap
        c.isVisible = visible
        c.introComplete = true
        c.didBegin = true
        if case .ready = bootstrap {
            c.bootstrapReady = true
        }
        return c
    }

    deinit {
        introTask?.cancel()
        dismissTask?.cancel()
    }

    // MARK: Bootstrap reporting (call from AppModel.init)

    func note(_ phase: LaunchBootstrapPhase) {
        guard !didDismiss else { return }
        if case .failed = bootstrap { return }
        if case .ready = bootstrap { return }
        bootstrap = phase
    }

    func markReady() {
        guard !didDismiss else { return }
        if case .failed = bootstrap { return }
        bootstrapReady = true
        bootstrap = .ready
        tryCompleteIfPossible()
    }

    func markFailed(_ message: String) {
        guard !didDismiss else { return }
        bootstrapReady = false
        bootstrap = .failed(message)
        // Stay visible; cancel ambient exit path.
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Start intro once first UI appears (or end of AppModel.init).
    func beginIfNeeded() {
        guard !didBegin else { return }
        didBegin = true
        appearDate = Date()
        startIntroAnimation()
    }

    // MARK: Animation

    private func startIntroAnimation() {
        introTask?.cancel()
        introTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.animationPhase = .initial

            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .logoIgnition

            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .auroraReveal

            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .brandingReveal

            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .engineActivity

            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }

            self.introComplete = true
            if self.bootstrapReady {
                await self.performReadyAndExit()
            } else if case .failed = self.bootstrap {
                // Hold on error.
            } else {
                self.animationPhase = .ambient
                self.tryCompleteIfPossible()
            }
        }
    }

    private func tryCompleteIfPossible() {
        guard bootstrapReady, introComplete, !didDismiss else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            await self?.performReadyAndExit()
        }
    }

    private func performReadyAndExit() async {
        guard !didDismiss else { return }

        // Honor minimum visible time.
        if let appearDate {
            let elapsed = Date().timeIntervalSince(appearDate)
            let remaining = Self.minimumVisibleSeconds - elapsed
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        guard !Task.isCancelled, !didDismiss else { return }

        bootstrap = .ready
        animationPhase = .ready
        readyPulse = true
        try? await Task.sleep(nanoseconds: 220_000_000)
        readyPulse = false
        guard !Task.isCancelled, !didDismiss else { return }

        animationPhase = .exiting
        // Animate exitProgress for views that bind it.
        let steps = 8
        for i in 1...steps {
            guard !Task.isCancelled else { return }
            exitProgress = Double(i) / Double(steps)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }

        didDismiss = true
        isVisible = false
        introTask?.cancel()
        introTask = nil
        dismissTask = nil
    }

    /// Test helper: force dismiss without animation.
    func forceHideForTests() {
        didDismiss = true
        isVisible = false
        introTask?.cancel()
        dismissTask?.cancel()
    }
}
