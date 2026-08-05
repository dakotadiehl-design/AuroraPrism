import Foundation

public enum FollowMode: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case manual
    case afterTime
    case afterGo
}

public enum TrackingMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// Unresolved attributes inherit from previous cues when resolving a look.
    case track
    /// Cue contributes only its stored levels (cue-only / non-tracking).
    case cueOnly
}

/// Optional loop behavior for a cue stack entry.
public struct LoopSpec: Codable, Equatable, Sendable, Hashable {
    public var count: Int?
    public var infinite: Bool

    public init(count: Int? = nil, infinite: Bool = false) {
        self.count = count
        self.infinite = infinite
    }

    public static let infiniteLoop = LoopSpec(count: nil, infinite: true)
}

/// Sparse per-fixture attribute targets stored on a cue or preset.
public struct FixtureCueLevels: Codable, Equatable, Sendable, Hashable {
    public var fixtureId: UUID
    /// Attribute tag → normalized or absolute value (engine interprets).
    public var attributes: [String: Double]

    public init(fixtureId: UUID, attributes: [String: Double] = [:]) {
        self.fixtureId = fixtureId
        self.attributes = attributes
    }
}

public struct CueLevelData: Codable, Equatable, Sendable, Hashable {
    public var fixtures: [FixtureCueLevels]

    public init(fixtures: [FixtureCueLevels] = []) {
        self.fixtures = fixtures
    }

    public static let empty = CueLevelData()
}

/// One cue in a cue list.
public struct Cue: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    /// User-facing cue number (supports 1.5-style numbering via Decimal).
    public var number: Decimal
    public var name: String
    public var fadeIn: TimeInterval
    public var fadeOut: TimeInterval
    public var delay: TimeInterval
    public var follow: FollowMode
    public var followTime: TimeInterval?
    public var tracking: TrackingMode
    public var levels: CueLevelData
    public var loop: LoopSpec?

    public init(
        id: UUID = UUID(),
        number: Decimal,
        name: String = "",
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        delay: TimeInterval = 0,
        follow: FollowMode = .none,
        followTime: TimeInterval? = nil,
        tracking: TrackingMode = .track,
        levels: CueLevelData = .empty,
        loop: LoopSpec? = nil
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.delay = delay
        self.follow = follow
        self.followTime = followTime
        self.tracking = tracking
        self.levels = levels
        self.loop = loop
    }
}

/// Ordered list of cues (a cue stack / sequence).
public struct CueList: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var cues: [Cue]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        cues: [Cue] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.cues = cues
        self.notes = notes
    }
}
