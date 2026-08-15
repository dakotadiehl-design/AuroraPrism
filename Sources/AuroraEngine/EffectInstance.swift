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
        cellCount: Int = 0
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
            cellCount: cellCount
        )
    }
}
