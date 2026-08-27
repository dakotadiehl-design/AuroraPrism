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

/// True application-global preferences (not show-document settings).
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var preferredFrameRateHz: Double = 40
    @Published var showConsoleTimestamps: Bool = true
    @Published var preferredDensity: String = "standard"
    @Published var localDMX: LocalDMXPersistedPreference = .empty
    @Published var loggingConfiguration: PrismLogConfiguration = .productionDefaults
    /// Set when saved logging JSON is corrupt. Consumed after logger bootstrap.
    private(set) var pendingLoggingFallbackWarning = false

    private let defaults: UserDefaults
    private let frameRateKey = "aurora.app.preferredFrameRateHz"
    private let consoleTsKey = "aurora.app.showConsoleTimestamps"
    private let densityKey = "aurora.app.preferredDensity"
    private let localDMXKey = "aurora.app.localDMX.v1"
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
        if let data = try? JSONEncoder().encode(loggingConfiguration) {
            defaults.set(data, forKey: loggingKey)
        }
    }

    func updateLocalDMX(_ value: LocalDMXPersistedPreference) {
        localDMX = value
        save()
    }

}
