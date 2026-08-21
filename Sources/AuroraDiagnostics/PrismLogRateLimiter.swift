import Foundation

public enum PrismLogRateDecision: Equatable, Sendable {
    case allow
    case suppress
    case allowAndSummarize(suppressed: Int)
}

public final class PrismLogRateLimiter: @unchecked Sendable {
    private struct Bucket {
        var windowStart: Date
        var count: Int
        var suppressed: Int
    }

    private let lock = NSLock()
    private var buckets: [String: Bucket] = [:]

    public init() {}

    public func accept(key: String, policy: PrismLogRatePolicy, now: Date = Date()) -> PrismLogRateDecision {
        lock.lock()
        defer { lock.unlock() }

        if var bucket = buckets[key] {
            if now.timeIntervalSince(bucket.windowStart) >= policy.interval {
                let suppressed = bucket.suppressed
                buckets[key] = Bucket(windowStart: now, count: 1, suppressed: 0)
                if suppressed > 0 {
                    return .allowAndSummarize(suppressed: suppressed)
                }
                return .allow
            }
            if bucket.count < policy.maxPerInterval {
                bucket.count += 1
                buckets[key] = bucket
                return .allow
            }
            bucket.suppressed += 1
            buckets[key] = bucket
            return .suppress
        }

        buckets[key] = Bucket(windowStart: now, count: 1, suppressed: 0)
        return .allow
    }

    public func reset() {
        lock.lock()
        buckets.removeAll()
        lock.unlock()
    }
}
