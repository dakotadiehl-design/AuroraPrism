import AuroraDiagnostics
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
    @Published var acpWebSocketPort: UInt16 = 27421
    @Published var acpDiscoveryEnabled: Bool = false
    /// Control is a separate, fail-closed opt-in from read-only remote access.
    @Published var acpShowControlEnabled: Bool = false
    /// Server-owned ACP node enrollment. Stored as a comma/newline separated list.
    @Published var acpOperatorNodeIDsText: String = ""
    /// Separate safety grant. Being an operator does not imply authority to clear blackout.
    @Published var acpBlackoutClearNodeIDsText: String = ""
    @Published var loggingConfiguration: PrismLogConfiguration = .productionDefaults
    /// Set when saved logging JSON is corrupt. Consumed after logger bootstrap.
    private(set) var pendingLoggingFallbackWarning = false

    private let defaults: UserDefaults
    private let frameRateKey = "aurora.app.preferredFrameRateHz"
    private let consoleTsKey = "aurora.app.showConsoleTimestamps"
    private let densityKey = "aurora.app.preferredDensity"
    private let localDMXKey = "aurora.app.localDMX.v1"
    private let remoteEnabledKey = "aurora.app.remote.enabled"
    private let remoteModeKey = "aurora.app.remote.accessMode"
    private let acpPortKey = "prism.app.acp.port"
    private let acpDiscoveryKey = "prism.app.acp.discovery"
    private let acpShowControlKey = "prism.app.acp.showControl"
    private let acpOperatorNodesKey = "prism.app.acp.operatorNodes"
    private let acpBlackoutClearNodesKey = "prism.app.acp.blackoutClearNodes"
    private let loggingKey = "prism.logging.configuration.v1"

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
        if defaults.object(forKey: acpPortKey) != nil {
            let p = defaults.integer(forKey: acpPortKey)
            if p > 0, p < 65536 { acpWebSocketPort = UInt16(p) }
        }
        acpDiscoveryEnabled = defaults.bool(forKey: acpDiscoveryKey)
        acpShowControlEnabled = defaults.bool(forKey: acpShowControlKey)
        acpOperatorNodeIDsText = defaults.string(forKey: acpOperatorNodesKey) ?? ""
        acpBlackoutClearNodeIDsText = defaults.string(forKey: acpBlackoutClearNodesKey) ?? ""
        defaults.removeObject(forKey: "aurora.app.remote.port")
        defaults.removeObject(forKey: "aurora.app.remote.webPort")
        defaults.removeObject(forKey: "aurora.app.remote.pin")
        loadLoggingConfiguration()
    }

    private func loadLoggingConfiguration() {
        guard let data = defaults.data(forKey: loggingKey) else {
            loggingConfiguration = .productionDefaults
            return
        }
        do {
            loggingConfiguration = try JSONDecoder().decode(PrismLogConfiguration.self, from: data)
        } catch {
            loggingConfiguration = .productionDefaults
            pendingLoggingFallbackWarning = true
        }
        PrismLogConfigurationStore.shared.replace(loggingConfiguration)
    }

    func consumeLoggingLoadWarning() -> Bool {
        let pending = pendingLoggingFallbackWarning
        pendingLoggingFallbackWarning = false
        return pending
    }

    func applyLoggingConfiguration(_ config: PrismLogConfiguration) {
        loggingConfiguration = config
        PrismLogConfigurationStore.shared.replace(config)
        save()
        PrismLog.notice(
            .appSettings,
            "app.settings.profile_changed",
            "Logging profile is now \(config.profile.displayName).",
            metadata: ["profile": .public(config.profile.rawValue)]
        )
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
        defaults.set(Int(acpWebSocketPort), forKey: acpPortKey)
        defaults.set(acpDiscoveryEnabled, forKey: acpDiscoveryKey)
        defaults.set(acpShowControlEnabled, forKey: acpShowControlKey)
        defaults.set(acpOperatorNodeIDsText, forKey: acpOperatorNodesKey)
        defaults.set(acpBlackoutClearNodeIDsText, forKey: acpBlackoutClearNodesKey)
        defaults.removeObject(forKey: "aurora.app.remote.port")
        defaults.removeObject(forKey: "aurora.app.remote.webPort")
        defaults.removeObject(forKey: "aurora.app.remote.pin")
        if let data = try? JSONEncoder().encode(loggingConfiguration) {
            defaults.set(data, forKey: loggingKey)
        }
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
