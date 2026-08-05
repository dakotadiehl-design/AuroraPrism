import Foundation

/// Monotonic or synthetic time source for the engine tick.
public protocol EngineClock: Sendable {
    /// Seconds (monotonic for live clocks; synthetic for tests).
    func now() -> TimeInterval
}

/// Wall/monotonic clock for live shows.
public struct ContinuousEngineClock: EngineClock, Sendable {
    public init() {}

    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// Deterministic clock for unit tests.
public final class ManualEngineClock: EngineClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _time: TimeInterval

    public init(time: TimeInterval = 0) {
        self._time = time
    }

    public var time: TimeInterval {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _time
        }
        set {
            lock.lock()
            _time = newValue
            lock.unlock()
        }
    }

    public func now() -> TimeInterval {
        time
    }

    public func advance(by dt: TimeInterval) {
        lock.lock()
        _time += dt
        lock.unlock()
    }
}
