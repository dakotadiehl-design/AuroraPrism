import Foundation

public enum FollowMode: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case manual
    case afterTime
    case afterGo
}

public enum TrackingMode: String, Codable, Sendable, Hashable, CaseIterable {
    case track
    case cueOnly
}

public struct LoopSpec: Codable, Equatable, Sendable, Hashable {
    public var count: Int?
    public var infinite: Bool

    public init(count: Int? = nil, infinite: Bool = false) {
        self.count = count
        self.infinite = infinite
    }

    public static let infiniteLoop = LoopSpec(count: nil, infinite: true)
}

/// Sparse per-fixture targets: literals and/or palette references.
public struct FixtureCueLevels: Codable, Equatable, Sendable, Hashable {
    public var fixtureId: UUID
    /// Literal attribute tag → 0…1.
    public var attributes: [String: Double]
    /// Attribute family or tag → palette UUID (“use whatever this palette means”).
    public var paletteRefs: [String: UUID]

    public init(
        fixtureId: UUID,
        attributes: [String: Double] = [:],
        paletteRefs: [String: UUID] = [:]
    ) {
        self.fixtureId = fixtureId
        self.attributes = attributes
        self.paletteRefs = paletteRefs
    }
}

public struct CueLevelData: Codable, Equatable, Sendable, Hashable {
    public var fixtures: [FixtureCueLevels]

    public init(fixtures: [FixtureCueLevels] = []) {
        self.fixtures = fixtures
    }

    public static let empty = CueLevelData()
}

public struct Cue: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
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
