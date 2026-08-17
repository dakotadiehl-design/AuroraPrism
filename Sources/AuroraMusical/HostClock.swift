import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Injectible monotonic clock for Musical Engine (system or virtual for tests).
public protocol HostClock: Sendable {
    func now() -> HostTime
}

/// Real macOS/Darwin host time.
public struct SystemHostClock: HostClock {
    public init() {}
    public func now() -> HostTime { HostTime.now() }
}

/// Deterministic clock for unit tests. Advance only via `advance` / `set`.
public final class VirtualHostClock: @unchecked Sendable, HostClock {
    private let lock = NSLock()
    private var _now: HostTime

    public init(start: HostTime = HostTime(nanoseconds: 0)) {
        self._now = start
    }

    public func now() -> HostTime {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    public func set(_ time: HostTime) {
        lock.lock()
        _now = time
        lock.unlock()
    }

    /// Advance by nanoseconds. Uses saturating addition (no wraparound).
    public func advance(nanoseconds: UInt64) {
        lock.lock()
        let sum = _now.nanoseconds.addingReportingOverflow(nanoseconds)
        _now = HostTime(nanoseconds: sum.overflow ? UInt64.max : sum.partialValue)
        lock.unlock()
    }

    /// Advance by seconds. Non-finite or negative values are ignored.
    public func advance(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        let nsDouble = seconds * 1_000_000_000.0
        guard nsDouble.isFinite, nsDouble > 0 else { return }
        let ns = nsDouble >= Double(UInt64.max) ? UInt64.max : UInt64(nsDouble)
        advance(nanoseconds: ns)
    }
}
