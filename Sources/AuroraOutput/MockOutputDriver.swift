import Foundation

public struct CapturedFrame: Equatable, Sendable {
    public var universe: UInt16
    public var data: [UInt8]
    public var timestamp: Date

    public init(universe: UInt16, data: [UInt8], timestamp: Date = Date()) {
        self.universe = universe
        self.data = data
        self.timestamp = timestamp
    }
}

/// Captures frames for unit tests.
public final class MockOutputDriver: OutputDriver, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public private(set) var isRunning = false
    public private(set) var frames: [CapturedFrame] = []
    private let lock = NSLock()

    public init(id: UUID = UUID(), name: String = "Mock") {
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
        let copy = Array(dmx)
        lock.lock()
        frames.append(CapturedFrame(universe: universe, data: copy))
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        frames.removeAll()
        lock.unlock()
    }

    public func frames(for universe: UInt16) -> [CapturedFrame] {
        lock.lock()
        defer { lock.unlock() }
        return frames.filter { $0.universe == universe }
    }
}
