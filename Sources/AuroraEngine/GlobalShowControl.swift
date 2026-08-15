import Foundation

/// Authoritative show-level safety / live controls (Lightkey parity P0-I / PR-P1).
/// Applied after look merge, before physical output and preview presentation.
public struct GlobalShowControlState: Equatable, Sendable {
    /// Scales intensity attributes globally (0…1). Does not rewrite programmer/cue stores.
    public var masterIntensity: Double
    /// Zero intensity path on resolved output; reversible.
    public var blackout: Bool
    /// Holds last resolved multi-universe frame for physical+preview while playback may advance.
    public var freeze: Bool
    /// When true, programmer does not contribute to live output (also settable via Programmer).
    public var blind: Bool
    /// When false, MIDI performance behaviors / mappings that mutate live state are ignored.
    public var midiPerformanceEnabled: Bool

    public init(
        masterIntensity: Double = 1,
        blackout: Bool = false,
        freeze: Bool = false,
        blind: Bool = false,
        midiPerformanceEnabled: Bool = true
    ) {
        self.masterIntensity = min(1, max(0, masterIntensity))
        self.blackout = blackout
        self.freeze = freeze
        self.blind = blind
        self.midiPerformanceEnabled = midiPerformanceEnabled
    }

    public static let `default` = GlobalShowControlState()
}

/// Applies global controls to a resolved look and/or DMX frame.
public enum GlobalShowControl {
    /// True intensity/dimmer masters (not RGB emitters).
    public static let dimmerAttributes: Set<String> = [
        "intensity", "dimmer", "dim",
    ]

    /// Color emitter attributes — scaled by master **only** when no dimmer attribute is present.
    public static let colorEmitterAttributes: Set<String> = [
        "colorR", "colorG", "colorB", "colorW", "colorA", "colorC", "colorM", "colorY",
    ]

    /// Scale look by master; blackout zeros dimmers (and color-only fixtures).
    /// When a fixture has intensity/dimmer, master scales **only** that channel (preserves chromatic ratios).
    /// When a fixture has only color emitters, master scales those emitters once.
    public static func applyToLook(_ look: ActiveLook, state: GlobalShowControlState) -> ActiveLook {
        guard state.blackout || state.masterIntensity < 0.999 else { return look }
        var result = look
        for (fixtureID, attrs) in look.fixtureAttributes {
            var next = attrs
            let hasDimmer = attrs.keys.contains { isDimmerAttribute($0) }
            for key in attrs.keys {
                if state.blackout {
                    if isDimmerAttribute(key) || (!hasDimmer && isColorEmitter(key)) {
                        next[key] = 0
                    }
                } else if isDimmerAttribute(key) {
                    next[key] = (attrs[key] ?? 0) * state.masterIntensity
                } else if !hasDimmer && isColorEmitter(key) {
                    next[key] = (attrs[key] ?? 0) * state.masterIntensity
                }
            }
            result.fixtureAttributes[fixtureID] = next
        }
        return result
    }

    public static func isDimmerAttribute(_ attribute: String) -> Bool {
        let lower = attribute.lowercased()
        if dimmerAttributes.contains(attribute) || dimmerAttributes.contains(lower) { return true }
        return lower.contains("intens") || lower == "dimmer" || lower == "dim"
    }

    public static func isColorEmitter(_ attribute: String) -> Bool {
        let lower = attribute.lowercased()
        if colorEmitterAttributes.contains(attribute) || colorEmitterAttributes.contains(lower) { return true }
        return lower.hasPrefix("color") && !isDimmerAttribute(attribute)
    }
}
