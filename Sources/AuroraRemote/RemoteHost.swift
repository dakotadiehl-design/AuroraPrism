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
    private var _listenerState: RemoteListenerState = .stopped
    private var actionHandler: (@Sendable (RemoteShowAction) -> Void)?
    private var snapshotProvider: (@Sendable () -> RemoteSnapshot)?
    private var stateHandler: (@Sendable (RemoteListenerState) -> Void)?

    public init(sessions: RemoteSessionManager = RemoteSessionManager()) {
        self.sessions = sessions
    }

    /// True only when the NWListener is actually `.ready` (REM-01).
    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _listenerState.isReady
    }

    public var listenerState: RemoteListenerState {
        lock.lock()
        defer { lock.unlock() }
        return _listenerState
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

    /// REM-01: notify when listener reaches ready / failed / stopped.
    public func setStateHandler(_ handler: @escaping @Sendable (RemoteListenerState) -> Void) {
        lock.lock()
        stateHandler = handler
        lock.unlock()
    }

    public func start() throws {
        let config = sessions.configSnapshot
        guard config.enabled else {
            throw RemoteHostError.disabled
        }
        lock.lock()
        if case .ready = _listenerState {
            lock.unlock()
            return
        }
        if case .starting = _listenerState {
            lock.unlock()
            return
        }
        lock.unlock()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: config.port) else {
            throw RemoteHostError.invalidPort
        }
        // Enforce bind policy (P2-11).
        if let host = RemoteSessionManager.listenerHost(for: config.bindPolicy) {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        }
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        let bindLabel: String
        if let host = RemoteSessionManager.listenerHost(for: config.bindPolicy) {
            bindLabel = "\(host):\(config.port)"
        } else {
            bindLabel = "0.0.0.0:\(config.port)"
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.setListenerState(.ready(boundEndpoint: bindLabel))
            case .failed(let error):
                self.setListenerState(.failed(error.localizedDescription))
            case .cancelled:
                self.setListenerState(.stopped)
            default:
                break
            }
        }
        setListenerState(.starting)
        listener.start(queue: queue)
        lock.lock()
        self.listener = listener
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
        lock.unlock()
        _ = sessions.kickAll()
        setListenerState(.stopped)
    }

    private func setListenerState(_ state: RemoteListenerState) {
        lock.lock()
        _listenerState = state
        let handler = stateHandler
        lock.unlock()
        handler?(state)
    }

    private func currentSnapshotRevision() -> UInt64 {
        lock.lock()
        let provider = snapshotProvider
        lock.unlock()
        return provider?().snapshotRevision ?? 0
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
        case .command(let requestId, let action):
            guard let sessionId else {
                return .commandResult(requestId: requestId, accepted: false, reason: "no session", snapshotRevision: 0)
            }
            guard !requestId.isEmpty else {
                return .commandResult(requestId: requestId, accepted: false, reason: "missing requestId", snapshotRevision: 0)
            }
            sessions.touch(sessionId: sessionId)
            switch sessions.reserveRequestId(sessionId: sessionId, requestId: requestId) {
            case .inFlight:
                return .commandResult(requestId: requestId, accepted: false, reason: "in flight", snapshotRevision: currentSnapshotRevision())
            case .completed(let accepted, let reason, let rev):
                return .commandResult(requestId: requestId, accepted: accepted, reason: reason, snapshotRevision: rev)
            case .execute:
                break
            }
            guard let authorized = sessions.authorize(sessionId: sessionId, action: action) else {
                let rev = currentSnapshotRevision()
                sessions.completeRequestId(sessionId: sessionId, requestId: requestId, accepted: false, reason: "not authorized", snapshotRevision: rev)
                return .commandResult(requestId: requestId, accepted: false, reason: "not authorized", snapshotRevision: rev)
            }
            lock.lock()
            let handler = actionHandler
            lock.unlock()
            handler?(authorized)
            // REM-05: return meaningful revision after dispatch (sync actions only).
            let rev = currentSnapshotRevision()
            sessions.completeRequestId(sessionId: sessionId, requestId: requestId, accepted: true, reason: nil, snapshotRevision: rev)
            return .commandResult(requestId: requestId, accepted: true, reason: nil, snapshotRevision: rev)
        case .ping:
            if let sessionId {
                sessions.touch(sessionId: sessionId)
            }
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
            // Pre-delimiter line buffer limit (P2-13).
            if buf.count > 64 * 1024, buf.range(of: Data([0x0A])) == nil {
                connection.cancel()
                return
            }
            var currentSession = sessionId

            while let range = buf.range(of: Data([0x0A])) {
                let line = buf.subdata(in: buf.startIndex..<range.lowerBound)
                buf.removeSubrange(buf.startIndex...range.lowerBound)
                if line.isEmpty { continue }
                if let msg = try? RemoteCodec.decodeClient(line) {
                    if case .hello = msg {
                        // Evaluate authentication exactly once (P1-7).
                        let response = self.handle(sessionId: nil, message: msg)
                        if case .welcome(let sid, _, _)? = response {
                            currentSession = sid
                            self.lock.lock()
                            self.connections[sid] = connection
                            self.sessionByConnection[ObjectIdentifier(connection)] = sid
                            self.lock.unlock()
                            if let data = try? RemoteCodec.encodeServer(response!) {
                                self.sendLine(data, on: connection)
                            }
                            self.broadcastSnapshot()
                        } else if let response, let data = try? RemoteCodec.encodeServer(response) {
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
