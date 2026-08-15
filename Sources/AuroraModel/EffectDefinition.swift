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
        self.direction = direction
        self.cellCount = cellCount
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
        attribute = try c.decodeIfPresent(String.self, forKey: .attribute) ?? "intensity"
        fixtureIDs = try c.decodeIfPresent([UUID].self, forKey: .fixtureIDs) ?? []
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        direction = try c.decodeIfPresent(Double.self, forKey: .direction) ?? 1
        cellCount = try c.decodeIfPresent(Int.self, forKey: .cellCount) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, rateHz, size, phase, spread, attribute, fixtureIDs, order, enabled, direction, cellCount
    }
}
