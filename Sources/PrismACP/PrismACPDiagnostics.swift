import Foundation

public struct PrismACPDiagnostics: Sendable, Equatable {
    public var listenerState: PrismACPListenerState
    public var discoveryActive: Bool
    public var enrollmentAvailable: Bool
    public var enrollmentPort: UInt16?
    public var provisioningState: String?
    public var credentialExpiresAt: Date?
    public var renewalReadiness: String?
    public var authenticatedSessionCount: Int
    public var nodeID: String
    public var instanceID: String
    public var boundPort: UInt16?
    public var lastConnectionFailure: String?
    public var lastAuthenticationFailure: String?
    public var lastDisconnectReason: String?
    public var blocker: PrismACPBlocker?
    public var discoveryBlocker: PrismACPBlocker?

    public var isRunning: Bool { listenerState == .ready }

    public init(
        listenerState: PrismACPListenerState = .stopped,
        discoveryActive: Bool = false,
        enrollmentAvailable: Bool = false,
        enrollmentPort: UInt16? = nil,
        provisioningState: String? = nil,
        credentialExpiresAt: Date? = nil,
        renewalReadiness: String? = nil,
        authenticatedSessionCount: Int = 0,
        nodeID: String = "",
        instanceID: String = "",
        boundPort: UInt16? = nil,
        lastConnectionFailure: String? = nil,
        lastAuthenticationFailure: String? = nil,
        lastDisconnectReason: String? = nil,
        blocker: PrismACPBlocker? = nil,
        discoveryBlocker: PrismACPBlocker? = nil
    ) {
        self.listenerState = listenerState
        self.discoveryActive = discoveryActive
        self.enrollmentAvailable = enrollmentAvailable
        self.enrollmentPort = enrollmentPort
        self.provisioningState = provisioningState
        self.credentialExpiresAt = credentialExpiresAt
        self.renewalReadiness = renewalReadiness
        self.authenticatedSessionCount = authenticatedSessionCount
        self.nodeID = nodeID
        self.instanceID = instanceID
        self.boundPort = boundPort
        self.lastConnectionFailure = lastConnectionFailure
        self.lastAuthenticationFailure = lastAuthenticationFailure
        self.lastDisconnectReason = lastDisconnectReason
        self.blocker = blocker
        self.discoveryBlocker = discoveryBlocker
    }
}
