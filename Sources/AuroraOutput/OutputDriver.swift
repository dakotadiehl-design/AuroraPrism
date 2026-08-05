import Foundation

/// Pluggable DMX (or equivalent) output sink.
public protocol OutputDriver: AnyObject {
    var id: UUID { get }
    var name: String { get }
    var isRunning: Bool { get }
    func start() throws
    func stop()
    /// `universe` is the logical show universe number (not necessarily Art-Net net/subnet).
    func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>)
}
