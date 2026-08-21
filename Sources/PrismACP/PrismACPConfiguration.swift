import Foundation

public struct PrismACPConfiguration: Sendable, Equatable {
    public var enabled: Bool
    public var discoveryEnabled: Bool
    public var advertiseControl: Bool
    public var operatorNodeIDs: Set<String>
    public var blackoutClearNodeIDs: Set<String>
    public var webSocketPort: UInt16
    public var loopbackOnly: Bool
    public var applicationSupportDirectory: URL

    public init(
        enabled: Bool = false,
        discoveryEnabled: Bool = false,
        advertiseControl: Bool = false,
        operatorNodeIDs: Set<String> = [],
        blackoutClearNodeIDs: Set<String>? = nil,
        webSocketPort: UInt16 = 27421,
        loopbackOnly: Bool = true,
        applicationSupportDirectory: URL
    ) {
        self.enabled = enabled
        self.discoveryEnabled = discoveryEnabled
        self.advertiseControl = advertiseControl
        self.operatorNodeIDs = operatorNodeIDs
        self.blackoutClearNodeIDs = blackoutClearNodeIDs ?? []
        self.webSocketPort = webSocketPort
        self.loopbackOnly = loopbackOnly
        self.applicationSupportDirectory = applicationSupportDirectory
    }
}

public enum PrismACPListenerState: String, Sendable, Equatable {
    case stopped
    case starting
    case ready
    case failed
}
