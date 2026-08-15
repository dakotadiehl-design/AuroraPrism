import Foundation
import Security

public struct RemoteClientInfo: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var clientId: String
    public var displayName: String
    public var role: RemoteRole
    public var connectedAt: Date
    /// Last activity for expiry / reconnect (P2-12).
    public var lastSeenAt: Date

    public init(
        id: UUID = UUID(),
        clientId: String,
        displayName: String,
        role: RemoteRole,
        connectedAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.clientId = clientId
        self.displayName = displayName
        self.role = role
        self.connectedAt = connectedAt
        self.lastSeenAt = lastSeenAt
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
    /// Inactive client TTL seconds (P2-12).
    public var sessionIdleTTL: TimeInterval

    public init(
        enabled: Bool = false,
        pin: String = "",
        maxClients: Int = 8,
        lockedToViewer: Bool = false,
        port: UInt16 = 8742,
        maxCommandsPerSecond: Int = 20,
        maxAuthFailuresPerMinute: Int = 10,
        bindPolicy: RemoteBindPolicy = .loopbackOnly,
        sessionIdleTTL: TimeInterval = 120
    ) {
        self.enabled = enabled
        self.pin = pin
        self.maxClients = max(1, maxClients)
        self.lockedToViewer = lockedToViewer
        self.port = port
        self.maxCommandsPerSecond = max(1, maxCommandsPerSecond)
        self.maxAuthFailuresPerMinute = max(1, maxAuthFailuresPerMinute)
        self.bindPolicy = bindPolicy
        self.sessionIdleTTL = max(15, sessionIdleTTL)
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
    /// UI-10 A6 / REM-04: per-session requestId → in-flight or completed (atomic reserve + ordered retention).
    private enum RequestIdRecord: Equatable {
        case inFlight
        case completed(accepted: Bool, reason: String?, snapshotRevision: UInt64)
    }
    private struct SessionRequestCache {
        var byId: [String: RequestIdRecord] = [:]
        /// Insertion order for deterministic eviction of completed IDs.
        var order: [String] = []
    }
    private var recentRequestResults: [UUID: SessionRequestCache] = [:]
    private let maxRecentRequestIds = 64

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

        // Reclaim idle sessions before enforcing maxClients (P2-12).
        reclaimInactiveLocked(now: now)

        // Reuse existing session for same clientId (browser reload).
        if let existing = clients.values.first(where: { $0.clientId == clientId }) {
            var updated = existing
            updated.lastSeenAt = Date(timeIntervalSince1970: now)
            updated.displayName = displayName ?? existing.displayName
            if config.lockedToViewer {
                updated.role = .viewer
            }
            clients[updated.id] = updated
            return .welcome(updated)
        }

        guard clients.count < config.maxClients else {
            return .reject("client limit reached")
        }

        let role: RemoteRole = config.lockedToViewer ? .viewer : .operatorRole
        let info = RemoteClientInfo(
            clientId: clientId,
            displayName: displayName ?? clientId,
            role: role,
            lastSeenAt: Date(timeIntervalSince1970: now)
        )
        clients[info.id] = info
        return .welcome(info)
    }

    /// Drop clients idle longer than `sessionIdleTTL`.
    @discardableResult
    public func reclaimInactive(now: TimeInterval = Date().timeIntervalSince1970) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return reclaimInactiveLocked(now: now)
    }

    private func reclaimInactiveLocked(now: TimeInterval) -> [UUID] {
        let ttl = config.sessionIdleTTL
        let stale = clients.filter { now - $0.value.lastSeenAt.timeIntervalSince1970 > ttl }.map(\.key)
        for id in stale {
            clients[id] = nil
            commandTimestamps[id] = nil
            recentRequestResults[id] = nil
            tokens = tokens.filter { $0.value != id }
        }
        return stale
    }

    public func touch(sessionId: UUID, now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        clients[sessionId]?.lastSeenAt = Date(timeIntervalSince1970: now)
        lock.unlock()
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

    /// REM-02: resolve token and optionally refresh session activity.
    public func sessionID(forToken token: String, touching: Bool) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard let sid = tokens[token], clients[sid] != nil else { return nil }
        if touching {
            clients[sid]?.lastSeenAt = Date()
        }
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
        recentRequestResults[sessionId] = nil
        tokens = tokens.filter { $0.value != sessionId }
        lock.unlock()
    }

    @discardableResult
    public func kick(sessionId: UUID) -> Bool {
        lock.lock()
        let existed = clients.removeValue(forKey: sessionId) != nil
        commandTimestamps[sessionId] = nil
        recentRequestResults[sessionId] = nil
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
        recentRequestResults.removeAll()
        lock.unlock()
        _ = reason
        return ids
    }

    public func authorize(sessionId: UUID, action: RemoteShowAction, now: TimeInterval = Date().timeIntervalSince1970) -> RemoteShowAction? {
        lock.lock()
        defer { lock.unlock() }
        guard var client = clients[sessionId] else { return nil }
        client.lastSeenAt = Date(timeIntervalSince1970: now)
        clients[sessionId] = client
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

    public enum RequestIdReservation: Equatable, Sendable {
        /// First caller — may execute the action.
        case execute
        /// Duplicate while first is still executing.
        case inFlight
        /// Prior completed result (at-most-once reply).
        case completed(accepted: Bool, reason: String?, snapshotRevision: UInt64)
    }

    /// Atomically reserve a requestId (UI10-02 / REM-04). Only `.execute` may run the handler.
    public func reserveRequestId(sessionId: UUID, requestId: String) -> RequestIdReservation {
        lock.lock()
        defer { lock.unlock() }
        guard !requestId.isEmpty else {
            return .completed(accepted: false, reason: "missing requestId", snapshotRevision: 0)
        }
        var cache = recentRequestResults[sessionId] ?? SessionRequestCache()
        if let prior = cache.byId[requestId] {
            switch prior {
            case .inFlight:
                return .inFlight
            case .completed(let accepted, let reason, let rev):
                return .completed(accepted: accepted, reason: reason, snapshotRevision: rev)
            }
        }
        cache.byId[requestId] = .inFlight
        cache.order.append(requestId)
        trimRequestCacheLocked(&cache)
        recentRequestResults[sessionId] = cache
        return .execute
    }

    /// Complete a previously reserved requestId with its final result (and revision).
    public func completeRequestId(
        sessionId: UUID,
        requestId: String,
        accepted: Bool,
        reason: String?,
        snapshotRevision: UInt64 = 0
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !requestId.isEmpty else { return }
        var cache = recentRequestResults[sessionId] ?? SessionRequestCache()
        cache.byId[requestId] = .completed(accepted: accepted, reason: reason, snapshotRevision: snapshotRevision)
        if !cache.order.contains(requestId) {
            cache.order.append(requestId)
        }
        trimRequestCacheLocked(&cache)
        recentRequestResults[sessionId] = cache
    }

    /// Legacy helpers kept for tests/call sites mid-migration.
    public func takeRequestIdIfNew(sessionId: UUID, requestId: String) -> (accepted: Bool, reason: String?)? {
        switch reserveRequestId(sessionId: sessionId, requestId: requestId) {
        case .execute:
            return nil
        case .inFlight:
            return (false, "in flight")
        case .completed(let accepted, let reason, _):
            return (accepted, reason)
        }
    }

    public func rememberRequestId(sessionId: UUID, requestId: String, accepted: Bool, reason: String?) {
        completeRequestId(sessionId: sessionId, requestId: requestId, accepted: accepted, reason: reason, snapshotRevision: 0)
    }

    /// REM-04: evict oldest *completed* IDs only; never evict in-flight.
    private func trimRequestCacheLocked(_ cache: inout SessionRequestCache) {
        while cache.order.count > maxRecentRequestIds {
            guard let oldest = cache.order.first else { break }
            if case .inFlight = cache.byId[oldest] {
                // Cannot drop in-flight; stop if only in-flight remain beyond cap.
                if cache.order.allSatisfy({
                    if case .inFlight = cache.byId[$0] { return true }
                    return false
                }) {
                    break
                }
                // Move oldest in-flight to end of consideration by rotating once.
                cache.order.removeFirst()
                cache.order.append(oldest)
                continue
            }
            cache.order.removeFirst()
            cache.byId[oldest] = nil
        }
    }

    /// NWParameters host restriction from bind policy (P2-11 / REM-07).
    /// `privateLAN` and `allInterfaces` both bind all interfaces today — UI must not claim private-only.
    public static func listenerHost(for policy: RemoteBindPolicy) -> String? {
        switch policy {
        case .loopbackOnly: return "127.0.0.1"
        case .privateLAN, .allInterfaces: return nil // all interfaces
        }
    }
}

public enum RemoteCommandAllowList {
    public static func isAllowed(_ action: RemoteShowAction) -> Bool {
        switch action {
        case .go, .stop, .back, .next,
             .fireCueIndex, .fireCue,
             .songNext, .songPrevious,
             .masterIntensity, .blackout, .blackoutOff, .toggleBlackout:
            return true
        case .setProgrammerAttribute:
            // UI-10 A8: remote Programmer out of scope.
            return false
        }
    }
}
