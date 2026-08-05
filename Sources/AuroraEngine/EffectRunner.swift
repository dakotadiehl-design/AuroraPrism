import AuroraModel
import Foundation

/// Owns live effect instances and applies them to an `ActiveLook` (PR22 / P1-4).
///
/// Thread-safe for engine tick + main-thread control. Apply order is explicit
/// `EffectInstance.order` (not UUID).
public final class EffectRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var effects: [UUID: EffectInstance] = [:]
    private var nextOrder: Int = 0

    public init() {}

    public func upsert(_ effect: EffectInstance) {
        lock.lock()
        var effect = effect
        if effects[effect.id] == nil {
            // New effect: append to end of stack when order left at default 0 and stack non-empty.
            if effect.order == 0, let maxOrder = effects.values.map(\.order).max() {
                effect.order = maxOrder + 1
            }
            nextOrder = max(nextOrder, effect.order + 1)
        }
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
        nextOrder = 0
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

    /// Replace runtime set from durable project definitions.
    public func load(definitions: [EffectDefinition]) {
        lock.lock()
        effects = Dictionary(uniqueKeysWithValues: definitions.map { def in
            let instance = EffectInstance(definition: def)
            return (instance.id, instance)
        })
        nextOrder = (effects.values.map(\.order).max() ?? -1) + 1
        lock.unlock()
    }

    /// Export durable definitions in apply order.
    public func exportDefinitions() -> [EffectDefinition] {
        snapshot().map { $0.asDefinition() }
    }

    /// Ordered snapshot: lower `order` first, then stable id.
    public func snapshot() -> [EffectInstance] {
        lock.lock()
        defer { lock.unlock() }
        return effects.values.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
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
        let ordered = effects.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
        for effect in ordered where effect.enabled {
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

    private static func applyChase(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let n = effect.fixtureIDs.count
        guard n > 0 else { return result }
        let attr = effect.attribute
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
