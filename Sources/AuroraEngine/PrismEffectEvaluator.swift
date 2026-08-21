import AuroraModel
import Foundation

/// Evaluator-owned metadata used by graphs and previews. UI code renders these
/// samples and must not independently reproduce generator or phase mathematics.
public struct EffectVisualizationMetadata: Equatable, Sendable {
    public struct TargetSample: Equatable, Sendable, Identifiable {
        public var id: EffectTargetID { target }
        public let target: EffectTargetID
        public let orderIndex: Int
        public let distributionPosition: Double
        public let phase: Double
        public let value: Double?
        public let pan: Double?
        public let tilt: Double?

        public init(
            target: EffectTargetID,
            orderIndex: Int,
            distributionPosition: Double,
            phase: Double,
            value: Double?,
            pan: Double? = nil,
            tilt: Double? = nil
        ) {
            self.target = target
            self.orderIndex = orderIndex
            self.distributionPosition = distributionPosition
            self.phase = phase
            self.value = value
            self.pan = pan
            self.tilt = tilt
        }
    }

    public let normalizedTime: Double
    public let targets: [TargetSample]
    /// One compiled cycle from the same generator used for semantic output.
    public let waveformSamples: [Double]
    public let waveformDirection: Double
    public let playheadPhase: Double
    public let timingStatus: EffectTimingStatus?
    public let clockSourceID: String?
    public let movementPathSamples: [EffectMovementPoint]

    public init(
        normalizedTime: Double,
        targets: [TargetSample],
        waveformSamples: [Double] = [],
        waveformDirection: Double = 1,
        playheadPhase: Double? = nil,
        timingStatus: EffectTimingStatus? = nil,
        clockSourceID: String? = nil,
        movementPathSamples: [EffectMovementPoint] = []
    ) {
        self.normalizedTime = normalizedTime
        self.targets = targets
        self.waveformSamples = waveformSamples
        self.waveformDirection = waveformDirection >= 0 ? 1 : -1
        self.playheadPhase = playheadPhase ?? normalizedTime
        self.timingStatus = timingStatus
        self.clockSourceID = clockSourceID
        self.movementPathSamples = movementPathSamples
    }
}

/// One authoritative evaluator result for output, Stage preview, and editor visuals.
public struct EffectEvaluationResult: Equatable, Sendable {
    public let semanticLook: ActiveLook
    public let visualizations: [UUID: EffectVisualizationMetadata]
    public let timingSamples: [UUID: EffectTimingSample]

    public init(
        semanticLook: ActiveLook,
        visualizations: [UUID: EffectVisualizationMetadata],
        timingSamples: [UUID: EffectTimingSample] = [:]
    ) {
        self.semanticLook = semanticLook
        self.visualizations = visualizations
        self.timingSamples = timingSamples
    }
}

/// Timing inputs for one evaluator frame. Missing entries intentionally fall
/// back to the exact legacy `rateHz × time` behavior during migration.
public struct EffectEvaluationContext: Equatable, Sendable {
    public var legacyTime: TimeInterval
    public var timingSamples: [UUID: EffectTimingSample]

    public init(legacyTime: TimeInterval, timingSamples: [UUID: EffectTimingSample] = [:]) {
        self.legacyTime = legacyTime
        self.timingSamples = timingSamples
    }
}

public enum PrismEffectEvaluator {
    /// Evaluates legacy effects without changing their established timing or merge behavior.
    public static func evaluate(
        baseLook: ActiveLook,
        time: TimeInterval,
        effects: [CompiledPrismEffect]
    ) -> EffectEvaluationResult {
        let ordered = effects.sorted {
            if $0.source.order != $1.source.order { return $0.source.order < $1.source.order }
            return $0.id.uuidString < $1.id.uuidString
        }

        return evaluateOrdered(baseLook: baseLook, context: .init(legacyTime: time), effects: ordered)
    }

    /// Real-time entry point for a stack already sorted and filtered during compilation.
    public static func evaluateOrdered(
        baseLook: ActiveLook,
        time: TimeInterval,
        effects: [CompiledPrismEffect]
    ) -> EffectEvaluationResult {
        evaluateOrdered(baseLook: baseLook, context: .init(legacyTime: time), effects: effects)
    }

    /// FX-2 entry point. Semantic output and visualization metadata consume the
    /// same normalized timing samples; no UI-side timing math is required.
    public static func evaluateOrdered(
        baseLook: ActiveLook,
        context: EffectEvaluationContext,
        effects: [CompiledPrismEffect]
    ) -> EffectEvaluationResult {
        var look = baseLook
        var visualizations: [UUID: EffectVisualizationMetadata] = [:]
        for compiled in effects where compiled.source.enabled && !compiled.targets.isEmpty {
            if let timing = context.timingSamples[compiled.id], !timing.isActive { continue }
            let result = evaluateOne(baseLook: look, context: context, effect: compiled)
            look = result.look
            visualizations[compiled.id] = result.metadata
        }
        return EffectEvaluationResult(semanticLook: look, visualizations: visualizations, timingSamples: context.timingSamples)
    }

