import Foundation

public final class CompositePrismLogger: PrismLogging, @unchecked Sendable {
    private let sinks: [any PrismLogging]
    private let limiter: PrismLogRateLimiter
    private let configuration: () -> PrismLogConfiguration
    private let now: () -> Date

    public init(
        sinks: [any PrismLogging],
        limiter: PrismLogRateLimiter = PrismLogRateLimiter(),
        configuration: @escaping () -> PrismLogConfiguration = { PrismLogConfigurationStore.shared.current() },
        now: @escaping () -> Date = Date.init
    ) {
        self.sinks = sinks
        self.limiter = limiter
        self.configuration = configuration
        self.now = now
    }

    public func isEnabled(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        configuration().accepts(level, category: category)
    }

    public func log(_ event: PrismLogEvent) {
        guard isEnabled(event.level, category: event.category) else { return }
        let sanitized = PrismLogSanitizer.sanitize(event)
        if let policy = sanitized.ratePolicy {
            let key = "\(sanitized.category.rawValue).\(sanitized.code)"
            switch limiter.accept(key: key, policy: policy, now: now()) {
            case .suppress:
                return
            case .allow:
                fanOut(sanitized)
            case .allowAndSummarize(let suppressed):
                fanOut(sanitized)
                let summaryLevel = sanitized.level
                let summary = PrismLogEvent(
                    level: summaryLevel,
                    category: sanitized.category,
                    code: "log.rate_limited",
                    humanMessage: "Repeated messages were combined to keep the log readable.",
                    technicalMessage: "suppressed \(suppressed) repeats of \(sanitized.code)",
                    metadata: [
                        "count": .count(suppressed),
                        "code": .public(sanitized.code),
                    ],
                    correlationID: sanitized.correlationID
                )
                if isEnabled(summaryLevel, category: sanitized.category) {
                    fanOut(summary)
                }
            }
            return
        }
        fanOut(sanitized)
    }

    private func fanOut(_ event: PrismLogEvent) {
        for sink in sinks {
            sink.log(event)
        }
    }
}
