import Foundation

/// Rate-limit / flood protection for Advanced MIDI (Pass-1 P0-J safety).
public final class MIDISafetyLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var eventTimes: [TimeInterval] = []
    /// Max events accepted per rolling 1 second window.
    public var maxEventsPerSecond: Int
    /// Minimum interval between accepted events for same source key (debounce).
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

    /// Returns true if the event should be processed.
    public func allow(event: MIDIEvent, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        eventTimes = eventTimes.filter { now - $0 < 1.0 }
        if eventTimes.count >= maxEventsPerSecond {
            droppedCount &+= 1
            return false
        }
        if debounceSeconds > 0 {
            let key = "\(event.sourceID)|\(event.messageTypeKey)|\(event.data1 ?? 255)"
            if let last = lastAcceptedByKey[key], now - last < debounceSeconds {
                droppedCount &+= 1
                return false
            }
            lastAcceptedByKey[key] = now
        }
        eventTimes.append(now)
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
