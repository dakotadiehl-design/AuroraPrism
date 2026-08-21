import Foundation

/// Durable show effect definition (P1-4). Runtime instances are derived from these.
///
/// `kind` matches engine `EffectKind` raw values: pulse, chase, wave, rainbow.
public struct EffectDefinition: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var kind: String
    /// Cycles per second.
    public var rateHz: Double
    /// Amplitude / level (0…1).
    public var size: Double
    /// Base phase 0…1.
    public var phase: Double
    /// Phase spread across fixtures (0…1).
    public var spread: Double
    public var attribute: String
    /// Ordered fixture participation (chase / wave phase order).
    public var fixtureIDs: [UUID]
    /// Explicit stack order (lower runs first). Not UUID order.
    public var order: Int
    public var enabled: Bool
    /// +1 forward / −1 reverse.
    public var direction: Double
    public var cellCount: Int
    /// FX-4 normalized intensity generator. Nil preserves exact legacy math.
    public var generator: EffectGeneratorDefinition?
    public var timing: EffectTimingDefinition?
    public var distribution: FixtureDistributionDefinition?
    /// Normalized property baseline used by V2 property mapping.
    public var base: Double
    public var colorGradient: EffectColorGradientDefinition?
    public var movement: EffectMovementDefinition?
    public var pattern: EffectPatternDefinition?
    public var cellTargeting: EffectCellTargetingDefinition?
    public var blendMode: EffectBlendMode
    public var blendAmount: Double
    public var mask: EffectMaskDefinition?
    public var templateEffectID: UUID?
    public var templateLinkMode: EffectTemplateLinkMode
    public var isFavorite: Bool
    public var scalarFan: EffectScalarFanDefinition?

    public init(
        id: UUID = UUID(),
        name: String = "Effect",
        kind: String = "pulse",
        rateHz: Double = 1,
        size: Double = 0.5,
        phase: Double = 0,
        spread: Double = 0,
        attribute: String = "intensity",
        fixtureIDs: [UUID] = [],
        order: Int = 0,
        enabled: Bool = true,
        direction: Double = 1,
        cellCount: Int = 0,
        generator: EffectGeneratorDefinition? = nil,
        timing: EffectTimingDefinition? = nil,
        distribution: FixtureDistributionDefinition? = nil,
        base: Double = 0,
        colorGradient: EffectColorGradientDefinition? = nil,
        movement: EffectMovementDefinition? = nil,
        pattern: EffectPatternDefinition? = nil,
        cellTargeting: EffectCellTargetingDefinition? = nil,
        blendMode: EffectBlendMode = .replace,
        blendAmount: Double = 1,
        mask: EffectMaskDefinition? = nil,
        templateEffectID: UUID? = nil,
        templateLinkMode: EffectTemplateLinkMode = .detached,
        isFavorite: Bool = false,
        scalarFan: EffectScalarFanDefinition? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rateHz = max(0, rateHz)
        self.size = min(1, max(0, size))
        self.phase = phase
        self.spread = spread
        self.attribute = attribute
        self.fixtureIDs = fixtureIDs
        self.order = order
        self.enabled = enabled
        self.direction = direction
        self.cellCount = cellCount
        self.generator = generator
        self.timing = timing
        self.distribution = distribution
        self.base = min(1, max(0, base))
        self.colorGradient = colorGradient
        self.movement = movement
        self.pattern = pattern
        self.cellTargeting = cellTargeting
        self.blendMode = blendMode
        self.blendAmount = min(1, max(0, blendAmount))
        self.mask = mask
        self.templateEffectID = templateEffectID
        self.templateLinkMode = templateLinkMode
        self.isFavorite = isFavorite
        self.scalarFan = scalarFan
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Effect"
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "pulse"
        rateHz = try c.decodeIfPresent(Double.self, forKey: .rateHz) ?? 1
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.5
        phase = try c.decodeIfPresent(Double.self, forKey: .phase) ?? 0
        spread = try c.decodeIfPresent(Double.self, forKey: .spread) ?? 0
        guard rateHz.isFinite, rateHz >= 0,
              size.isFinite, (0...1).contains(size),
              phase.isFinite, spread.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .rateHz, in: c, debugDescription: "Effect rate, size, phase, and spread are invalid")
        }
        attribute = try c.decodeIfPresent(String.self, forKey: .attribute) ?? "intensity"
        fixtureIDs = try c.decodeIfPresent([UUID].self, forKey: .fixtureIDs) ?? []
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        direction = try c.decodeIfPresent(Double.self, forKey: .direction) ?? 1
        cellCount = try c.decodeIfPresent(Int.self, forKey: .cellCount) ?? 0
        guard direction.isFinite, cellCount >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .direction, in: c, debugDescription: "Effect direction and cell count are invalid")
        }
        generator = try c.decodeIfPresent(EffectGeneratorDefinition.self, forKey: .generator)
        timing = try c.decodeIfPresent(EffectTimingDefinition.self, forKey: .timing)
        distribution = try c.decodeIfPresent(FixtureDistributionDefinition.self, forKey: .distribution)
        let decodedBase = try c.decodeIfPresent(Double.self, forKey: .base) ?? 0
        guard decodedBase.isFinite, (0...1).contains(decodedBase) else {
            throw DecodingError.dataCorruptedError(forKey: .base, in: c, debugDescription: "Effect base must be normalized")
        }
        base = decodedBase
        colorGradient = try c.decodeIfPresent(EffectColorGradientDefinition.self, forKey: .colorGradient)
        movement = try c.decodeIfPresent(EffectMovementDefinition.self, forKey: .movement)
        pattern = try c.decodeIfPresent(EffectPatternDefinition.self, forKey: .pattern)
        cellTargeting = try c.decodeIfPresent(EffectCellTargetingDefinition.self, forKey: .cellTargeting)
        blendMode = try c.decodeIfPresent(EffectBlendMode.self, forKey: .blendMode) ?? .replace
        let decodedBlendAmount = try c.decodeIfPresent(Double.self, forKey: .blendAmount) ?? 1
        guard decodedBlendAmount.isFinite, (0...1).contains(decodedBlendAmount) else {
            throw DecodingError.dataCorruptedError(forKey: .blendAmount, in: c, debugDescription: "Effect blend amount must be normalized")
        }
        blendAmount = decodedBlendAmount
        mask = try c.decodeIfPresent(EffectMaskDefinition.self, forKey: .mask)
        templateEffectID = try c.decodeIfPresent(UUID.self, forKey: .templateEffectID)
        templateLinkMode = try c.decodeIfPresent(EffectTemplateLinkMode.self, forKey: .templateLinkMode) ?? .detached
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        scalarFan = try c.decodeIfPresent(EffectScalarFanDefinition.self, forKey: .scalarFan)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, rateHz, size, phase, spread, attribute, fixtureIDs, order, enabled, direction, cellCount
        case generator, timing, distribution, base, colorGradient, movement, pattern, cellTargeting
        case blendMode, blendAmount, mask, templateEffectID, templateLinkMode, isFavorite
        case scalarFan
    }
}
