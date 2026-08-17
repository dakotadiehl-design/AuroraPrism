import Foundation

/// Rate-limit / flood protection for Advanced MIDI (Pass-1 P0-J safety).
///
/// **Physical release always bypasses** flood/debounce so Note Off (and velocity-zero Note On)
/// can unwind AME holds and MIDI behaviors even under dense input.
///
/// Rolling window uses **monotonic event timestamps** (ingress HostTime seconds), not wall clock.
public final class MIDISafetyLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var eventTimes: [TimeInterval] = []
    /// Max non-release events accepted per rolling 1 second window.
    public var maxEventsPerSecond: Int
    /// Minimum interval between accepted non-release events for same source key (debounce).
    public var debounceSeconds: TimeInterval
    private var lastAcceptedByKey: [String: TimeInterval] = [:]
    private var droppedCount: UInt64 = 0

    public init(maxEventsPerSecond: Int = 200, debounceSeconds: TimeInterval = 0) {
        self.maxEventsPerSecond = max(1, maxEventsPerSecond)
        self.debounceSeconds = max(0, debounceSeconds)
    }

    public var droppedEventCount: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return droppedCount
    }

    /// Note Off / velocity-zero Note On — must never be flood-suppressed for safety unwind.
    public static func isPhysicalRelease(_ event: MIDIEvent) -> Bool {
        switch event {
        case .noteOff:
            return true
        case .noteOn(_, _, let velocity, _, _):
            return velocity == 0
        default:
            return false
        }
    }

    /// Returns true if the event should be processed for ordinary activation/performance work.
    /// Physical release always returns true and does **not** consume flood budget.
    ///
    /// - Parameter now: Monotonic time base (prefer `event.timestamp`). Defaults to event timestamp
    ///   when using `allow(event:)` — do not pass wall-clock `Date()` for production paths.
    public func allow(event: MIDIEvent, now: TimeInterval? = nil) -> Bool {
        if Self.isPhysicalRelease(event) {
            return true
        }
        let t = now ?? event.timestamp
        lock.lock()
        defer { lock.unlock() }
        eventTimes = eventTimes.filter { t - $0 < 1.0 }
        if eventTimes.count >= maxEventsPerSecond {
            droppedCount &+= 1
            return false
        }
        if debounceSeconds > 0 {
            let key = "\(event.sourceID)|\(event.messageTypeKey)|\(event.data1 ?? 255)"
            if let last = lastAcceptedByKey[key], t - last < debounceSeconds {
                droppedCount &+= 1
                return false
            }
            lastAcceptedByKey[key] = t
        }
        eventTimes.append(t)
        return true
    }

    public func reset() {
        lock.lock()
        eventTimes.removeAll()
        lastAcceptedByKey.removeAll()
        droppedCount = 0
        lock.unlock()
    }
}
