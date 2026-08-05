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
        enabled: Bool = true
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
    }
}
