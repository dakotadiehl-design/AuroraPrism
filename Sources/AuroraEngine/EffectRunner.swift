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
    /// First-wins on duplicate IDs (never traps — Post-C6 audit).
    public func load(definitions: [EffectDefinition]) {
        lock.lock()
        var map: [UUID: EffectInstance] = [:]
        map.reserveCapacity(definitions.count)
        for def in definitions {
            if map[def.id] == nil {
                map[def.id] = EffectInstance(definition: def)
            }
        }
        effects = map
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
        case .pulse, .wave, .beamPulse:
            return applySine(look: look, time: time, effect: effect)
        case .chase:
            return applyChase(look: look, time: time, effect: effect)
        case .rainbow:
            return applyRainbow(look: look, time: time, effect: effect)
        case .positionCircle:
            return applyPositionCircle(look: look, time: time, effect: effect)
        case .colorStep:
            return applyColorStep(look: look, time: time, effect: effect)
        case .cellChase:
            return applyCellChase(look: look, time: time, effect: effect)
        }
    }

    private static func phaseForFixture(effect: EffectInstance, index: Int) -> Double {
        let n = effect.fixtureIDs.count
        let span = max(n - 1, 1)
        let orderedIndex = effect.direction < 0 ? (n - 1 - index) : index
        return effect.phase + effect.spread * (Double(orderedIndex) / Double(span))
    }

    private static func applySine(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let attr = effect.kind == .beamPulse
            ? (effect.attribute.isEmpty || effect.attribute == "intensity" ? "zoom" : effect.attribute)
            : effect.attribute
        for (index, fixtureID) in effect.fixtureIDs.enumerated() {
            let phase = phaseForFixture(effect: effect, index: index)
            let angle = 2 * Double.pi * (effect.rateHz * time * effect.direction + phase)
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
        let step = effect.rateHz * time * effect.direction + effect.phase
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
            let hueFrac = fract(effect.rateHz * time * effect.direction + phase)
            let rgb = ColorMath.rgb(from: HSVColor(h: hueFrac * 360, s: 1, v: value))
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            attrs["colorR"] = rgb.r
            attrs["colorG"] = rgb.g
            attrs["colorB"] = rgb.b
            result.fixtureAttributes[fixtureID] = attrs
        }
        return result
    }

    private static func applyPositionCircle(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let radius = effect.size * 0.5
        for (index, fixtureID) in effect.fixtureIDs.enumerated() {
            let phase = phaseForFixture(effect: effect, index: index)
            let angle = 2 * Double.pi * (effect.rateHz * time * effect.direction + phase)
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            attrs["pan"] = clamp01(0.5 + radius * cos(angle))
            attrs["tilt"] = clamp01(0.5 + radius * sin(angle))
            result.fixtureAttributes[fixtureID] = attrs
        }
        return result
    }

    private static func applyColorStep(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let colors: [(Double, Double, Double)] = [
            (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1), (1, 0, 1),
        ]
        let step = Int(floor(effect.rateHz * time * effect.direction + effect.phase * Double(colors.count)))
        for (index, fixtureID) in effect.fixtureIDs.enumerated() {
            let ci = ((step + index) % colors.count + colors.count) % colors.count
            let c = colors[ci]
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            attrs["colorR"] = c.0 * effect.size
            attrs["colorG"] = c.1 * effect.size
            attrs["colorB"] = c.2 * effect.size
            result.fixtureAttributes[fixtureID] = attrs
        }
        return result
    }

    /// Chases `attribute@cellN` (default colorR) across cells on each fixture.
    private static func applyCellChase(look: ActiveLook, time: TimeInterval, effect: EffectInstance) -> ActiveLook {
        var result = look
        let baseAttr = effect.attribute.contains("@")
            ? String(effect.attribute.split(separator: "@").first ?? "colorR")
            : (effect.attribute.isEmpty ? "colorR" : effect.attribute)
        let cells = max(1, effect.cellCount > 0 ? effect.cellCount : 8)
        let step = effect.rateHz * time * effect.direction + effect.phase
        let activeCell = Int(floor(step * Double(cells)).truncatingRemainder(dividingBy: Double(cells)))
        let active = ((activeCell % cells) + cells) % cells
        for fixtureID in effect.fixtureIDs {
            var attrs = result.fixtureAttributes[fixtureID] ?? [:]
            for c in 0..<cells {
                attrs["\(baseAttr)@\(c)"] = c == active ? effect.size : 0
            }
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
