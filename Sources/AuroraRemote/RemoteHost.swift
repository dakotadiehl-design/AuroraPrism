import Foundation
import Network

/// Lightweight TCP host: newline-delimited JSON protocol messages (PR31).
/// Web UI (PR32) can speak the same codec over HTTP/WebSocket adapters.
public final class RemoteHost: @unchecked Sendable {
    public let sessions: RemoteSessionManager
    private let queue = DispatchQueue(label: "com.aurora.remote.host", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var sessionByConnection: [ObjectIdentifier: UUID] = [:]
    private var _isRunning = false
    private var actionHandler: (@Sendable (RemoteShowAction) -> Void)?
    private var snapshotProvider: (@Sendable () -> RemoteSnapshot)?

    public init(sessions: RemoteSessionManager = RemoteSessionManager()) {
        self.sessions = sessions
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    public func setActionHandler(_ handler: @escaping @Sendable (RemoteShowAction) -> Void) {
        lock.lock()
        actionHandler = handler
        lock.unlock()
    }

    public func setSnapshotProvider(_ provider: @escaping @Sendable () -> RemoteSnapshot) {
        lock.lock()
        snapshotProvider = provider
        lock.unlock()
    }

    public func start() throws {
        let config = sessions.configSnapshot
        guard config.enabled else {
            throw RemoteHostError.disabled
        }
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw RemoteHostError.invalidPort
        }
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.lock.lock()
                self?._isRunning = false
                self?.lock.unlock()
            }
        }
        listener.start(queue: queue)
        lock.lock()
        self.listener = listener
        _isRunning = true
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        listener?.cancel()
        listener = nil
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        sessionByConnection.removeAll()
        _isRunning = false
        lock.unlock()
        _ = sessions.kickAll()
    }

    /// Inject a decoded client message for tests (no network).
    public func handle(sessionId: UUID?, message: RemoteClientMessage) -> RemoteServerMessage? {
        switch message {
        case .hello(let clientId, let protocolVersion, let pin, let displayName):
            switch sessions.handleHello(
                clientId: clientId,
                protocolVersion: protocolVersion,
                pin: pin,
                displayName: displayName
            ) {
            case .welcome(let info):
                return .welcome(
                    sessionId: info.id,
                    role: info.role,
                    protocolVersion: AuroraRemoteModule.protocolVersion
                )
            case .reject(let reason):
                return .reject(reason: reason)
            }
        case .command(let action):
            guard let sessionId,
                  let authorized = sessions.authorize(sessionId: sessionId, action: action)
            else {
                return .reject(reason: "not authorized")
            }
            lock.lock()
            let handler = actionHandler
            lock.unlock()
            handler?(authorized)
            return nil
        case .ping:
            return .pong
        }
    }

    public func broadcastSnapshot() {
        lock.lock()
        let provider = snapshotProvider
        let conns = connections
        lock.unlock()
        guard let provider else { return }
        let base = provider()
        for (sessionId, conn) in conns {
            let role = sessions.clientsSnapshot.first(where: { $0.id == sessionId })?.role ?? .viewer
            var snap = base
            snap.role = role
            snap.locked = sessions.configSnapshot.lockedToViewer
            if let data = try? RemoteCodec.encodeServer(.snapshot(snap)) {
                sendLine(data, on: conn)
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveLines(on: connection, buffer: Data(), sessionId: nil)
    }

    private func receiveLines(on connection: NWConnection, buffer: Data, sessionId: UUID?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let content { buf.append(content) }
            var currentSession = sessionId

            while let range = buf.range(of: Data([0x0A])) {
                let line = buf.subdata(in: buf.startIndex..<range.lowerBound)
                buf.removeSubrange(buf.startIndex...range.lowerBound)
                if line.isEmpty { continue }
                if let msg = try? RemoteCodec.decodeClient(line) {
                    if case .hello = msg {
                        if let response = self.handle(sessionId: nil, message: msg),
                           case .welcome(let sid, _, _) = response {
                            currentSession = sid
                            self.lock.lock()
                            self.connections[sid] = connection
                            self.sessionByConnection[ObjectIdentifier(connection)] = sid
                            self.lock.unlock()
                            if let data = try? RemoteCodec.encodeServer(response) {
                                self.sendLine(data, on: connection)
                            }
                            // Send initial snapshot
                            self.broadcastSnapshot()
                        } else if let response = self.handle(sessionId: nil, message: msg),
                                  let data = try? RemoteCodec.encodeServer(response) {
                            self.sendLine(data, on: connection)
                            connection.cancel()
                            return
                        }
                    } else if let response = self.handle(sessionId: currentSession, message: msg),
                              let data = try? RemoteCodec.encodeServer(response) {
                        self.sendLine(data, on: connection)
                    }
                }
            }

            if isComplete || error != nil {
                if let sid = currentSession {
                    self.sessions.disconnect(sessionId: sid)
                    self.lock.lock()
                    self.connections[sid] = nil
                    self.lock.unlock()
                }
                connection.cancel()
                return
            }
            self.receiveLines(on: connection, buffer: buf, sessionId: currentSession)
        }
    }

    private func sendLine(_ data: Data, on connection: NWConnection) {
        var payload = data
        payload.append(0x0A)
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }
}

public enum RemoteHostError: Error, Equatable, Sendable {
    case disabled
    case invalidPort
}
