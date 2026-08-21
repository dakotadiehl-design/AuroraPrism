import Foundation

/// Bounded live projection for tests and the in-app Console. Not the durable store.
public final class InMemoryPrismLogSink: PrismLogging, @unchecked Sendable {
    public static let shared = InMemoryPrismLogSink()

    private let lock = NSLock()
    private var events: [PrismLogEvent] = []
    private let capacity: Int
    private let byteBudget: Int
    private var bytes: Int = 0
    public var onChange: (@Sendable () -> Void)?

    public init(capacity: Int = 500, byteBudget: Int = 256 * 1024) {
        self.capacity = max(1, capacity)
        self.byteBudget = max(64, byteBudget)
    }

    public func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        true
    }

    public func log(_ event: PrismLogEvent) {
        lock.lock()
        events.append(event)
        bytes += event.estimatedByteCount
        while !events.isEmpty && (events.count > capacity || bytes > byteBudget) {
            let removed = events.removeFirst()
            bytes -= removed.estimatedByteCount
            if bytes < 0 { bytes = 0 }
        }
        let callback = onChange
        lock.unlock()
        callback?()
    }

    public func snapshot(limit: Int? = nil) -> [PrismLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        if let limit {
            return Array(events.suffix(max(0, limit)))
        }
        return events
    }

    public func clear() {
        lock.lock()
        events.removeAll()
        bytes = 0
        let callback = onChange
        lock.unlock()
        callback?()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }
}
