import Foundation

/// How the reusable Stage canvas interprets pointer input (C1).
/// Geometry mutation is never implied by selection alone.
public enum StageInteractionMode: String, CaseIterable, Sendable, Equatable {
    /// Select fixtures; pan empty canvas; geometry locked.
    case programSelect
    /// Place / move / marquee / scenic edit; geometry unlocked.
    case editGeometry
    /// Pan/zoom only (no selection changes from canvas).
    case panOnly
}
