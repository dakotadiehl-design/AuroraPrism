import Foundation

/// Discards all frames (offline / headless).
public final class NullOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public private(set) var isRunning = false

    public init(id: UUID = UUID(), name: String = "Null") {
        self.id = id
        self.name = name
    }

    public func start() throws {
        isRunning = true
    }

    public func stop() {
        isRunning = false
    }

    public func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {
        // Intentionally empty.
    }
}
