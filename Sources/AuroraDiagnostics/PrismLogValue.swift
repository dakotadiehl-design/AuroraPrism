import Foundation

public enum PrismLogPrivacy: String, Sendable, Codable, Equatable {
    case `public`
    case `private`
    case sensitive
}

/// Closed metadata value. Keys are sorted at event construction for deterministic tests.
public enum PrismLogValue: Sendable, Equatable {
    case string(String, privacy: PrismLogPrivacy)
    case int(Int, privacy: PrismLogPrivacy)
    case uint(UInt64, privacy: PrismLogPrivacy)
    case double(Double, privacy: PrismLogPrivacy)
    case bool(Bool, privacy: PrismLogPrivacy)
    case identifier(String, privacy: PrismLogPrivacy)

    public var privacy: PrismLogPrivacy {
        switch self {
        case .string(_, let privacy),
             .int(_, let privacy),
             .uint(_, let privacy),
             .double(_, let privacy),
             .bool(_, let privacy),
             .identifier(_, let privacy):
            return privacy
        }
    }

    public var publicDescription: String {
        switch privacy {
        case .public:
            return rawDescription
        case .private, .sensitive:
            return "<private>"
        }
    }

    public var rawDescription: String {
        switch self {
        case .string(let value, _): return value
        case .int(let value, _): return String(value)
        case .uint(let value, _): return String(value)
        case .double(let value, _): return String(value)
        case .bool(let value, _): return value ? "true" : "false"
        case .identifier(let value, _): return value
        }
    }

    public var estimatedByteCount: Int {
        rawDescription.utf8.count
    }

    public static func `public`(_ value: String) -> PrismLogValue {
        .string(value, privacy: .public)
    }

    public static func count(_ value: Int) -> PrismLogValue {
        .int(value, privacy: .public)
    }

    public static func flag(_ value: Bool) -> PrismLogValue {
        .bool(value, privacy: .public)
    }
}

extension PrismLogValue: Codable {
    private enum Kind: String, Codable {
        case string, int, uint, double, bool, identifier
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, privacy
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(privacy, forKey: .privacy)
        switch self {
        case .string(let value, _):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .int(let value, _):
            try container.encode(Kind.int, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .uint(let value, _):
            try container.encode(Kind.uint, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .double(let value, _):
            try container.encode(Kind.double, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .bool(let value, _):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .identifier(let value, _):
            try container.encode(Kind.identifier, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let privacy = try container.decode(PrismLogPrivacy.self, forKey: .privacy)
        switch kind {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value), privacy: privacy)
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value), privacy: privacy)
        case .uint:
            self = .uint(try container.decode(UInt64.self, forKey: .value), privacy: privacy)
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value), privacy: privacy)
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value), privacy: privacy)
        case .identifier:
            self = .identifier(try container.decode(String.self, forKey: .value), privacy: privacy)
        }
    }
}
