import AuroraModel
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
    public let outputProtocol: UniverseProtocolHint
    private let lock = NSLock()
    private var _isRunning = false
    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }
    public private(set) var frames: [CapturedFrame] = []

    public init(
        id: UUID = UUID(),
        name: String = "Mock",
        outputProtocol: UniverseProtocolHint = .none
    ) {
        self.id = id
        self.name = name
        self.outputProtocol = outputProtocol
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
