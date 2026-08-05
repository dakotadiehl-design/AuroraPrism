import Foundation

/// Documented live-performance budgets (PR30).
public enum PerformanceBudget {
    /// Default engine frame rate (Hz).
    public static let defaultFrameRateHz: Double = 40
    /// Max acceptable mean frame work on a modern Mac for scale test (ms).
    public static let scaleTestMeanFrameMs: Double = 5
    /// Snapshot publish throttle default (Hz).
    public static let defaultSnapshotHz: Double = 20
    /// UI edit feedback target (ms) — documentation constant.
    public static let uiFeedbackTargetMs: Double = 16
}
