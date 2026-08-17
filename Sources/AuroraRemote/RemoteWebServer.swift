import Foundation
import Network

/// HTTP live-ops companion server (PR32). Uses the same `RemoteSessionManager` as the TCP host.
public final class RemoteWebServer: @unchecked Sendable {
    public let sessions: RemoteSessionManager
    public let port: UInt16
    private let queue = DispatchQueue(label: "com.aurora.remote.web", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var _listenerState: RemoteListenerState = .stopped
    private var actionHandler: (@Sendable (RemoteShowAction) -> Void)?
    private var snapshotProvider: (@Sendable () -> RemoteSnapshot)?
    private var stateHandler: (@Sendable (RemoteListenerState) -> Void)?
    private let indexHTML: Data
    /// Max HTTP body accepted.
    public static let maxBodyBytes = 64 * 1024
    /// Pre-delimiter header cap — disconnect if exceeded before `\r\n\r\n` (P2-13).
    public static let maxHeaderBytes = 16 * 1024
    /// Pre-delimiter TCP-style line buffer for any streaming receive helpers.
    public static let maxLineBufferBytes = 64 * 1024

    public init(
        sessions: RemoteSessionManager,
        port: UInt16 = 8743,
        indexHTML: Data? = nil
    ) {
        self.sessions = sessions
        self.port = port
        if let indexHTML {
            self.indexHTML = indexHTML
        } else if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Web"),
                  let data = try? Data(contentsOf: url) {
            self.indexHTML = data
        } else {
            self.indexHTML = Data("<html><body>Aurora Remote</body></html>".utf8)
        }
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

    public func setStateHandler(_ handler: @escaping @Sendable (RemoteListenerState) -> Void) {
        lock.lock()
        stateHandler = handler
        lock.unlock()
    }

    public func start() throws {
        guard sessions.configSnapshot.enabled else { throw RemoteHostError.disabled }
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
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw RemoteHostError.invalidPort }
        let bind = sessions.configSnapshot.bindPolicy
        if let host = RemoteSessionManager.listenerHost(for: bind) {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        }
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
        }
        let bindLabel: String
        if let host = RemoteSessionManager.listenerHost(for: bind) {
            bindLabel = "\(host):\(port)"
        } else {
            bindLabel = "0.0.0.0:\(port)"
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
        // Snapshot under lock; cancel outside so NW callbacks cannot re-enter deadlocked.
        lock.lock()
        let listenerToCancel = listener
        listener = nil
        lock.unlock()
        listenerToCancel?.cancel()
        sessions.invalidateAllTokens()
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

    /// Testable request handler (no sockets).
    public func handleHTTP(
        method: String,
        path: String,
        headers: [String: String],
        body: Data?
    ) -> (status: Int, contentType: String, body: Data) {
        let pathOnly = path.split(separator: "?").first.map(String.init) ?? path
        if method == "GET" && (pathOnly == "/" || pathOnly == "/index.html") {
            return (200, "text/html; charset=utf-8", indexHTML)
        }
        if method == "GET" && pathOnly == "/api/health" {
            return json(200, ["ok": true, "protocolVersion": AuroraRemoteModule.protocolVersion])
        }
        if method == "POST" && pathOnly == "/api/hello" {
            return handleHello(body: body ?? Data())
        }
        if method == "POST" && pathOnly == "/api/command" {
            return handleCommand(headers: headers, body: body ?? Data())
        }
        if method == "GET" && pathOnly == "/api/snapshot" {
            return handleSnapshot(headers: headers)
        }
        return json(404, ["error": "not found"])
    }

    // MARK: - Routes

    private func handleHello(body: Data) -> (Int, String, Data) {
        struct HelloBody: Decodable {
            var clientId: String
            var pin: String?
            var displayName: String?
            var protocolVersion: Int?
        }
        guard let hello = try? JSONDecoder().decode(HelloBody.self, from: body) else {
            return json(400, ["error": "bad body"])
        }
        // UI10-04: negotiate protocol version from client when provided.
        let clientVersion = hello.protocolVersion ?? AuroraRemoteModule.protocolVersion
        switch sessions.handleHello(
            clientId: hello.clientId,
            protocolVersion: clientVersion,
            pin: hello.pin,
            displayName: hello.displayName
        ) {
        case .welcome(let info):
            guard let token = sessions.issueToken(for: info.id) else {
                return json(500, ["error": "token issue failed"])
            }
            return json(200, [
                "token": token,
                "sessionId": info.id.uuidString,
                "role": info.role.rawValue,
                "protocolVersion": AuroraRemoteModule.protocolVersion,
            ])
        case .reject(let reason):
            return json(401, ["error": reason, "protocolVersion": AuroraRemoteModule.protocolVersion])
        }
    }

    private func handleCommand(headers: [String: String], body: Data) -> (Int, String, Data) {
        guard let sessionId = session(from: headers) else {
            return json(401, ["error": "unauthorized"])
        }
        struct CmdBody: Decodable {
            var requestId: String?
            var action: ActionBody
        }
        struct ActionBody: Decodable {
            var name: String
            var intValue: Int?
            var stringValue: String?
            var doubleValue: Double?
        }
        guard let cmd = try? JSONDecoder().decode(CmdBody.self, from: body),
              let action = mapAction(cmd.action.name, intValue: cmd.action.intValue, stringValue: cmd.action.stringValue, doubleValue: cmd.action.doubleValue)
        else {
            return json(400, ["error": "bad command"])
        }
        // UI10-01: require client-supplied requestId for at-most-once GO.
        guard let requestId = cmd.requestId, !requestId.isEmpty else {
            return json(400, ["error": "missing requestId", "ok": false])
        }
        switch sessions.reserveRequestId(sessionId: sessionId, requestId: requestId) {
        case .inFlight:
            return json(200, [
                "ok": false,
                "requestId": requestId,
                "duplicate": true,
                "reason": "in flight",
                "snapshotRevision": currentSnapshotRevision(),
            ])
        case .completed(let accepted, let reason, let rev):
            return json(200, [
                "ok": accepted,
                "requestId": requestId,
                "duplicate": true,
                "reason": reason as Any,
                "snapshotRevision": rev,
            ])
        case .execute:
            break
        }
        guard let authorized = sessions.authorize(sessionId: sessionId, action: action) else {
            let rev = currentSnapshotRevision()
            sessions.completeRequestId(sessionId: sessionId, requestId: requestId, accepted: false, reason: "not authorized", snapshotRevision: rev)
            return json(403, ["error": "not authorized", "requestId": requestId, "ok": false, "snapshotRevision": rev])
        }
        lock.lock()
        let handler = actionHandler
        lock.unlock()
        handler?(authorized)
        let rev = currentSnapshotRevision()
        sessions.completeRequestId(sessionId: sessionId, requestId: requestId, accepted: true, reason: nil, snapshotRevision: rev)
        return json(200, ["ok": true, "requestId": requestId, "duplicate": false, "snapshotRevision": rev])
    }

    private func handleSnapshot(headers: [String: String]) -> (Int, String, Data) {
        // REM-02: snapshot polling refreshes session activity.
        guard let sessionId = session(from: headers, touching: true) else {
            return json(401, ["error": "unauthorized"])
        }
        lock.lock()
        let provider = snapshotProvider
        lock.unlock()
        var snap = provider?() ?? RemoteSnapshot(showName: "Aurora", engineRunning: false)
        if let client = sessions.clientsSnapshot.first(where: { $0.id == sessionId }) {
            snap.role = client.role
        }
        snap.locked = sessions.configSnapshot.lockedToViewer
        guard let data = try? JSONEncoder().encode(snap) else {
            return json(500, ["error": "encode"])
        }
        return (200, "application/json", data)
    }

    private func mapAction(
        _ name: String,
        intValue: Int?,
        stringValue: String?,
        doubleValue: Double?
    ) -> RemoteShowAction? {
        switch name {
        case "go": return .go
        case "stop": return .stop
        case "back": return .back
        case "next": return .next
        case "fireCueIndex":
            guard let i = intValue else { return nil }
            return .fireCueIndex(i)
        case "fireCue":
            guard let s = stringValue, let id = UUID(uuidString: s) else { return nil }
            return .fireCue(id)
        case "songNext": return .songNext
        case "songPrevious": return .songPrevious
        case "setProgrammerAttribute":
            guard let attr = stringValue, let v = doubleValue else { return nil }
            return .setProgrammerAttribute(attribute: attr, value: v)
        default:
            return nil
        }
    }

    private func session(from headers: [String: String], touching: Bool = false) -> UUID? {
        let token = headers["X-Aurora-Token"] ?? headers["x-aurora-token"]
        guard let token else { return nil }
        if touching {
            return sessions.sessionID(forToken: token, touching: true)
        }
        return sessions.sessionID(forToken: token)
    }

    private func json(_ status: Int, _ object: [String: Any]) -> (Int, String, Data) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return (status, "application/json", data)
    }

    // MARK: - Minimal HTTP

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let content { buf.append(content) }
            // Pre-delimiter limit (P2-13): reject before finding header terminator.
            if buf.count > Self.maxHeaderBytes, buf.range(of: Data("\r\n\r\n".utf8)) == nil {
                connection.cancel()
                return
            }
            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: buf.startIndex..<headerEnd.lowerBound)
                if headerData.count > Self.maxHeaderBytes {
                    connection.cancel()
                    return
                }
                let headerText = String(data: headerData, encoding: .utf8) ?? ""
                let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
                guard let requestLine = lines.first else {
                    connection.cancel()
                    return
                }
                let parts = requestLine.split(separator: " ")
                let method = parts.count > 0 ? String(parts[0]) : "GET"
                let path = parts.count > 1 ? String(parts[1]) : "/"
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    if let colon = line.firstIndex(of: ":") {
                        let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        headers[key] = value
                    }
                }
                let lengthStr = headers["Content-Length"] ?? headers["content-length"] ?? "0"
                guard let contentLength = Int(lengthStr), contentLength >= 0, contentLength <= Self.maxBodyBytes else {
                    connection.cancel()
                    return
                }
                let bodyStart = headerEnd.upperBound
                var body = Data()
                if contentLength > 0 {
                    let available = buf.distance(from: bodyStart, to: buf.endIndex)
                    if available < contentLength {
                        if isComplete || error != nil {
                            connection.cancel()
                        } else {
                            self.receiveRequest(on: connection, buffer: buf)
                        }
                        return
                    }
                    let bodyEnd = buf.index(bodyStart, offsetBy: contentLength)
                    body = buf.subdata(in: bodyStart..<bodyEnd)
                }
                let response = self.handleHTTP(method: method, path: path, headers: headers, body: body.isEmpty ? nil : body)
                self.sendHTTP(response, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: buf)
        }
    }

    private func sendHTTP(_ response: (status: Int, contentType: String, body: Data), on connection: NWConnection) {
        let reason = response.status == 200 ? "OK" : "ERR"
        var header = "HTTP/1.1 \(response.status) \(reason)\r\n"
        header += "Content-Type: \(response.contentType)\r\n"
        header += "Content-Length: \(response.body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "\r\n"
        var payload = Data(header.utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
