import CoreMIDI
import Foundation

/// Configuration for built-in RTP-MIDI via CoreMIDI network session (PR18).
public struct RTPMIDIConfig: Equatable, Sendable, Codable {
    public var enabled: Bool
    /// When true, accept connections from anyone (`.anyone`); else contacts-only.
    public var allowAnyone: Bool

    public init(enabled: Bool = false, allowAnyone: Bool = true) {
        self.enabled = enabled
        self.allowAnyone = allowAnyone
    }

    public static let `default` = RTPMIDIConfig()
    public static let defaultsKey = "aurora.midi.rtpmidi.v1"

    public static func load(from defaults: UserDefaults = .standard) -> RTPMIDIConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(RTPMIDIConfig.self, from: data)
        else { return .default }
        return config
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: RTPMIDIConfig.defaultsKey)
        }
    }
}

/// Wraps `MIDINetworkSession` so Aurora can offer RTP-MIDI without Audio MIDI Setup.
public final class RTPMIDISession: @unchecked Sendable {
    private let lock = NSLock()
    private var config: RTPMIDIConfig
    private var _lastError: String?

    public init(config: RTPMIDIConfig = .default) {
        self.config = config
    }

    public var configSnapshot: RTPMIDIConfig {
        lock.lock()
        defer { lock.unlock() }
        return config
    }

    public var lastError: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }

    /// Whether the system network session reports enabled.
    public var isNetworkEnabled: Bool {
        MIDINetworkSession.default().isEnabled
    }

    public var localName: String {
        MIDINetworkSession.default().networkName
    }

    /// Applies config to the shared `MIDINetworkSession`.
    public func apply(_ config: RTPMIDIConfig) {
        lock.lock()
        self.config = config
        lock.unlock()
        config.save()

        let session = MIDINetworkSession.default()
        session.isEnabled = config.enabled
        session.connectionPolicy = config.allowAnyone
            ? MIDINetworkConnectionPolicy.anyone
            : MIDINetworkConnectionPolicy.hostsInContactList
        lock.lock()
        _lastError = nil
        lock.unlock()
    }

    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        var next = config
        lock.unlock()
        next.enabled = enabled
        apply(next)
    }

    public func statusLine() -> String {
        let session = MIDINetworkSession.default()
        if session.isEnabled {
            return "RTP-MIDI: on · \(session.networkName)"
        }
        return "RTP-MIDI: off"
    }
}
