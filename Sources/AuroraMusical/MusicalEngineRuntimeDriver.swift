import Foundation

/// High-resolution non-UI driver for `MusicalEngine.tick` / scheduler harvest (audit Wave 1 / P0-5).
///
/// Fixed 4 ms cadence is intentional for a live-show desktop app: reliability and low scheduler
/// jitter win over adaptive timer economy. Opening the AME window must not change this cadence
/// (presentation timers are separate).
public final class MusicalEngineRuntimeDriver: @unchecked Sendable {
    private let lock = NSLock()
    private weak var engine: MusicalEngine?
    private var timer: DispatchSourceTimer?
    private let queue: DispatchQueue
    /// Fixed harvest interval (seconds). Default 4 ms.
    private let intervalSeconds: Double
    private var running = false

    public init(
        engine: MusicalEngine? = nil,
        intervalSeconds: Double = 0.004
    ) {
        self.engine = engine
        self.intervalSeconds = max(0.001, intervalSeconds)
        self.queue = DispatchQueue(label: "com.aurora.musical.driver", qos: .userInteractive)
    }

    /// Backward-compatible init accepting unused idle/active pair (always uses active/fixed interval).
    public convenience init(
        engine: MusicalEngine? = nil,
        idleIntervalSeconds: Double,
        activeIntervalSeconds: Double
    ) {
        self.init(engine: engine, intervalSeconds: activeIntervalSeconds)
        _ = idleIntervalSeconds
    }

    public func setEngine(_ engine: MusicalEngine?) {
        lock.lock()
        self.engine = engine
        lock.unlock()
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    public func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()
        armTimer()
    }

    public func stop() {
        lock.lock()
        running = false
        timer?.cancel()
        timer = nil
        lock.unlock()
    }

    private func armTimer() {
        lock.lock()
        timer?.cancel()
        guard running else { lock.unlock(); return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: intervalSeconds,
            leeway: .milliseconds(1)
        )
        t.setEventHandler { [weak self] in
            self?.tickOnce()
        }
        timer = t
        lock.unlock()
        t.resume()
    }

    private func tickOnce() {
        lock.lock()
        let eng = engine
        let stillRunning = running
        lock.unlock()
        guard stillRunning, let eng else { return }
        eng.tick()
    }
}
