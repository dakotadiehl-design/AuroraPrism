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
    /// Ordered live references to Cue Blocks. Order is merge-significant.
    public var cueBlockRefs: [CueBlockReference]

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
        loop: LoopSpec? = nil,
        cueBlockRefs: [CueBlockReference] = []
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
        self.cueBlockRefs = cueBlockRefs
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, name, fadeIn, fadeOut, delay, follow, followTime, tracking, levels, loop, cueBlockRefs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Decimal.self, forKey: .number)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        fadeIn = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeIn) ?? 0
        fadeOut = try c.decodeIfPresent(TimeInterval.self, forKey: .fadeOut) ?? 0
        delay = try c.decodeIfPresent(TimeInterval.self, forKey: .delay) ?? 0
        follow = try c.decodeIfPresent(FollowMode.self, forKey: .follow) ?? .none
        followTime = try c.decodeIfPresent(TimeInterval.self, forKey: .followTime)
        tracking = try c.decodeIfPresent(TrackingMode.self, forKey: .tracking) ?? .track
        levels = try c.decodeIfPresent(CueLevelData.self, forKey: .levels) ?? .empty
        loop = try c.decodeIfPresent(LoopSpec.self, forKey: .loop)
        // Older cue-list JSON without the key decodes to empty (schema ≤4).
        cueBlockRefs = try c.decodeIfPresent([CueBlockReference].self, forKey: .cueBlockRefs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(number, forKey: .number)
        try c.encode(name, forKey: .name)
        try c.encode(fadeIn, forKey: .fadeIn)
        try c.encode(fadeOut, forKey: .fadeOut)
        try c.encode(delay, forKey: .delay)
        try c.encode(follow, forKey: .follow)
        try c.encodeIfPresent(followTime, forKey: .followTime)
        try c.encode(tracking, forKey: .tracking)
        try c.encode(levels, forKey: .levels)
        try c.encodeIfPresent(loop, forKey: .loop)
        try c.encode(cueBlockRefs, forKey: .cueBlockRefs)
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
