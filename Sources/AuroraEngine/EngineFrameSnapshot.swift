import AuroraModel
import Foundation

/// Immutable engine state for UI monitors (throttled copies).
public struct EngineFrameSnapshot: Equatable, Sendable {
    public var frameIndex: UInt64
    public var time: TimeInterval
    public var frameRateHz: Double
    /// Universe **number** → full DMX channel array.
    public var universeLevels: [UInt16: [UInt8]]
    public var isRunning: Bool
    public var playback: PlaybackSnapshot
    /// Non-fatal palette/resolution issues from last resolve (P1-11).
    public var resolutionIssues: [ResolutionIssue]

    public init(
        frameIndex: UInt64 = 0,
        time: TimeInterval = 0,
        frameRateHz: Double = 40,
        universeLevels: [UInt16: [UInt8]] = [:],
        isRunning: Bool = false,
        playback: PlaybackSnapshot = .idle,
        resolutionIssues: [ResolutionIssue] = []
    ) {
        self.frameIndex = frameIndex
        self.time = time
        self.frameRateHz = frameRateHz
        self.universeLevels = universeLevels
        self.isRunning = isRunning
        self.playback = playback
        self.resolutionIssues = resolutionIssues
    }

    public static let idle = EngineFrameSnapshot()
}
