import Foundation

public struct PrismLogRatePolicy: Sendable, Equatable {
    public var interval: TimeInterval
    public var maxPerInterval: Int

    public init(interval: TimeInterval, maxPerInterval: Int) {
        self.interval = max(0.05, interval)
        self.maxPerInterval = max(1, maxPerInterval)
    }

    public static let oncePerSecond = PrismLogRatePolicy(interval: 1, maxPerInterval: 1)
}

public struct PrismLogEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: PrismLogLevel
    public let category: PrismLogCategory
    public let code: String
    public let humanMessage: String
    public let technicalMessage: String?
    public let metadata: [String: PrismLogValue]
    public let correlationID: UUID?
    public let ratePolicy: PrismLogRatePolicy?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: PrismLogLevel,
        category: PrismLogCategory,
        code: String,
        humanMessage: String,
        technicalMessage: String? = nil,
        metadata: [String: PrismLogValue] = [:],
        correlationID: UUID? = nil,
        ratePolicy: PrismLogRatePolicy? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.code = code
        self.humanMessage = humanMessage
        self.technicalMessage = technicalMessage
        self.metadata = Dictionary(uniqueKeysWithValues: metadata.sorted { $0.key < $1.key })
        self.correlationID = correlationID
        self.ratePolicy = ratePolicy
    }

    public var estimatedByteCount: Int {
        var total = code.utf8.count + humanMessage.utf8.count + (technicalMessage?.utf8.count ?? 0)
        for (key, value) in metadata {
            total += key.utf8.count + value.estimatedByteCount
        }
        return total
    }

    public var publicMetadataDescription: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.publicDescription)" }
            .joined(separator: " ")
    }
}
