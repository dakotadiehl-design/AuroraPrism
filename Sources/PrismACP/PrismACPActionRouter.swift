import AuroraACP
import Foundation

public struct PrismACPAction: Sendable, Equatable {
    public var name: String
    public var commandID: String
    public var originNodeID: String
    public var originInstanceID: String
    public var originPrincipal: String?
    public var originSessionID: String?
    public var idempotencyKey: String?
    public var parameter: String?
    public var value: Double?
    public var preconditions: [ACPPrecondition]
    public var freshnessRejection: String?

    public init(
        name: String,
        commandID: String = UUID().uuidString.lowercased(),
        originNodeID: String = UUID().uuidString.lowercased(),
        originInstanceID: String = UUID().uuidString.lowercased(),
        originPrincipal: String? = nil,
        originSessionID: String? = nil,
        idempotencyKey: String? = nil,
        parameter: String? = nil,
        value: Double? = nil,
        preconditions: [ACPPrecondition] = [],
        freshnessRejection: String? = nil
    ) {
        self.name = name
        self.commandID = commandID
        self.originNodeID = originNodeID
        self.originInstanceID = originInstanceID
        self.originPrincipal = originPrincipal
        self.originSessionID = originSessionID
        self.idempotencyKey = idempotencyKey
        self.parameter = parameter
        self.value = value
        self.preconditions = preconditions
        self.freshnessRejection = freshnessRejection
    }
}

public enum PrismACPActionRouterError: Error, Equatable {
    case mutationsNotAdvertised
    case unavailable(String)
    case preconditionFailed
    case unsupported
    case rejected(String)
}

public struct PrismACPAdmissionResult: Sendable, Equatable {
    public var disposition: String
    public var storageKey: String?
    public var reason: String?
    public var resultingEpoch: UInt64?
    public var resultingRevision: UInt64?
    public var result: [String: AnySendable]

    public init(
        disposition: String,
        storageKey: String? = nil,
        reason: String? = nil,
        resultingEpoch: UInt64? = nil,
        resultingRevision: UInt64? = nil,
        result: [String: AnySendable] = [:]
    ) {
        self.disposition = disposition
        self.storageKey = storageKey
        self.reason = reason
        self.resultingEpoch = resultingEpoch
        self.resultingRevision = resultingRevision
        self.result = result
    }
}

public struct PrismACPControlRequest: Sendable, Equatable {
    public var action: PrismACPAction

    public init(action: PrismACPAction) {
        self.action = action
    }

    public func evaluatePreconditions(
        authorityEpoch: UInt64,
        revision: UInt64,
        showID: String?,
        currentCueID: String?
    ) throws {
        try ACPStateRevision.evaluatePreconditions(
            action.preconditions,
            authorityEpoch: authorityEpoch,
            revision: revision,
            showID: showID,
            currentCueID: currentCueID
        )
    }
}

public struct PrismACPControlResult: Sendable, Equatable {
    public var disposition: String
    public var reason: String?
    public var resultingEpoch: UInt64?
    public var resultingRevision: UInt64?

    public init(
        disposition: String,
        reason: String? = nil,
        resultingEpoch: UInt64? = nil,
        resultingRevision: UInt64? = nil
    ) {
        self.disposition = disposition
        self.reason = reason
        self.resultingEpoch = resultingEpoch
        self.resultingRevision = resultingRevision
    }
}

public struct PrismACPActionRouter: Sendable {
    public var advertiseControl: Bool

    public init(advertiseControl: Bool = false) {
        self.advertiseControl = advertiseControl
    }

    public func advertisedCapabilities() -> [String] {
        guard advertiseControl else { return [] }
        return ["performance.go", "performance.fire_cue", "output.master", "blackoutOn", "blackoutOff"]
    }

    public func submit(_ action: PrismACPAction) throws {
        guard advertiseControl else {
            throw PrismACPActionRouterError.mutationsNotAdvertised
        }
        try Self.validate(action)
    }

    public static func validate(_ action: PrismACPAction) throws {
        guard ["performance.go", "performance.fire_cue", "output.master", "blackoutOn", "blackoutOff"].contains(action.name) else {
            throw PrismACPActionRouterError.unsupported
        }
        let fields = Set(action.preconditions.map(\.field))
        guard fields.contains("authority_epoch") else {
            throw PrismACPActionRouterError.rejected("required_preconditions_missing")
        }
        if ["performance.go", "performance.fire_cue"].contains(action.name), !fields.contains("current_cue_id") {
            throw PrismACPActionRouterError.rejected("required_preconditions_missing")
        }
        guard showActionStorageKey(for: action) != nil else {
            throw PrismACPActionRouterError.unsupported
        }
        switch action.name {
        case "performance.fire_cue":
            guard let parameter = action.parameter, UUID(uuidString: parameter) != nil else {
                throw PrismACPActionRouterError.rejected("invalid_cue_id")
            }
        case "output.master":
            guard let value = action.value, value.isFinite, value >= 0, value <= 1 else {
                throw PrismACPActionRouterError.rejected("invalid_value")
            }
        default:
            break
        }
    }

    public static func showActionStorageKey(for action: PrismACPAction) -> String? {
        switch action.name {
        case "performance.go": return "go"
        case "performance.fire_cue": return "fireCue"
        case "output.master": return "masterIntensity"
        case "blackoutOn": return "blackout"
        case "blackoutOff": return "blackoutOff"
        default: return nil
        }
    }

    public static func isOnceOnly(_ action: PrismACPAction) -> Bool {
        ["performance.go", "performance.fire_cue", "blackoutOn", "blackoutOff"].contains(action.name)
    }

    public static func fingerprint(_ action: PrismACPAction) -> String {
        let predicates = action.preconditions.map {
            "\($0.op)|\($0.field)|\(String(describing: $0.value))|\($0.resource ?? "")|\($0.resourceField ?? "")"
        }.joined(separator: ";")
        let numericValue = action.value.map { String($0) } ?? ""
        return [action.name, action.parameter ?? "", numericValue, predicates].joined(separator: "|")
    }
}
