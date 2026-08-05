import Foundation
import Network

/// HTTP live-ops companion server (PR32). Uses the same `RemoteSessionManager` as the TCP host.
public final class RemoteWebServer: @unchecked Sendable {
    public let sessions: RemoteSessionManager
    public let port: UInt16
    private let queue = DispatchQueue(label: "com.aurora.remote.web", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var _isRunning = false
    private var actionHandler: (@Sendable (RemoteShowAction) -> Void)?
    private var snapshotProvider: (@Sendable () -> RemoteSnapshot)?
    private let indexHTML: Data
    /// Max HTTP body accepted (P2-9).
    public static let maxBodyBytes = 64 * 1024
    public static let maxHeaderBytes = 16 * 1024

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
        guard sessions.configSnapshot.enabled else { throw RemoteHostError.disabled }
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw RemoteHostError.invalidPort }
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
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
        _isRunning = false
        lock.unlock()
        sessions.invalidateAllTokens()
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
        }
        guard let hello = try? JSONDecoder().decode(HelloBody.self, from: body) else {
            return json(400, ["error": "bad body"])
        }
        switch sessions.handleHello(
            clientId: hello.clientId,
            protocolVersion: AuroraRemoteModule.protocolVersion,
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
            ])
        case .reject(let reason):
            return json(401, ["error": reason])
        }
    }

    private func handleCommand(headers: [String: String], body: Data) -> (Int, String, Data) {
        guard let sessionId = session(from: headers) else {
            return json(401, ["error": "unauthorized"])
        }
        struct CmdBody: Decodable {
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
        guard let authorized = sessions.authorize(sessionId: sessionId, action: action) else {
            return json(403, ["error": "not authorized"])
        }
        lock.lock()
        let handler = actionHandler
        lock.unlock()
        handler?(authorized)
        return json(200, ["ok": true])
    }

    private func handleSnapshot(headers: [String: String]) -> (Int, String, Data) {
        guard let sessionId = session(from: headers) else {
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

    private func session(from headers: [String: String]) -> UUID? {
        let token = headers["X-Aurora-Token"] ?? headers["x-aurora-token"]
        guard let token else { return nil }
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
            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: buf.startIndex..<headerEnd.lowerBound)
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
                if headerData.count > Self.maxHeaderBytes {
                    connection.cancel()
                    return
                }
                let lengthStr = headers["Content-Length"] ?? headers["content-length"] ?? "0"
                guard let contentLength = Int(lengthStr), contentLength >= 0, contentLength <= Self.maxBodyBytes else {
                    connection.cancel()
                    return
                }
                var bodyStart = headerEnd.upperBound
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
