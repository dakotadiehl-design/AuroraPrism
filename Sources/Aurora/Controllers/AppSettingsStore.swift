import Foundation

/// Persisted Local DMX preference (UI-08 A1).
/// Prefers stable hardware identity over `/dev/cu.*` path alone.
struct LocalDMXPersistedPreference: Equatable, Codable, Sendable {
    /// Preferred stable identity (USB serial / hardware id when available).
    var hardwareIdentifier: String?
    /// Last known callout path (endpoint only — low confidence).
    var lastEndpointPath: String?
    /// Operator wants Local DMX on when device is present.
    var requestedEnabled: Bool

    static let empty = LocalDMXPersistedPreference(
        hardwareIdentifier: nil,
        lastEndpointPath: nil,
        requestedEnabled: false
    )
}

/// Remote access preference (UI-08 A5 / REM-07).
enum RemoteAccessMode: String, Codable, Sendable, CaseIterable {
    /// Loopback only.
    case thisMacOnly
    /// All interfaces (presented honestly — not private-LAN-only filtering).
    case localNetwork
}

/// True application-global preferences (not show-document settings).
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var preferredFrameRateHz: Double = 40
    @Published var showConsoleTimestamps: Bool = true
    @Published var preferredDensity: String = "standard"
    @Published var localDMX: LocalDMXPersistedPreference = .empty
    /// Remote remains off until operator enables (A5).
    @Published var remoteAccessEnabled: Bool = false
    @Published var remoteAccessMode: RemoteAccessMode = .thisMacOnly
    @Published var remotePort: UInt16 = 8742
    @Published var remoteWebPort: UInt16 = 8743
    /// PIN loaded from Keychain (SEC-01). Never logged.
    @Published var remotePIN: String = ""

    private let defaults: UserDefaults
    private let frameRateKey = "aurora.app.preferredFrameRateHz"
    private let consoleTsKey = "aurora.app.showConsoleTimestamps"
    private let densityKey = "aurora.app.preferredDensity"
    private let localDMXKey = "aurora.app.localDMX.v1"
    private let remoteEnabledKey = "aurora.app.remote.enabled"
    private let remoteModeKey = "aurora.app.remote.accessMode"
    private let remotePortKey = "aurora.app.remote.port"
    private let remoteWebPortKey = "aurora.app.remote.webPort"
    /// Legacy plaintext key — migrated once then cleared (SEC-01).
    private let remotePINKeyLegacy = "aurora.app.remote.pin"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: frameRateKey) != nil {
            preferredFrameRateHz = defaults.double(forKey: frameRateKey)
        }
        if defaults.object(forKey: consoleTsKey) != nil {
            showConsoleTimestamps = defaults.bool(forKey: consoleTsKey)
        }
        if let d = defaults.string(forKey: densityKey) {
            preferredDensity = d
        }
        if let data = defaults.data(forKey: localDMXKey),
           let decoded = try? JSONDecoder().decode(LocalDMXPersistedPreference.self, from: data) {
            localDMX = decoded
        }
        remoteAccessEnabled = defaults.bool(forKey: remoteEnabledKey)
        if let mode = defaults.string(forKey: remoteModeKey),
           let parsed = RemoteAccessMode(rawValue: mode) {
            remoteAccessMode = parsed
        }
        if defaults.object(forKey: remotePortKey) != nil {
            let p = defaults.integer(forKey: remotePortKey)
            if p > 0, p < 65536 { remotePort = UInt16(p) }
        }
        if defaults.object(forKey: remoteWebPortKey) != nil {
            let p = defaults.integer(forKey: remoteWebPortKey)
            if p > 0, p < 65536 { remoteWebPort = UInt16(p) }
        }
        // SEC-01: prefer Keychain; migrate legacy UserDefaults once.
        if let keychainPIN = RemotePINKeychain.load(), !keychainPIN.isEmpty {
            remotePIN = keychainPIN
        } else if let legacy = defaults.string(forKey: remotePINKeyLegacy), !legacy.isEmpty {
            remotePIN = legacy
            _ = RemotePINKeychain.save(legacy)
            defaults.removeObject(forKey: remotePINKeyLegacy)
        }
    }

    func save() {
        defaults.set(preferredFrameRateHz, forKey: frameRateKey)
        defaults.set(showConsoleTimestamps, forKey: consoleTsKey)
        defaults.set(preferredDensity, forKey: densityKey)
        if let data = try? JSONEncoder().encode(localDMX) {
            defaults.set(data, forKey: localDMXKey)
        }
        defaults.set(remoteAccessEnabled, forKey: remoteEnabledKey)
        defaults.set(remoteAccessMode.rawValue, forKey: remoteModeKey)
        defaults.set(Int(remotePort), forKey: remotePortKey)
        defaults.set(Int(remoteWebPort), forKey: remoteWebPortKey)
        // PIN lives in Keychain only.
        if remotePIN.isEmpty {
            RemotePINKeychain.delete()
        } else {
            _ = RemotePINKeychain.save(remotePIN)
        }
        defaults.removeObject(forKey: remotePINKeyLegacy)
    }

    func updateLocalDMX(_ value: LocalDMXPersistedPreference) {
        localDMX = value
        save()
    }

    /// SET-01: validate port without silent coercion. Returns error message or nil.
    static func validatePort(_ text: String) -> (UInt16?, String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (nil, "Port is required")
        }
        guard let value = Int(trimmed) else {
            return (nil, "Port must be a number")
        }
        guard value >= 1, value <= 65535 else {
            return (nil, "Port must be 1–65535")
        }
        return (UInt16(value), nil)
    }
}
