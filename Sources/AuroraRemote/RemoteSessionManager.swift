import Foundation
import Security

public struct RemoteClientInfo: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var clientId: String
    public var displayName: String
    public var role: RemoteRole
    public var connectedAt: Date

    public init(
        id: UUID = UUID(),
        clientId: String,
        displayName: String,
        role: RemoteRole,
        connectedAt: Date = Date()
    ) {
        self.id = id
        self.clientId = clientId
        self.displayName = displayName
        self.role = role
        self.connectedAt = connectedAt
    }
}

public enum RemoteBindPolicy: String, Codable, Sendable, Equatable {
    /// Listen on all interfaces (explicit opt-in).
    case allInterfaces
    /// Prefer private/LAN (still may bind 0.0.0.0 with documentation; v1 marks intent).
    case privateLAN
    case loopbackOnly
}

public struct RemoteHostConfig: Equatable, Sendable {
    public var enabled: Bool
    public var pin: String
    public var maxClients: Int
    public var lockedToViewer: Bool
    public var port: UInt16
    public var maxCommandsPerSecond: Int
    public var maxAuthFailuresPerMinute: Int
    public var bindPolicy: RemoteBindPolicy

    public init(
        enabled: Bool = false,
        pin: String = "",
        maxClients: Int = 8,
        lockedToViewer: Bool = false,
        port: UInt16 = 8742,
        maxCommandsPerSecond: Int = 20,
        maxAuthFailuresPerMinute: Int = 10,
        bindPolicy: RemoteBindPolicy = .privateLAN
    ) {
        self.enabled = enabled
        self.pin = pin
        self.maxClients = max(1, maxClients)
        self.lockedToViewer = lockedToViewer
        self.port = port
        self.maxCommandsPerSecond = max(1, maxCommandsPerSecond)
        self.maxAuthFailuresPerMinute = max(1, maxAuthFailuresPerMinute)
        self.bindPolicy = bindPolicy
    }

    /// Cryptographically random 6-digit PIN (never "0000" as a product default) — P1-5.
    public static func generatePIN() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let n = bytes.reduce(0) { ($0 << 8) | Int($1) }
        let pin = abs(n) % 1_000_000
        return String(format: "%06d", pin)
    }
}

/// Auth, roles, lock, tokens, and command authorization (PR31/PR33 + review P1).
public final class RemoteSessionManager: @unchecked Sendable {
    private let lock = NSLock()
    private var config: RemoteHostConfig
    private var clients: [UUID: RemoteClientInfo] = [:]
    private var commandTimestamps: [UUID: [TimeInterval]] = [:]
    private var authFailureTimestamps: [TimeInterval] = []
    /// HTTP/web tokens → session id (P1-6).
    private var tokens: [String: UUID] = [:]

    public init(config: RemoteHostConfig = RemoteHostConfig()) {
        self.config = config
    }

    public var configSnapshot: RemoteHostConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    public var clientsSnapshot: [RemoteClientInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(clients.values).sorted { $0.connectedAt < $1.connectedAt }
    }

    public func updateConfig(_ config: RemoteHostConfig) {
        lock.lock()
        let pinChanged = self.config.pin != config.pin
        self.config = config
        if config.lockedToViewer {
            for id in clients.keys {
                clients[id]?.role = .viewer
            }
        }
        if pinChanged || !config.enabled {
            tokens.removeAll()
        }
        lock.unlock()
    }

    public func setLockedToViewer(_ locked: Bool) {
        lock.lock()
        config.lockedToViewer = locked
        if locked {
            for id in clients.keys {
                clients[id]?.role = .viewer
            }
        }
        lock.unlock()
    }

    public enum HelloResult: Equatable, Sendable {
        case welcome(RemoteClientInfo)
        case reject(String)
    }

    public func handleHello(
        clientId: String,
        protocolVersion: Int,
        pin: String?,
        displayName: String?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> HelloResult {
        lock.lock()
        defer { lock.unlock() }

        guard config.enabled else {
            return .reject("remote disabled")
        }
        guard protocolVersion == AuroraRemoteModule.protocolVersion else {
            return .reject("protocol version mismatch")
        }
        guard !config.pin.isEmpty else {
            return .reject("PIN not configured")
        }

        // Auth failure rate limit (P1-5).
        authFailureTimestamps = authFailureTimestamps.filter { now - $0 < 60 }
        if authFailureTimestamps.count >= config.maxAuthFailuresPerMinute {
            return .reject("too many failed attempts")
        }

        guard (pin ?? "") == config.pin else {
            authFailureTimestamps.append(now)
            return .reject("invalid PIN")
        }
        guard clients.count < config.maxClients else {
            return .reject("client limit reached")
        }

        let role: RemoteRole = config.lockedToViewer ? .viewer : .operatorRole
        let info = RemoteClientInfo(
            clientId: clientId,
            displayName: displayName ?? clientId,
            role: role
        )
        clients[info.id] = info
        return .welcome(info)
    }

    // MARK: - Tokens (P1-6)

    public func issueToken(for sessionId: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard clients[sessionId] != nil else { return nil }
        let token = UUID().uuidString
        tokens[token] = sessionId
        return token
    }

    public func sessionID(forToken token: String) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let sid = tokens[token], clients[sid] != nil else { return nil }
        return sid
    }

    public func invalidateToken(_ token: String) {
        lock.lock()
        tokens[token] = nil
        lock.unlock()
    }

    public func invalidateAllTokens() {
        lock.lock()
        tokens.removeAll()
        lock.unlock()
    }

    public func disconnect(sessionId: UUID) {
        lock.lock()
        clients[sessionId] = nil
        commandTimestamps[sessionId] = nil
        tokens = tokens.filter { $0.value != sessionId }
        lock.unlock()
    }

    @discardableResult
    public func kick(sessionId: UUID) -> Bool {
        lock.lock()
        let existed = clients.removeValue(forKey: sessionId) != nil
        commandTimestamps[sessionId] = nil
        tokens = tokens.filter { $0.value != sessionId }
        lock.unlock()
        return existed
    }

    public func kickAll(reason: String = "host kick") -> [UUID] {
        lock.lock()
        let ids = Array(clients.keys)
        clients.removeAll()
        commandTimestamps.removeAll()
        tokens.removeAll()
        lock.unlock()
        _ = reason
        return ids
    }

    public func authorize(sessionId: UUID, action: RemoteShowAction, now: TimeInterval = Date().timeIntervalSince1970) -> RemoteShowAction? {
        lock.lock()
        defer { lock.unlock() }
        guard let client = clients[sessionId] else { return nil }
        if client.role == .viewer { return nil }
        if config.lockedToViewer { return nil }
        guard RemoteCommandAllowList.isAllowed(action) else { return nil }
        var times = commandTimestamps[sessionId] ?? []
        times = times.filter { now - $0 < 1.0 }
        if times.count >= config.maxCommandsPerSecond {
            return nil
        }
        times.append(now)
        commandTimestamps[sessionId] = times
        return action
    }
}

public enum RemoteCommandAllowList {
    public static func isAllowed(_ action: RemoteShowAction) -> Bool {
        switch action {
        case .go, .stop, .back, .next,
             .fireCueIndex, .fireCue,
             .songNext, .songPrevious,
             .setProgrammerAttribute:
            return true
        }
    }
}
