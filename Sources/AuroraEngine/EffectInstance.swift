import AuroraModel
import Foundation

/// A live effect applied above playback and below the programmer (PR22 / P1-4).
public struct EffectInstance: Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var kind: EffectKind
    /// Cycles per second.
    public var rateHz: Double
    /// Amplitude / level (0…1).
    public var size: Double
    /// Base phase 0…1.
    public var phase: Double
    /// Additional phase per fixture index (0…1 full cycle across the span).
    public var spread: Double
    /// Primary attribute for pulse / chase / wave.
    public var attribute: String
    /// Ordered fixture participation (chase / wave phase order).
    public var fixtureIDs: [UUID]
    /// Explicit apply order (lower first). Not UUID sort.
    public var order: Int
    public var enabled: Bool
    /// +1 forward, −1 reverse chase/wave direction.
    public var direction: Double
    /// Number of cells for cellChase (0 = auto from attribute pattern).
    public var cellCount: Int
    public var generator: EffectGeneratorDefinition?
    public var timing: EffectTimingDefinition?
    public var distribution: FixtureDistributionDefinition?
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
        kind: EffectKind = .pulse,
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
        self.direction = direction >= 0 ? 1 : -1
        self.cellCount = max(0, cellCount)
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

    public init(definition: EffectDefinition) {
        self.id = definition.id
        self.name = definition.name
        self.kind = EffectKind(rawValue: definition.kind) ?? .pulse
        self.rateHz = definition.rateHz
        self.size = definition.size
        self.phase = definition.phase
        self.spread = definition.spread
        self.attribute = definition.attribute
        self.fixtureIDs = definition.fixtureIDs
        self.order = definition.order
        self.enabled = definition.enabled
        self.direction = definition.direction >= 0 ? 1 : -1
        self.cellCount = definition.cellCount
        self.generator = definition.generator
        self.timing = definition.timing
        self.distribution = definition.distribution
        self.base = definition.base
        self.colorGradient = definition.colorGradient
        self.movement = definition.movement
        self.pattern = definition.pattern
        self.cellTargeting = definition.cellTargeting
        self.blendMode = definition.blendMode
        self.blendAmount = definition.blendAmount
        self.mask = definition.mask
        self.templateEffectID = definition.templateEffectID
        self.templateLinkMode = definition.templateLinkMode
        self.isFavorite = definition.isFavorite
        self.scalarFan = definition.scalarFan
    }

    public func asDefinition() -> EffectDefinition {
        EffectDefinition(
            id: id,
            name: name,
            kind: kind.rawValue,
            rateHz: rateHz,
            size: size,
            phase: phase,
            spread: spread,
            attribute: attribute,
            fixtureIDs: fixtureIDs,
            order: order,
            enabled: enabled,
            direction: direction,
            cellCount: cellCount,
            generator: generator,
            timing: timing,
            distribution: distribution,
            base: base,
            colorGradient: colorGradient,
            movement: movement,
            pattern: pattern,
            cellTargeting: cellTargeting,
            blendMode: blendMode,
            blendAmount: blendAmount,
            mask: mask,
            templateEffectID: templateEffectID,
            templateLinkMode: templateLinkMode,
            isFavorite: isFavorite,
            scalarFan: scalarFan
        )
    }
}
