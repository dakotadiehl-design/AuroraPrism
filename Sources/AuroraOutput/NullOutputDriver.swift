import AuroraModel
import Foundation

/// Discards all frames (offline / headless).
/// ST-02: Never reports as a successful physical/network output path.
public final class NullOutputDriver: OutputDriver, OutputHealthReporting, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let outputProtocol: UniverseProtocolHint = .none
    private let lock = NSLock()
    private var _isRunning = false
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    public init(id: UUID = UUID(), name: String = "Null") {
        self.id = id
        self.name = name
    }

    public func start() throws {
        lock.lock()
        _isRunning = true
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        _isRunning = false
        lock.unlock()
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        // Intentionally empty.
    }

    /// Null sink is never “healthy output” for operator chrome (ST-02).
    public func healthSnapshot() -> OutputHealthSnapshot {
        OutputHealthSnapshot(
            driverID: id,
            name: name,
            outputProtocol: outputProtocol,
            state: .disabled,
            target: "discard"
        )
    }
}
