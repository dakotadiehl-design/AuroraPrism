import Foundation

/// Shared remote client logic for web adapters and a future native Pad app (PR34 scaffold).
///
/// Does not open sockets itself — callers supply send/receive so iOS/macOS can use
/// URLSession, Network.framework, or tests with fakes.
public final class RemoteProtocolClient: @unchecked Sendable {
    public let clientId: String
    public let displayName: String
    public private(set) var sessionId: UUID?
    public private(set) var role: RemoteRole?
    public private(set) var lastSnapshot: RemoteSnapshot?

    private let lock = NSLock()

    public init(clientId: String = UUID().uuidString, displayName: String = "AuroraPad") {
        self.clientId = clientId
        self.displayName = displayName
    }

    public func makeHello(pin: String) throws -> Data {
        try RemoteCodec.encodeClient(
            .hello(
                clientId: clientId,
                protocolVersion: AuroraRemoteModule.protocolVersion,
                pin: pin,
                displayName: displayName
            )
        )
    }

    public func makeCommand(_ action: RemoteShowAction) throws -> Data {
        try RemoteCodec.encodeClient(.command(requestId: UUID().uuidString, action: action))
    }

    public func makePing() throws -> Data {
        try RemoteCodec.encodeClient(.ping)
    }

    /// Apply a server message; returns false if rejected/kicked.
    @discardableResult
    public func handleServerMessage(_ data: Data) throws -> Bool {
        let message = try RemoteCodec.decodeServer(data)
        lock.lock()
        defer { lock.unlock() }
        switch message {
        case .welcome(let sessionId, let role, _):
            self.sessionId = sessionId
            self.role = role
            return true
        case .reject, .kicked:
            sessionId = nil
            role = nil
            return false
        case .snapshot(let snap):
            lastSnapshot = snap
            role = snap.role
            return true
        case .pong:
            return true
        case .commandResult:
            return true
        }
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionId != nil
    }
}
