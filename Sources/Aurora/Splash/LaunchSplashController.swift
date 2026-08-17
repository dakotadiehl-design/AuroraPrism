import AuroraUI
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
/// Shown once per app process; never on project open / mode switch / float windows.
@MainActor
final class LaunchSplashController: ObservableObject {
    /// Full-window overlay visibility (main ContentView only).
    @Published private(set) var isVisible: Bool = true
    @Published private(set) var animationPhase: SplashAnimationPhase = .initial
    @Published private(set) var bootstrap: LaunchBootstrapPhase = .launching
    /// 0…1 for subtle exit scale / opacity.
    @Published private(set) var exitProgress: Double = 0
    /// Logo READY pulse (brief).
    @Published private(set) var readyPulse: Bool = false

    /// Minimum time splash remains visible after appear (brand sequence hold).
    /// Source of truth: `LaunchSplashPolicy` (library-testable).
    static var minimumVisibleSeconds: TimeInterval { LaunchSplashPolicy.minimumVisibleSeconds }

    /// Absolute cap so a hung bootstrap cannot trap the operator (C6C).
    static var maximumVisibleSeconds: TimeInterval { LaunchSplashPolicy.maximumVisibleSeconds }

    private var introTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var maxHoldTask: Task<Void, Never>?
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
        maxHoldTask?.cancel()
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
        // Stay visible with Continue; cancel ambient exit path.
        dismissTask?.cancel()
        dismissTask = nil
        maxHoldTask?.cancel()
        maxHoldTask = nil
    }

    /// Operator continues past a non-fatal startup presentation failure (C6C).
    func dismissAfterFailure() {
        guard case .failed = bootstrap else { return }
        forceHideForTests()
    }

    /// Start intro once first UI appears (or end of AppModel.init).
    func beginIfNeeded() {
        guard !didBegin else { return }
        didBegin = true
        appearDate = Date()
        startIntroAnimation()
        startMaximumHoldWatchdog()
    }

    // MARK: Animation

    private func startIntroAnimation() {
        introTask?.cancel()
        introTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.animationPhase = .initial

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .logoIgnition

            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .auroraReveal

            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .brandingReveal

            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            self.animationPhase = .engineActivity

            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            self.introComplete = true
            if self.bootstrapReady {
                await self.performReadyAndExit()
            } else if case .failed = self.bootstrap {
                // Hold on error with Continue.
            } else {
                self.animationPhase = .ambient
                self.tryCompleteIfPossible()
            }
        }
    }

    private func startMaximumHoldWatchdog() {
        maxHoldTask?.cancel()
        maxHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maximumVisibleSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.didDismiss else { return }
            // On hard failure, still allow Continue rather than auto-dismiss.
            if case .failed = self.bootstrap { return }
            // Hung bootstrap: reveal workspace rather than permanent splash.
            await self.performReadyAndExit(force: true)
        }
    }

    private func tryCompleteIfPossible() {
        guard bootstrapReady, introComplete, !didDismiss else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            await self?.performReadyAndExit()
        }
    }

    private func performReadyAndExit(force: Bool = false) async {
        guard !didDismiss else { return }

        if !force, let appearDate {
            let elapsed = Date().timeIntervalSince(appearDate)
            let remaining = Self.minimumVisibleSeconds - elapsed
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        guard !Task.isCancelled, !didDismiss else { return }

        if case .failed = bootstrap, !force {
            return
        }

        bootstrap = .ready
        animationPhase = .ready
        readyPulse = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        readyPulse = false
        guard !Task.isCancelled, !didDismiss else { return }

        animationPhase = .exiting
        // Smooth exit curve (ease-ish steps).
        let steps = 10
        for i in 1...steps {
            guard !Task.isCancelled else { return }
            let t = Double(i) / Double(steps)
            // Ease-in-out cubic for exit progress.
            let eased = t < 0.5
                ? 4 * t * t * t
                : 1 - pow(-2 * t + 2, 3) / 2
            exitProgress = eased
            try? await Task.sleep(nanoseconds: 28_000_000)
        }

        didDismiss = true
        isVisible = false
        introTask?.cancel()
        introTask = nil
        dismissTask = nil
        maxHoldTask?.cancel()
        maxHoldTask = nil
    }

    /// Test helper: force dismiss without animation.
    func forceHideForTests() {
        didDismiss = true
        isVisible = false
        introTask?.cancel()
        dismissTask?.cancel()
        maxHoldTask?.cancel()
        introTask = nil
        dismissTask = nil
        maxHoldTask = nil
    }
}
