import Foundation

/// Fixed-rate timer that invokes a tick handler on a background queue.
public final class EngineScheduler: @unchecked Sendable {
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var _running = false

    public init(label: String = "com.aurora.engine.scheduler") {
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _running
    }

    /// Starts periodic ticks. `period` is the frame period in seconds.
    public func start(period: TimeInterval, handler: @escaping () -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let ns = UInt64(max(period, 0.001) * 1_000_000_000)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(ns)), leeway: .milliseconds(1))
        timer.setEventHandler(handler: handler)
        lock.lock()
        self.timer = timer
        _running = true
        lock.unlock()
        timer.resume()
    }

    public func stop() {
        lock.lock()
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        _running = false
        lock.unlock()
    }
}
