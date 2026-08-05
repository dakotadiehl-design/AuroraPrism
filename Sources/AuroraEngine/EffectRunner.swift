import Foundation

/// Owns live effect instances and applies them to an `ActiveLook` (PR22).
///
/// Thread-safe for engine tick + main-thread control. Apply is pure given a snapshot of instances.
public final class EffectRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var effects: [UUID: EffectInstance] = [:]

    public init() {}

    public func upsert(_ effect: EffectInstance) {
        lock.lock()
        effects[effect.id] = effect
        lock.unlock()
    }

    public func remove(id: UUID) {
        lock.lock()
        effects[id] = nil
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        effects.removeAll()
        lock.unlock()
    }

    public func setEnabled(id: UUID, enabled: Bool) {
        lock.lock()
        if var effect = effects[id] {
            effect.enabled = enabled
            effects[id] = effect
        }
        lock.unlock()
    }

    /// Stable ordered snapshot (by insertion is not guaranteed; sorted by id for determinism).
    public func snapshot() -> [EffectInstance] {
        lock.lock()
        defer { lock.unlock() }
        return effects.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public var runningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return effects.values.filter(\.enabled).count
    }

    /// Applies all enabled effects to `look` at engine time `time` (seconds).
    public func apply(on look: ActiveLook, time: TimeInterval) -> ActiveLook {
        let instances = snapshot().filter(\.enabled)
        guard !instances.isEmpty else { return look }
        return Self.apply(look: look, time: time, effects: instances)
    }

    /// Pure apply for tests and deterministic evaluation.
    public static func apply(
        look: ActiveLook,
        time: TimeInterval,
        effects: [EffectInstance]
    ) -> ActiveLook {
        var result = look
        for effect in effects where effect.enabled {
            guard !effect.fixtureIDs.isEmpty else { continue }
            result = applyOne(look: result, time: time, effect: effect)
        }
        return result
    }

    // MARK: - Generators

    private static func applyOne(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        switch effect.kind {
        case .pulse, .wave:
            return applySine(look: look, time: time, effect: effect)
        case .chase:
            return applyChase(look: look, time: time, effect: effect)
        case .rainbow:
            return applyRainbow(look: look, time: time, effect: effect)
        }
    }

    private static func phaseForFixture(effect: EffectInstance, index: Int) -> Double {
        let n = effect.fixtureIDs.count
        let span = max(n - 1, 1)
        return effect.phase + effect.spread * (Double(index) / Double(span))
    }

    /// Relative sine: clamp(base + size * sin(2π · (rate·t + phase_i))).
    private static func applySine(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let attr = effect.attribute
        for (index, fixtureID) in effect.fixtureIDs.enumerated() {
            let phase = phaseForFixture(effect: effect, index: index)
            let angle = 2 * Double.pi * (effect.rateHz * time + phase)
            let offset = effect.size * sin(angle)
            let base = result.fixtureAttributes[fixtureID]?[attr] ?? 0
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            attrs[attr] = clamp01(base + offset)
            result.fixtureAttributes[fixtureID] = attrs
        }
        return result
    }

    /// Absolute chase on `attribute`: one fixture at `size`, others at 0.
    private static func applyChase(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let n = effect.fixtureIDs.count
        guard n > 0 else { return result }
        let attr = effect.attribute
        // Advance through fixtures at rateHz full cycles per second.
        let step = effect.rateHz * time + effect.phase
        let active = Int(floor(step * Double(n)).truncatingRemainder(dividingBy: Double(n)))
        let activeIndex = ((active % n) + n) % n

        for (index, fixtureID) in effect.fixtureIDs.enumerated() {
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            attrs[attr] = index == activeIndex ? effect.size : 0
            result.fixtureAttributes[fixtureID] = attrs
        }
        return result
    }

    /// Writes colorR/G/B from rotating hue.
    private static func applyRainbow(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let value = max(0.5, effect.size)
        for (index, fixtureID) in effect.fixtureIDs.enumerated() {
            let phase = phaseForFixture(effect: effect, index: index)
            let hueFrac = fract(effect.rateHz * time + phase)
            let rgb = ColorMath.rgb(from: HSVColor(h: hueFrac * 360, s: 1, v: value))
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            attrs["colorR"] = rgb.r
            attrs["colorG"] = rgb.g
            attrs["colorB"] = rgb.b
            result.fixtureAttributes[fixtureID] = attrs
        }
        return result
    }

    private static func clamp01(_ x: Double) -> Double {
        min(1, max(0, x))
    }

    private static func fract(_ x: Double) -> Double {
        let f = x - floor(x)
        return f < 0 ? f + 1 : f
    }
}
