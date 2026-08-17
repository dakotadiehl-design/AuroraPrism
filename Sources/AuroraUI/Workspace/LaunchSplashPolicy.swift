import Foundation

// MARK: - C6 splash policy (library-testable; consumed by app LaunchSplashController)

/// Timing and lifecycle rules for process-launch splash presentation.
public enum LaunchSplashPolicy: Sendable {
    /// Minimum visible time after appear (seconds).
    public static let minimumVisibleSeconds: TimeInterval = 2.85
    /// Absolute hold cap (seconds) before force-exit when bootstrap hangs.
    public static let maximumVisibleSeconds: TimeInterval = 12.0

    /// Whether auto-dismiss is allowed for this bootstrap outcome.
    public static func allowsAutoDismiss(bootstrapFailed: Bool, bootstrapReady: Bool, introComplete: Bool) -> Bool {
        !bootstrapFailed && bootstrapReady && introComplete
    }

    /// Remaining delay to honor minimum hold; 0 if already elapsed.
    public static func remainingMinimumHold(elapsed: TimeInterval) -> TimeInterval {
        max(0, minimumVisibleSeconds - elapsed)
    }

    /// Whether the max-hold watchdog should force exit.
    public static func shouldForceExitAfterMaxHold(bootstrapFailed: Bool, alreadyDismissed: Bool) -> Bool {
        !bootstrapFailed && !alreadyDismissed
    }
}

// MARK: - C5 float close policy (pure, testable)

/// Decision for floating window close / redock lifecycle.
public enum FloatWindowClosePolicy: Sendable {
    case redock
    case preserveFloating
    case ignore

    /// User closed the window (traffic light) while app is alive → redock.
    /// App is terminating → preserve floating layout.
    /// Surface already docked → ignore.
    public static func decide(isTerminating: Bool, surfaceStillFloating: Bool) -> FloatWindowClosePolicy {
        if isTerminating { return .preserveFloating }
        if surfaceStillFloating { return .redock }
        return .ignore
    }
}
