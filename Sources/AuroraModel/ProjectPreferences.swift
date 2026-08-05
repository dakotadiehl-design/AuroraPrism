import Foundation

/// Project-scoped defaults (fade times, tracking, etc.). App-level prefs live elsewhere.
public struct ProjectPreferences: Codable, Equatable, Sendable, Hashable {
    /// Default fade-in when creating cues (seconds).
    public var defaultFadeIn: TimeInterval
    /// Default fade-out when creating cues (seconds).
    public var defaultFadeOut: TimeInterval
    /// Default tracking mode for new cues.
    public var defaultTracking: TrackingMode
    /// Default engine frame rate hint stored with the show (Hz). Engine may override.
    public var preferredFrameRateHz: Double

    public init(
        defaultFadeIn: TimeInterval = 0,
        defaultFadeOut: TimeInterval = 0,
        defaultTracking: TrackingMode = .track,
        preferredFrameRateHz: Double = 40
    ) {
        self.defaultFadeIn = defaultFadeIn
        self.defaultFadeOut = defaultFadeOut
        self.defaultTracking = defaultTracking
        self.preferredFrameRateHz = preferredFrameRateHz
    }

    public static let `default` = ProjectPreferences()
}
