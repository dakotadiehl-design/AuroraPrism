import Foundation

/// Counts occurrences and yields the count at most once per interval.
public final class PrismIntervalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmit: Date?
    private var count = 0
    private let interval: TimeInterval

    public init(interval: TimeInterval = 1) {
        self.interval = max(0.05, interval)
    }

    /// Record one occurrence. Returns the accumulated count when a summary should be emitted.
    public func note(now: Date = Date()) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if let lastEmit, now.timeIntervalSince(lastEmit) < interval {
            return nil
        }
        lastEmit = now
        let emitted = count
        count = 0
        return emitted
    }
}
