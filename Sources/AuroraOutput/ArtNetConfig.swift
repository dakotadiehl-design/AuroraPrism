import Foundation

/// User-facing Art-Net output settings (app prefs; not necessarily in show file).
public struct ArtNetConfig: Equatable, Sendable, Codable {
    public var enabled: Bool
    /// Unicast host or broadcast address (e.g. "192.168.1.20" or "255.255.255.255").
    public var destinationHost: String
    public var destinationPort: UInt16
    /// Art-Net universe = Int(showUniverseNumber) + universeOffset.
    /// Default -1 so show universe 1 → Art-Net 0.
    public var universeOffset: Int
    public var useBroadcast: Bool

    public init(
        enabled: Bool = false,
        destinationHost: String = "255.255.255.255",
        destinationPort: UInt16 = 6454,
        universeOffset: Int = -1,
        useBroadcast: Bool = true
    ) {
        self.enabled = enabled
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
        self.universeOffset = universeOffset
        self.useBroadcast = useBroadcast
    }

    public static let `default` = ArtNetConfig()

    public static let defaultsKey = "aurora.output.artnet.v1"

    public static func load(from defaults: UserDefaults = .standard) -> ArtNetConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(ArtNetConfig.self, from: data)
        else { return .default }
        return config
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: ArtNetConfig.defaultsKey)
        }
    }

    public func artNetUniverse(forShowUniverse number: UInt16) -> UInt16 {
        let value = Int(number) + universeOffset
        return UInt16(clamping: max(0, min(0x7FFF, value)))
    }
}
