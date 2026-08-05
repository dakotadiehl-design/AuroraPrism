import Foundation

/// True application-global preferences (not show-document settings).
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var preferredFrameRateHz: Double = 40
    @Published var showConsoleTimestamps: Bool = true

    private let defaults: UserDefaults
    private let frameRateKey = "aurora.app.preferredFrameRateHz"
    private let consoleTsKey = "aurora.app.showConsoleTimestamps"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: frameRateKey) != nil {
            preferredFrameRateHz = defaults.double(forKey: frameRateKey)
        }
        if defaults.object(forKey: consoleTsKey) != nil {
            showConsoleTimestamps = defaults.bool(forKey: consoleTsKey)
        }
    }

    func save() {
        defaults.set(preferredFrameRateHz, forKey: frameRateKey)
        defaults.set(showConsoleTimestamps, forKey: consoleTsKey)
    }
}
