import Foundation

public enum PrismLogProfile: String, Codable, Sendable, CaseIterable {
    case productionDefaults
    case troubleshooting
    case verboseAll
    case custom

    public var displayName: String {
        switch self {
        case .productionDefaults: return "Production Defaults"
        case .troubleshooting: return "Troubleshooting"
        case .verboseAll: return "Verbose All"
        case .custom: return "Custom"
        }
    }
}

/// Immutable snapshot swapped atomically when Settings change.
public struct PrismLogConfiguration: Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var profile: PrismLogProfile
    public var thresholds: [PrismLogCategory: PrismLogLevel]
    public init(
        version: Int = PrismLogConfiguration.currentVersion,
        profile: PrismLogProfile = .productionDefaults,
        thresholds: [PrismLogCategory: PrismLogLevel] = [:]
    ) {
        self.version = version
        self.profile = profile
        self.thresholds = thresholds
    }

    public static var productionDefaults: PrismLogConfiguration {
        var thresholds: [PrismLogCategory: PrismLogLevel] = [:]
        for category in PrismLogCategory.allCases {
            thresholds[category] = category.defaultLevel
        }
        return PrismLogConfiguration(profile: .productionDefaults, thresholds: thresholds)
    }

    public static var troubleshooting: PrismLogConfiguration {
        var thresholds: [PrismLogCategory: PrismLogLevel] = [:]
        for category in PrismLogCategory.allCases {
            switch category.group {
            case .ame, .music, .control, .remote, .output:
                thresholds[category] = .info
            case .ui:
                thresholds[category] = .error
            default:
                thresholds[category] = category == .enginePerformance ? .error : .notice
            }
        }
        return PrismLogConfiguration(profile: .troubleshooting, thresholds: thresholds)
    }

    public static var verboseAll: PrismLogConfiguration {
        var thresholds: [PrismLogCategory: PrismLogLevel] = [:]
        for category in PrismLogCategory.allCases {
            thresholds[category] = .debug
        }
        return PrismLogConfiguration(profile: .verboseAll, thresholds: thresholds)
    }

    public func level(for category: PrismLogCategory) -> PrismLogLevel {
        thresholds[category] ?? category.defaultLevel
    }

    public func accepts(_ level: PrismLogLevel, category: PrismLogCategory) -> Bool {
        self.level(for: category).accepts(level)
    }

    public func setting(_ category: PrismLogCategory, to level: PrismLogLevel) -> PrismLogConfiguration {
        var next = thresholds
        next[category] = level
        return PrismLogConfiguration(profile: .custom, thresholds: next)
    }

    public func setting(group: PrismLogCategoryGroup, to level: PrismLogLevel) -> PrismLogConfiguration {
        var next = thresholds
        for category in group.categories {
            next[category] = level
        }
        return PrismLogConfiguration(profile: .custom, thresholds: next)
    }

    public func settingAll(to level: PrismLogLevel) -> PrismLogConfiguration {
        var next: [PrismLogCategory: PrismLogLevel] = [:]
        for category in PrismLogCategory.allCases {
            next[category] = level
        }
        return PrismLogConfiguration(profile: .custom, thresholds: next)
    }
}

extension PrismLogConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, profile, thresholds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(profile, forKey: .profile)
        var encoded: [String: String] = [:]
        for (category, level) in thresholds {
            encoded[category.rawValue] = level.rawValue
        }
        try container.encode(encoded, forKey: .thresholds)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        guard storedVersion <= PrismLogConfiguration.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Logging configuration version \(storedVersion) is newer than supported version \(PrismLogConfiguration.currentVersion)."
            )
        }
        guard storedVersion >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Logging configuration version cannot be negative."
            )
        }
        // Version 0 (a missing version field) is the only legacy representation.
        // Its keys are compatible with v1, so migration consists of normalizing the version.
        version = PrismLogConfiguration.currentVersion
        profile = try container.decodeIfPresent(PrismLogProfile.self, forKey: .profile) ?? .custom
        let encoded = try container.decodeIfPresent([String: String].self, forKey: .thresholds) ?? [:]
        var decoded: [PrismLogCategory: PrismLogLevel] = [:]
        for category in PrismLogCategory.allCases {
            if let raw = encoded[category.rawValue], let level = PrismLogLevel(rawValue: raw) {
                decoded[category] = level
            } else {
                decoded[category] = category.defaultLevel
            }
        }
        thresholds = decoded
    }
}

public final class PrismLogConfigurationStore: @unchecked Sendable {
    public static let shared = PrismLogConfigurationStore()

    private let lock = NSLock()
    private var snapshot: PrismLogConfiguration

    public init(initial: PrismLogConfiguration = .productionDefaults) {
        snapshot = initial
    }

    public func current() -> PrismLogConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func replace(_ config: PrismLogConfiguration) {
        lock.lock()
        snapshot = config
        lock.unlock()
    }
}
