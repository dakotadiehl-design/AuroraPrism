import Foundation

/// Rolling timing samples for engine frames (PR30).
public struct EngineFrameMetrics: Equatable, Sendable {
    public var sampleCount: Int
    public var lastFrameMs: Double
    public var meanFrameMs: Double
    /// Maximum since last `reset()` (not rolling-window) — P2-4.
    public var lifetimeMaxFrameMs: Double
    /// Alias for clarity in older call sites.
    public var maxFrameMs: Double { lifetimeMaxFrameMs }

    public init(
        sampleCount: Int = 0,
        lastFrameMs: Double = 0,
        meanFrameMs: Double = 0,
        lifetimeMaxFrameMs: Double = 0
    ) {
        self.sampleCount = sampleCount
        self.lastFrameMs = lastFrameMs
        self.meanFrameMs = meanFrameMs
        self.lifetimeMaxFrameMs = lifetimeMaxFrameMs
    }

    public static let empty = EngineFrameMetrics()
}

/// Thread-safe accumulator used by `LightingEngine`.
public final class FrameMetricsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var sumMs = 0.0
    private var maxMs = 0.0
    private var lastMs = 0.0
    private let window: Int

    public init(window: Int = 240) {
        self.window = max(1, window)
    }

    public func record(durationSeconds: TimeInterval) {
        let ms = durationSeconds * 1000
        lock.lock()
        lastMs = ms
        maxMs = max(maxMs, ms)
        sumMs += ms
        count += 1
        if count > window {
            // Simple decay: keep mean stable without storing full ring.
            sumMs *= Double(window) / Double(count)
            count = window
        }
        lock.unlock()
    }

    public func snapshot() -> EngineFrameMetrics {
        lock.lock()
        defer { lock.unlock() }
        let mean = count == 0 ? 0 : sumMs / Double(count)
        return EngineFrameMetrics(
            sampleCount: count,
            lastFrameMs: lastMs,
            meanFrameMs: mean,
            lifetimeMaxFrameMs: maxMs
        )
    }

    public func reset() {
        lock.lock()
        count = 0
        sumMs = 0
        maxMs = 0
        lastMs = 0
        lock.unlock()
    }
}
