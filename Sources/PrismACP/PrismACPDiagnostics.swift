import Foundation

public struct PrismACPDiagnostics: Sendable, Equatable {
    public var enabled: Bool
    public var listenerState: PrismACPListenerState
    public var sessionCount: Int
    public var nodeID: String
    public var instanceID: String
    public var advertisedCapabilities: [String]

    public init(
        enabled: Bool,
        listenerState: PrismACPListenerState,
        sessionCount: Int,
        nodeID: String,
        instanceID: String,
        advertisedCapabilities: [String]
    ) {
        self.enabled = enabled
        self.listenerState = listenerState
        self.sessionCount = sessionCount
        self.nodeID = nodeID
        self.instanceID = instanceID
        self.advertisedCapabilities = advertisedCapabilities
    }
}
