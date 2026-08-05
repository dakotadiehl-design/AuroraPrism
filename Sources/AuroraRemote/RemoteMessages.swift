import Foundation

public enum RemoteRole: String, Codable, Sendable, Hashable {
    case viewer
    case operatorRole = "operator"
}

/// Live-ops actions allowed over remote (subset of desk control).
public enum RemoteShowAction: Equatable, Sendable, Codable {
    case go
    case stop
    case back
    case next
    case fireCueIndex(Int)
    case fireCue(UUID)
    case songNext
    case songPrevious
    case setProgrammerAttribute(attribute: String, value: Double)

    public var isMutating: Bool {
        true
    }
}

public struct RemoteSnapshot: Equatable, Sendable, Codable {
    public var protocolVersion: Int
    public var showName: String
    public var engineRunning: Bool
    public var cueIndex: Int
    public var cueName: String?
    public var songTitle: String?
    public var songEntryIndex: Int
    public var locked: Bool
    public var role: RemoteRole
    /// Compact first-universe active channel count for monitors.
    public var activeChannelCount: Int

    public init(
        protocolVersion: Int = AuroraRemoteModule.protocolVersion,
        showName: String,
        engineRunning: Bool,
        cueIndex: Int = -1,
        cueName: String? = nil,
        songTitle: String? = nil,
        songEntryIndex: Int = -1,
        locked: Bool = false,
        role: RemoteRole = .viewer,
        activeChannelCount: Int = 0
    ) {
        self.protocolVersion = protocolVersion
        self.showName = showName
        self.engineRunning = engineRunning
        self.cueIndex = cueIndex
        self.cueName = cueName
        self.songTitle = songTitle
        self.songEntryIndex = songEntryIndex
        self.locked = locked
        self.role = role
        self.activeChannelCount = activeChannelCount
    }
}

/// Wire messages (JSON object with `type` discriminant).
public enum RemoteClientMessage: Equatable, Sendable {
    case hello(clientId: String, protocolVersion: Int, pin: String?, displayName: String?)
    case command(RemoteShowAction)
    case ping
}

public enum RemoteServerMessage: Equatable, Sendable {
    case welcome(sessionId: UUID, role: RemoteRole, protocolVersion: Int)
    case reject(reason: String)
    case snapshot(RemoteSnapshot)
    case pong
    case kicked(reason: String)
}

public enum RemoteCodec {
    public static func encodeClient(_ message: RemoteClientMessage) throws -> Data {
        let enc = JSONEncoder()
        switch message {
        case .hello(let clientId, let protocolVersion, let pin, let displayName):
            return try enc.encode(HelloDTO(
                type: "hello",
                clientId: clientId,
                protocolVersion: protocolVersion,
                pin: pin,
                displayName: displayName
            ))
        case .command(let action):
            return try enc.encode(CommandDTO(type: "command", action: encodeAction(action)))
        case .ping:
            return try enc.encode(TypeOnlyDTO(type: "ping"))
        }
    }

    public static func decodeClient(_ data: Data) throws -> RemoteClientMessage {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let type = obj?["type"] as? String else {
            throw RemoteCodecError.missingType
        }
        switch type {
        case "hello":
            let dto = try JSONDecoder().decode(HelloDTO.self, from: data)
            return .hello(
                clientId: dto.clientId,
                protocolVersion: dto.protocolVersion,
                pin: dto.pin,
                displayName: dto.displayName
            )
        case "command":
            let dto = try JSONDecoder().decode(CommandDTO.self, from: data)
            return .command(try decodeAction(dto.action))
        case "ping":
            return .ping
        default:
            throw RemoteCodecError.unknownType(type)
        }
    }

    public static func encodeServer(_ message: RemoteServerMessage) throws -> Data {
        let enc = JSONEncoder()
        switch message {
        case .welcome(let sessionId, let role, let protocolVersion):
            return try enc.encode(WelcomeDTO(
                type: "welcome",
                sessionId: sessionId.uuidString,
                role: role.rawValue,
                protocolVersion: protocolVersion
            ))
        case .reject(let reason):
            return try enc.encode(RejectDTO(type: "reject", reason: reason))
        case .snapshot(let snap):
            return try enc.encode(SnapshotDTO(type: "snapshot", snapshot: snap))
        case .pong:
            return try enc.encode(TypeOnlyDTO(type: "pong"))
        case .kicked(let reason):
            return try enc.encode(RejectDTO(type: "kicked", reason: reason))
        }
    }

