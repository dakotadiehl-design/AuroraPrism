import AuroraACP
import Foundation

public protocol PrismACPStateSource: Sendable {
    func snapshot() async -> [String: AnySendable]
}

public actor PrismACPEmptyStateSource: PrismACPStateSource {
    public init() {}
    public func snapshot() async -> [String: AnySendable] {
        ACPStateRevision.snapshotPayload(authorityEpoch: 0, revision: 0, resources: [])
    }
}

public actor PrismACPStatePublisher {
    public private(set) var lastSnapshot: [String: AnySendable] = [:]
    public init() {}
    public func publish(_ snapshot: [String: AnySendable]) {
        lastSnapshot = snapshot
    }
}
