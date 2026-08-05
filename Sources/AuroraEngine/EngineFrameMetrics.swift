import Foundation

/// Rolling timing samples for engine frames (PR30 / P2-18).
public struct EngineFrameMetrics: Equatable, Sendable {
    public var sampleCount: Int
    public var lastFrameMs: Double
    public var meanFrameMs: Double
    public var p95FrameMs: Double
    public var p99FrameMs: Double
    /// Maximum since last `reset()` (not rolling-window).
    public var lifetimeMaxFrameMs: Double
    public var overrunCount: UInt64
    public var consecutiveOverruns: UInt64
    public var targetPeriodMs: Double
    public var jitterMs: Double
    /// Alias for clarity in older call sites.
    public var maxFrameMs: Double { lifetimeMaxFrameMs }

    public init(
        sampleCount: Int = 0,
        lastFrameMs: Double = 0,
        meanFrameMs: Double = 0,
        p95FrameMs: Double = 0,
        p99FrameMs: Double = 0,
        lifetimeMaxFrameMs: Double = 0,
        overrunCount: UInt64 = 0,
        consecutiveOverruns: UInt64 = 0,
        targetPeriodMs: Double = 25,
        jitterMs: Double = 0
    ) {
        self.sampleCount = sampleCount
        self.lastFrameMs = lastFrameMs
        self.meanFrameMs = meanFrameMs
        self.p95FrameMs = p95FrameMs
        self.p99FrameMs = p99FrameMs
        self.lifetimeMaxFrameMs = lifetimeMaxFrameMs
        self.overrunCount = overrunCount
        self.consecutiveOverruns = consecutiveOverruns
        self.targetPeriodMs = targetPeriodMs
        self.jitterMs = jitterMs
    }

    public static let empty = EngineFrameMetrics()
}

/// Thread-safe accumulator used by `LightingEngine`.
public final class FrameMetricsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Double] = []
    private var maxMs = 0.0
    private var lastMs = 0.0
    private var overrunCount: UInt64 = 0
    private var consecutiveOverruns: UInt64 = 0
    private let window: Int
    private var targetPeriodMs: Double

    public init(window: Int = 240, targetPeriodMs: Double = 25) {
        self.window = max(16, window)
        self.targetPeriodMs = targetPeriodMs
        samples.reserveCapacity(self.window)
    }

    public func setTargetPeriodMs(_ ms: Double) {
        lock.lock()
        targetPeriodMs = max(1, ms)
        lock.unlock()
    }

    public func record(durationSeconds: TimeInterval) {
        let ms = durationSeconds * 1000
        lock.lock()
        lastMs = ms
        maxMs = max(maxMs, ms)
        samples.append(ms)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }
        if ms > targetPeriodMs {
            overrunCount &+= 1
            consecutiveOverruns &+= 1
        } else {
            consecutiveOverruns = 0
        }
        lock.unlock()
    }

    public func snapshot() -> EngineFrameMetrics {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else {
            return EngineFrameMetrics(targetPeriodMs: targetPeriodMs)
        }
        let sorted = samples.sorted()
        let mean = samples.reduce(0, +) / Double(samples.count)
        let p95 = percentile(sorted, 0.95)
        let p99 = percentile(sorted, 0.99)
        let minS = sorted.first ?? 0
        let maxS = sorted.last ?? 0
        return EngineFrameMetrics(
            sampleCount: samples.count,
            lastFrameMs: lastMs,
            meanFrameMs: mean,
            p95FrameMs: p95,
            p99FrameMs: p99,
            lifetimeMaxFrameMs: maxMs,
            overrunCount: overrunCount,
            consecutiveOverruns: consecutiveOverruns,
            targetPeriodMs: targetPeriodMs,
            jitterMs: maxS - minS
        )
    }

    public func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        maxMs = 0
        lastMs = 0
        overrunCount = 0
        consecutiveOverruns = 0
        lock.unlock()
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[idx]
    }
}
