import Foundation
import AuroraModel

/// Pluggable DMX (or equivalent) output sink.
public protocol OutputDriver: AnyObject {
    var id: UUID { get }
    var name: String { get }
    var isRunning: Bool { get }
    /// Which universe protocol this driver implements (P1-10 routing).
    var outputProtocol: UniverseProtocolHint { get }
    func start() throws
    func stop()
    /// `universe` is the logical show universe number (not necessarily Art-Net net/subnet).
    func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>)
}

public extension OutputDriver {
    /// Default: accept any / untyped (Mock, tests).
    var outputProtocol: UniverseProtocolHint { .none }
}
