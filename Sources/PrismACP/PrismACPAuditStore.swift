import Foundation

public struct PrismACPAuditEvent: Sendable, Equatable {
    public var timestamp: String
    public var operation: String
    public var disposition: String
    public var origin: String
    public var target: String?
    public var resultingEpoch: UInt64?
    public var resultingRevision: UInt64?
    public var safetyOutcome: String

    public init(
        timestamp: String,
        operation: String,
        disposition: String,
        origin: String,
        target: String? = nil,
        resultingEpoch: UInt64? = nil,
        resultingRevision: UInt64? = nil,
        safetyOutcome: String = "not_safety_sensitive"
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.disposition = disposition
        self.origin = origin
        self.target = target
        self.resultingEpoch = resultingEpoch
        self.resultingRevision = resultingRevision
        self.safetyOutcome = safetyOutcome
    }
}

public actor PrismACPAuditStore {
    private var events: [PrismACPAuditEvent] = []
    private let capacity: Int

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    public func record(_ event: PrismACPAuditEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    public func snapshot() -> [PrismACPAuditEvent] { events }
}
