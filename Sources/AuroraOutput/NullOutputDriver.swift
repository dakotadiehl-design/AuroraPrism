import AuroraModel
import Foundation

/// Discards all frames (offline / headless).
public final class NullOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let outputProtocol: UniverseProtocolHint = .local
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
}
