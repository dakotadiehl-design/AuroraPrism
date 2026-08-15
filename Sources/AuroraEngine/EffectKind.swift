import Foundation

/// Built-in effect generator kinds (PR22 + Pass-1 effect families).
public enum EffectKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Relative sine LFO on a single attribute.
    case pulse
    /// Sequential absolute value on one fixture at a time.
    case chase
    /// Sine LFO with phase spread across fixtures (same math as pulse; distinct kind for UI defaults).
    case wave
    /// HSV rainbow written to colorR / colorG / colorB.
    case rainbow
    /// Position circle on pan/tilt (movement family).
    case positionCircle
    /// Color step cycle through primaries (color family).
    case colorStep
    /// Multi-cell chase along `attr@cellN` attributes when present.
    case cellChase
    /// Beam zoom pulse (beam family).
    case beamPulse
}
