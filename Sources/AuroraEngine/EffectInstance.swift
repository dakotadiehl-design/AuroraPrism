import Foundation

/// A live effect applied above playback and below the programmer (PR22).
///
/// Runtime-only in v1 — not yet persisted on the show document.
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
    public var enabled: Bool

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
        self.enabled = enabled
    }
}
