import Foundation

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

public struct RemoteHostConfig: Equatable, Sendable {
    public var enabled: Bool
    public var pin: String
    public var maxClients: Int
    /// When true, only viewer role is granted (Mac lock).
    public var lockedToViewer: Bool
    public var port: UInt16
    /// Max authorized commands per session per rolling second (PR33).
    public var maxCommandsPerSecond: Int

    public init(
        enabled: Bool = false,
        pin: String = "0000",
        maxClients: Int = 8,
        lockedToViewer: Bool = false,
        port: UInt16 = 8742,
        maxCommandsPerSecond: Int = 20
    ) {
        self.enabled = enabled
        self.pin = pin
        self.maxClients = max(1, maxClients)
        self.lockedToViewer = lockedToViewer
        self.port = port
        self.maxCommandsPerSecond = max(1, maxCommandsPerSecond)
    }
}

/// Auth, roles, lock, and command authorization for remote clients (PR31/PR33).
public final class RemoteSessionManager: @unchecked Sendable {
    private let lock = NSLock()
    private var config: RemoteHostConfig
    private var clients: [UUID: RemoteClientInfo] = [:]
    private var commandTimestamps: [UUID: [TimeInterval]] = [:]

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
        self.config = config
        if config.lockedToViewer {
            for id in clients.keys {
                clients[id]?.role = .viewer
            }
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
        displayName: String?
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
        guard (pin ?? "") == config.pin else {
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

    public func disconnect(sessionId: UUID) {
        lock.lock()
        clients[sessionId] = nil
        commandTimestamps[sessionId] = nil
        lock.unlock()
    }

    @discardableResult
    public func kick(sessionId: UUID) -> Bool {
        lock.lock()
        let existed = clients.removeValue(forKey: sessionId) != nil
        commandTimestamps[sessionId] = nil
        lock.unlock()
        return existed
    }

    public func kickAll(reason: String = "host kick") -> [UUID] {
        lock.lock()
        let ids = Array(clients.keys)
        clients.removeAll()
        commandTimestamps.removeAll()
        lock.unlock()
        _ = reason
        return ids
    }

    /// Returns authorized action or nil if forbidden / rate-limited.
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
