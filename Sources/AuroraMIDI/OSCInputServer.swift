import Foundation
import Network

/// UDP OSC listener that decodes packets and emits mapped show actions (PR27).
public final class OSCInputServer: @unchecked Sendable {
    public let port: UInt16
    private let queue = DispatchQueue(label: "com.aurora.osc", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var _isRunning = false
    private var handler: (@Sendable (ShowAction, Float?) -> Void)?
    private var _lastError: String?

    public init(port: UInt16 = 9000) {
        self.port = port
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    public var lastError: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }

    public func setHandler(_ handler: @escaping @Sendable (ShowAction, Float?) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    public func start() throws {
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OSCError.invalidPort(port)
        }
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                self?.lock.lock()
                self?._lastError = err.localizedDescription
                self?._isRunning = false
                self?.lock.unlock()
            }
        }
        listener.start(queue: queue)
        lock.lock()
        self.listener = listener
        _isRunning = true
        _lastError = nil
        lock.unlock()
    }

    public func stop() {
        // Snapshot under lock; cancel outside so NW receive callbacks cannot re-enter deadlocked.
        lock.lock()
        let listenerToCancel = listener
        listener = nil
        _isRunning = false
        lock.unlock()
        listenerToCancel?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            if let content {
                self?.handle(packet: content)
            }
            if error == nil {
                self?.receive(on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    /// Test hook: inject a packet without UDP.
    public func handle(packet: Data) {
        let messages = OSCParser.parse(packet: packet)
        lock.lock()
        let handler = self.handler
        lock.unlock()
        for message in messages {
            if let mapped = OSCAddressMap.action(for: message) {
                handler?(mapped.0, mapped.value)
            }
        }
    }
}

public enum OSCError: Error, Equatable, Sendable {
    case invalidPort(UInt16)
}