    public static func decodeServer(_ data: Data) throws -> RemoteServerMessage {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let type = obj?["type"] as? String else {
            throw RemoteCodecError.missingType
        }
        switch type {
        case "welcome":
            let dto = try JSONDecoder().decode(WelcomeDTO.self, from: data)
            guard let id = UUID(uuidString: dto.sessionId),
                  let role = RemoteRole(rawValue: dto.role)
            else { throw RemoteCodecError.invalidPayload }
            return .welcome(sessionId: id, role: role, protocolVersion: dto.protocolVersion)
        case "reject":
            let dto = try JSONDecoder().decode(RejectDTO.self, from: data)
            return .reject(reason: dto.reason)
        case "kicked":
            let dto = try JSONDecoder().decode(RejectDTO.self, from: data)
            return .kicked(reason: dto.reason)
        case "snapshot":
            let dto = try JSONDecoder().decode(SnapshotDTO.self, from: data)
            return .snapshot(dto.snapshot)
        case "pong":
            return .pong
        default:
            throw RemoteCodecError.unknownType(type)
        }
    }

    private static func encodeAction(_ action: RemoteShowAction) -> ActionDTO {
        switch action {
        case .go: return ActionDTO(name: "go")
        case .stop: return ActionDTO(name: "stop")
        case .back: return ActionDTO(name: "back")
        case .next: return ActionDTO(name: "next")
        case .fireCueIndex(let i): return ActionDTO(name: "fireCueIndex", intValue: i)
        case .fireCue(let id): return ActionDTO(name: "fireCue", stringValue: id.uuidString)
        case .songNext: return ActionDTO(name: "songNext")
        case .songPrevious: return ActionDTO(name: "songPrevious")
        case .setProgrammerAttribute(let attr, let value):
            return ActionDTO(name: "setProgrammerAttribute", stringValue: attr, doubleValue: value)
        }
    }

    private static func decodeAction(_ dto: ActionDTO) throws -> RemoteShowAction {
        switch dto.name {
        case "go": return .go
        case "stop": return .stop
        case "back": return .back
        case "next": return .next
        case "fireCueIndex":
            guard let i = dto.intValue else { throw RemoteCodecError.invalidPayload }
            return .fireCueIndex(i)
        case "fireCue":
            guard let s = dto.stringValue, let id = UUID(uuidString: s) else {
                throw RemoteCodecError.invalidPayload
            }
            return .fireCue(id)
        case "songNext": return .songNext
        case "songPrevious": return .songPrevious
        case "setProgrammerAttribute":
            guard let attr = dto.stringValue, let v = dto.doubleValue else {
                throw RemoteCodecError.invalidPayload
            }
            return .setProgrammerAttribute(attribute: attr, value: v)
        default:
            throw RemoteCodecError.unknownType(dto.name)
        }
    }
}

public enum RemoteCodecError: Error, Equatable, Sendable {
    case missingType
    case unknownType(String)
    case invalidPayload
}

// MARK: - DTOs

private struct TypeOnlyDTO: Codable {
    var type: String
}

private struct HelloDTO: Codable {
    var type: String
    var clientId: String
    var protocolVersion: Int
    var pin: String?
    var displayName: String?
}

private struct CommandDTO: Codable {
    var type: String
    var action: ActionDTO
}

private struct ActionDTO: Codable {
    var name: String
    var intValue: Int?
    var stringValue: String?
    var doubleValue: Double?
}

private struct WelcomeDTO: Codable {
    var type: String
    var sessionId: String
    var role: String
    var protocolVersion: Int
}

private struct RejectDTO: Codable {
    var type: String
    var reason: String
}

private struct SnapshotDTO: Codable {
    var type: String
    var snapshot: RemoteSnapshot
}