    private static func evaluateOne(
        baseLook: ActiveLook,
        context: EffectEvaluationContext,
        effect compiled: CompiledPrismEffect
    ) -> (look: ActiveLook, metadata: EffectVisualizationMetadata) {
        let effect = compiled.source
        var result = baseLook
        var samples: [EffectVisualizationMetadata.TargetSample] = []
        let count = compiled.resolvedTargets.count
        let timingPhase = context.timingSamples[compiled.id]?.phase
            ?? effect.rateHz * context.legacyTime
        let cycle = timingPhase * effect.direction
        let normalizedTime = fract(cycle)

        for (index, resolvedTarget) in compiled.resolvedTargets.enumerated() {
            let target = resolvedTarget.target
            let position = resolvedTarget.distributionPosition
            let phase = effect.phase + effect.spread * position
            var visualValue: Double?

            if case let .scalarFan(attribute, start, end)? = compiled.propertyMapping {
                let value = clamp01(start + (end - start) * position)
                set(value, attribute: attribute, target: target, effect: effect, look: &result)
                samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: phase, value: value))
                continue
            }

            if let pattern = compiled.pattern, compiled.propertyMapping == .pattern {
                let patternSample = pattern.sample(position: position, phase: cycle + effect.phase)
                let value = clamp01(effect.base + effect.size * patternSample.value)
                if let hue = patternSample.hue {
                    let rgb = ColorMath.rgb(from: HSVColor(h: hue, s: 1, v: value))
                    set(rgb.r, attribute: "colorR", target: target, effect: effect, look: &result)
                    set(rgb.g, attribute: "colorG", target: target, effect: effect, look: &result)
                    set(rgb.b, attribute: "colorB", target: target, effect: effect, look: &result)
                } else {
                    set(value, attribute: effect.attribute.isEmpty ? "intensity" : effect.attribute, target: target, effect: effect, look: &result)
                }
                visualValue = value
                samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: fract(cycle + effect.phase), value: value))
                continue
            }

            if let movement = compiled.movement, compiled.propertyMapping == .movement {
                let point = movement.point(at: cycle + phase)
                let centerPan = movement.definition.coordinateMode == .relative
                    ? (currentValue(attribute: "pan", target: target, look: result) ?? movement.definition.centerPan)
                    : movement.definition.centerPan
                let centerTilt = movement.definition.coordinateMode == .relative
                    ? (currentValue(attribute: "tilt", target: target, look: result) ?? movement.definition.centerTilt)
                    : movement.definition.centerTilt
                let pan = clamp01(centerPan + point.x)
                let tilt = clamp01(centerTilt + point.y)
                set(pan, attribute: "pan", target: target, effect: effect, look: &result)
                set(tilt, attribute: "tilt", target: target, effect: effect, look: &result)
                visualValue = fract(cycle + phase)
                samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: fract(cycle + phase), value: visualValue, pan: pan, tilt: tilt))
                continue
            }

            if let gradient = compiled.colorGradient, compiled.propertyMapping == .colorGradient {
                let animation = compiled.generator.map {
                    (EffectGeneratorEvaluator.value(generator: $0, phase: cycle + effect.phase) - 0.5) * effect.size
                } ?? 0
                let gradientPosition = position + effect.phase + animation
                let color = EffectColorGradientEvaluator.color(at: gradientPosition, gradient: gradient)
                set(color.r, attribute: "colorR", target: target, effect: effect, look: &result)
                set(color.g, attribute: "colorG", target: target, effect: effect, look: &result)
                set(color.b, attribute: "colorB", target: target, effect: effect, look: &result)
                visualValue = fract(gradientPosition)
                samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: fract(cycle + effect.phase), value: visualValue))
                continue
            }

            if let generator = compiled.generator {
                guard case let .intensity(attribute)? = compiled.propertyMapping else {
                    samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: fract(cycle + phase), value: nil))
                    continue
                }
                let generated = EffectGeneratorEvaluator.value(generator: generator, phase: cycle + phase)
                let value = clamp01(effect.base + effect.size * generated)
                set(value, attribute: attribute, target: target, effect: effect, look: &result)
                visualValue = value
                samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: fract(cycle + phase), value: visualValue))
                continue
            }

            switch effect.kind {
            case .pulse, .wave, .beamPulse:
                let attribute = effect.kind == .beamPulse
                    ? (effect.attribute.isEmpty || effect.attribute == "intensity" ? "zoom" : effect.attribute)
                    : effect.attribute
                let offset = effect.size * sin(2 * Double.pi * (cycle + phase))
                let base = result.fixtureAttributes[target.fixtureID]?[attribute] ?? 0
                let value = clamp01(base + offset)
                set(value, attribute: attribute, target: target, effect: effect, look: &result)
                visualValue = value

            case .chase:
                let step = cycle + effect.phase
                let raw = Int(floor(step * Double(count)).truncatingRemainder(dividingBy: Double(count)))
                let active = ((raw % count) + count) % count
                let value = index == active ? effect.size : 0
                set(value, attribute: effect.attribute, target: target, effect: effect, look: &result)
                visualValue = value

            case .rainbow:
                let hue = fract(cycle + phase)
                let rgb = ColorMath.rgb(from: HSVColor(h: hue * 360, s: 1, v: max(0.5, effect.size)))
                set(rgb.r, attribute: "colorR", target: target, effect: effect, look: &result)
                set(rgb.g, attribute: "colorG", target: target, effect: effect, look: &result)
                set(rgb.b, attribute: "colorB", target: target, effect: effect, look: &result)
                visualValue = hue

            case .positionCircle:
                let angle = 2 * Double.pi * (cycle + phase)
                let radius = effect.size * 0.5
                set(clamp01(0.5 + radius * cos(angle)), attribute: "pan", target: target, effect: effect, look: &result)
                set(clamp01(0.5 + radius * sin(angle)), attribute: "tilt", target: target, effect: effect, look: &result)
                visualValue = fract(angle / (2 * Double.pi))

            case .movement:
                break
            case .pattern:
                break

            case .colorStep:
                let colors: [(Double, Double, Double)] = [
                    (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1), (1, 0, 1),
                ]
                let step = Int(floor(cycle + effect.phase * Double(colors.count)))
                let colorIndex = ((step + index) % colors.count + colors.count) % colors.count
                let color = colors[colorIndex]
                set(color.0 * effect.size, attribute: "colorR", target: target, effect: effect, look: &result)
                set(color.1 * effect.size, attribute: "colorG", target: target, effect: effect, look: &result)
                set(color.2 * effect.size, attribute: "colorB", target: target, effect: effect, look: &result)
                visualValue = Double(colorIndex) / Double(colors.count)

            case .colorGradient:
                break

            case .cellChase:
                let baseAttribute = effect.attribute.contains("@")
                    ? String(effect.attribute.split(separator: "@").first ?? "colorR")
                    : (effect.attribute.isEmpty ? "colorR" : effect.attribute)
                let cells = max(1, effect.cellCount > 0 ? effect.cellCount : 8)
                let step = cycle + effect.phase
                let raw = Int(floor(step * Double(cells)).truncatingRemainder(dividingBy: Double(cells)))
                let active = ((raw % cells) + cells) % cells
                for cell in 0..<cells {
                    var cellTarget = target
                    cellTarget.elementID = FixtureElement.cellID(index: cell)
                    set(cell == active ? effect.size : 0, attribute: baseAttribute, target: cellTarget, effect: effect, look: &result)
                }
                visualValue = Double(active) / Double(cells)
            }

            samples.append(.init(target: target, orderIndex: index, distributionPosition: position, phase: phase, value: visualValue))
        }

        return (
            result,
            EffectVisualizationMetadata(
                normalizedTime: normalizedTime,
                targets: samples,
                waveformSamples: compiled.waveformSamples,
                waveformDirection: effect.direction,
                playheadPhase: fract(cycle + effect.phase),
                timingStatus: context.timingSamples[compiled.id]?.status,
                clockSourceID: context.timingSamples[compiled.id]?.sourceID,
                movementPathSamples: compiled.movement?.pathSamples ?? []
            )
        )
    }

    private static func set(_ value: Double, attribute: String, target: EffectTargetID, effect: EffectInstance, look: inout ActiveLook) {
        var attributes = look.fixtureAttributes[target.fixtureID] ?? [:]
        let key = attributeKey(attribute: attribute, target: target)
        let current = attributes[key] ?? 0
        let composed: Double
        switch effect.blendMode {
        case .replace: composed = value
        case .add: composed = current + value
        case .multiply: composed = current * value
        case .maximum: composed = max(current, value)
        case .minimum: composed = min(current, value)
        }
        attributes[key] = clamp01(current + (composed - current) * effect.blendAmount)
        look.fixtureAttributes[target.fixtureID] = attributes
    }

    private static func currentValue(attribute: String, target: EffectTargetID, look: ActiveLook) -> Double? {
        look.fixtureAttributes[target.fixtureID]?[attributeKey(attribute: attribute, target: target)]
    }

    private static func attributeKey(attribute: String, target: EffectTargetID) -> String {
        if let elementID = target.elementID, let cellIndex = FixtureElement.cellIndex(from: elementID) {
            return "\(attribute)@\(cellIndex)"
        } else if let elementID = target.elementID {
            return "\(attribute)@\(elementID)"
        } else {
            return attribute
        }
    }

    private static func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func fract(_ value: Double) -> Double {
        let fraction = value - floor(value)
        return fraction < 0 ? fraction + 1 : fraction
    }
}
