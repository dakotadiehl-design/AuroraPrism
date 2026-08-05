import Foundation
import AuroraModel

/// Driver operational state for status dots / diagnostics (P2-6).
public enum OutputDriverState: String, Codable, Sendable, Equatable {
    case disabled
    case starting
    case ready
    case degraded
    case failed
    case disconnected
}

/// First-class output health snapshot for UI and diagnostics.
public struct OutputHealthSnapshot: Equatable, Sendable, Identifiable {
    public var id: UUID { driverID }
    public var driverID: UUID
    public var name: String
    public var outputProtocol: UniverseProtocolHint
    public var state: OutputDriverState
    public var target: String
    public var lastError: String?
    public var lastSuccessAt: Date?
    public var packetsSent: UInt64
    public var packetsDropped: UInt64
    public var activeUniverses: [UInt16]
    public var updatedAt: Date

    public init(
        driverID: UUID,
        name: String,
        outputProtocol: UniverseProtocolHint,
        state: OutputDriverState,
        target: String = "",
        lastError: String? = nil,
        lastSuccessAt: Date? = nil,
        packetsSent: UInt64 = 0,
        packetsDropped: UInt64 = 0,
        activeUniverses: [UInt16] = [],
        updatedAt: Date = Date()
    ) {
        self.driverID = driverID
        self.name = name
        self.outputProtocol = outputProtocol
        self.state = state
        self.target = target
        self.lastError = lastError
        self.lastSuccessAt = lastSuccessAt
        self.packetsSent = packetsSent
        self.packetsDropped = packetsDropped
        self.activeUniverses = activeUniverses
        self.updatedAt = updatedAt
    }
}

/// Optional health reporting for drivers.
public protocol OutputHealthReporting: AnyObject {
    func healthSnapshot() -> OutputHealthSnapshot
}
