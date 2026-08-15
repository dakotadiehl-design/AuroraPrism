import Foundation

/// Authoritative per-frame semantic presentation (Pass-1 A5 / P0-A fix).
/// Produced on the same evaluation path as DMX merge — Stage Preview must consume this, not rebuild looks in AppModel.
public struct ResolvedShowSnapshot: Equatable, Sendable {
    public var frameIndex: UInt64
    public var timestamp: TimeInterval
    /// Fully resolved ActiveLook after playback → effects → programmer → global (pre-freeze hold).
    public var look: ActiveLook
    /// Look used for physical presentation (equals `look` unless freeze is holding a prior frame's look).
    public var presentationLook: ActiveLook
    public var playback: PlaybackSnapshot
    public var global: GlobalShowControlState
    public var universeLevels: [UInt16: [UInt8]]

    public init(
        frameIndex: UInt64 = 0,
        timestamp: TimeInterval = 0,
        look: ActiveLook = .empty,
        presentationLook: ActiveLook = .empty,
        playback: PlaybackSnapshot = .idle,
        global: GlobalShowControlState = .default,
        universeLevels: [UInt16: [UInt8]] = [:]
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.look = look
        self.presentationLook = presentationLook
        self.playback = playback
        self.global = global
        self.universeLevels = universeLevels
    }

    public static let empty = ResolvedShowSnapshot()
}
