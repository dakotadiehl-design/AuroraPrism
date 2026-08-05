import Foundation

/// User-facing sACN / E1.31 output settings (app prefs).
public struct SACNConfig: Equatable, Sendable, Codable {
    public var enabled: Bool
    /// When non-nil and non-empty, unicast to this host; otherwise multicast per universe.
    public var destinationHost: String?
    public var destinationPort: UInt16
    /// sACN universe = Int(showUniverseNumber) + universeOffset (default 0 → show 1 = sACN 1).
    public var universeOffset: Int
    /// E1.31 priority 0…200 (default 100).
    public var priority: UInt8
    public var sourceName: String

    public init(
        enabled: Bool = false,
        destinationHost: String? = nil,
        destinationPort: UInt16 = 5568,
        universeOffset: Int = 0,
        priority: UInt8 = 100,
        sourceName: String = "Aurora"
    ) {
        self.enabled = enabled
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
        self.universeOffset = universeOffset
        self.priority = min(200, priority)
        self.sourceName = sourceName
    }

    public static let `default` = SACNConfig()
    public static let defaultsKey = "aurora.output.sacn.v1"

    public static func load(from defaults: UserDefaults = .standard) -> SACNConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(SACNConfig.self, from: data)
        else { return .default }
        return config
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: SACNConfig.defaultsKey)
        }
    }

    public func sacnUniverse(forShowUniverse number: UInt16) -> UInt16 {
        let value = Int(number) + universeOffset
        return UInt16(clamping: max(1, min(63_999, value)))
    }

    /// E1.31 multicast address for a sACN universe number.
    public static func multicastHost(forSACNUniverse universe: UInt16) -> String {
        let hi = (universe >> 8) & 0xFF
        let lo = universe & 0xFF
        return "239.255.\(hi).\(lo)"
    }

    public func destinationHost(forSACNUniverse universe: UInt16) -> String {
        if let host = destinationHost, !host.isEmpty {
            return host
        }
        return Self.multicastHost(forSACNUniverse: universe)
    }
}
