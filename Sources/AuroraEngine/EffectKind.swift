import Foundation

/// Built-in effect generator kinds (PR22).
public enum EffectKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Relative sine LFO on a single attribute.
    case pulse
    /// Sequential absolute value on one fixture at a time.
    case chase
    /// Sine LFO with phase spread across fixtures (same math as pulse; distinct kind for UI defaults).
    case wave
    /// HSV rainbow written to colorR / colorG / colorB.
    case rainbow
}
