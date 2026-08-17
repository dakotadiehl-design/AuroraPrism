import Foundation

/// Discontinuities and transport transitions. Consumers (AME, future Effects) must
/// distinguish normal phase advance from seeks / source changes.
public enum MusicalTimelineEvent: Equatable, Sendable {
    case started
    case stopped
    case continued
    case positionJumped(old: QuarterNotePosition?, new: QuarterNotePosition?)
    case sourceChanged(from: String?, to: String?)
    case syncLost
    case syncRecovered
    case freewheelBegan
    case fallbackActivated
}
