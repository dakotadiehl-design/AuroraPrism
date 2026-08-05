import Foundation

/// Runtime configuration for the lighting engine scheduler and merge.
public struct EngineConfiguration: Equatable, Sendable {
    /// Target frame rate in Hz (clamped to 20…44).
    public var frameRateHz: Double
    /// Channels per universe buffer.
    public var channelCount: Int
    /// How often UI-facing snapshots are refreshed while running (Hz).
    public var snapshotThrottleHz: Double

    public init(
        frameRateHz: Double = 40,
        channelCount: Int = 512,
        snapshotThrottleHz: Double = 15
    ) {
        self.frameRateHz = EngineConfiguration.clampFrameRate(frameRateHz)
        self.channelCount = max(1, channelCount)
        self.snapshotThrottleHz = max(1, min(snapshotThrottleHz, 60))
    }

    public static let `default` = EngineConfiguration()

    public var framePeriod: TimeInterval {
        1.0 / frameRateHz
    }

    public static func clampFrameRate(_ hz: Double) -> Double {
        min(44, max(20, hz))
    }
}
