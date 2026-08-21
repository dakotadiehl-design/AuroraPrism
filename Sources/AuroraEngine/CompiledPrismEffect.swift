import AuroraModel
import Foundation

public enum CompiledEffectPropertyMapping: Equatable, Sendable {
    case intensity(attribute: String)
    case colorGradient
    case movement
    case pattern
    case scalarFan(attribute: String, start: Double, end: Double)
}

public struct CompiledEffectColorGradient: Equatable, Sendable {
    public let stops: [EffectGradientStop]
    public let interpolation: EffectColorInterpolation
    public let reversed: Bool
    public let mirrored: Bool
    public let positionOffset: Double

    public init?(_ definition: EffectColorGradientDefinition, paletteColors: [UUID: EffectColor] = [:]) {
        let resolved = definition.stops.map { stop -> EffectGradientStop in
            guard let paletteID = stop.paletteID, let color = paletteColors[paletteID] else { return stop }
            var copy = stop; copy.color = color; return copy
        }
        let sorted = resolved.sorted {
            $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position
        }
        guard !sorted.isEmpty else { return nil }
        self.stops = sorted
        self.interpolation = definition.interpolation
        self.reversed = definition.reversed
        self.mirrored = definition.mirrored
        self.positionOffset = definition.positionOffset
    }
}

/// Immutable effect representation consumed by the real-time evaluator.
///
/// Compilation is the boundary for reference resolution, validation, target
/// ordering, compatibility checks, and other work that must not run per frame.
public struct CompiledPrismEffect: Equatable, Sendable, Identifiable {
    public var id: UUID { source.id }
    public let source: EffectInstance
    public let resolvedTargets: [ResolvedEffectTarget]
    public var targets: [EffectTargetID] { resolvedTargets.map(\.target) }
    public let timing: CompiledEffectTiming?
    public let generator: CompiledEffectGenerator?
    public let waveformSamples: [Double]
    public let propertyMapping: CompiledEffectPropertyMapping?
    public let colorGradient: CompiledEffectColorGradient?
    public let movement: CompiledEffectMovement?
    public let pattern: CompiledEffectPattern?
    public let parameterDescriptors: [EffectParameterDescriptor]
    public let compatibilityIssues: [EffectCompatibilityIssue]

    public init(
        source: EffectInstance,
        resolvedTargets: [ResolvedEffectTarget],
        timing: CompiledEffectTiming? = nil,
        generator: CompiledEffectGenerator? = nil,
        waveformSamples: [Double] = [],
        propertyMapping: CompiledEffectPropertyMapping? = nil,
        colorGradient: CompiledEffectColorGradient? = nil,
        movement: CompiledEffectMovement? = nil,
        pattern: CompiledEffectPattern? = nil,
        parameterDescriptors: [EffectParameterDescriptor],
        compatibilityIssues: [EffectCompatibilityIssue] = []
    ) {
        self.source = source
        self.resolvedTargets = resolvedTargets
        self.timing = timing
        self.generator = generator
        self.waveformSamples = waveformSamples
        self.propertyMapping = propertyMapping
        self.colorGradient = colorGradient
        self.movement = movement
        self.pattern = pattern
        self.parameterDescriptors = parameterDescriptors
        self.compatibilityIssues = compatibilityIssues
    }
}

public struct EffectCompatibilityIssue: Equatable, Hashable, Sendable, Identifiable {
    public enum Severity: String, Sendable { case warning, unsupported }

    public let id: String
    public let severity: Severity
    public let message: String
    public let target: EffectTargetID?

    public init(id: String, severity: Severity, message: String, target: EffectTargetID? = nil) {
        self.id = id
        self.severity = severity
        self.message = message
        self.target = target
    }
}

/// First compiler implementation. It deliberately retains legacy `rateHz` semantics
/// exactly; later V2 definitions can compile into this same immutable boundary.
public enum PrismEffectCompiler {
    public static func compile(_ effect: EffectInstance, context: EffectDistributionContext = .init()) -> CompiledPrismEffect {
        let resolution = resolveTemplate(for: effect, context: context)
        let compiled = compileResolved(resolution.effect, context: context)
        guard !resolution.issues.isEmpty else { return compiled }
        let blocksEvaluation = resolution.issues.contains { $0.severity == .unsupported }
        return CompiledPrismEffect(
            source: compiled.source,
            resolvedTargets: blocksEvaluation ? [] : compiled.resolvedTargets,
            timing: compiled.timing,
            generator: compiled.generator,
            waveformSamples: compiled.waveformSamples,
            propertyMapping: compiled.propertyMapping,
            colorGradient: compiled.colorGradient,
            movement: compiled.movement,
            pattern: compiled.pattern,
            parameterDescriptors: compiled.parameterDescriptors,
            compatibilityIssues: compiled.compatibilityIssues + resolution.issues
        )
    }

    private static func compileResolved(_ effect: EffectInstance, context: EffectDistributionContext) -> CompiledPrismEffect {
        if let scalarFan = effect.scalarFan {
            return compileScalarFan(effect, definition: scalarFan, context: context)
        }
        if effect.kind == .movement, let movement = effect.movement {
            return compileMovement(effect, definition: movement, context: context)
        }
        if effect.kind == .pattern, let pattern = effect.pattern {
            return compilePattern(effect, definition: pattern, context: context)
        }
        if effect.kind == .colorGradient, let definition = effect.colorGradient {
            return compileColorGradient(effect, definition: definition, context: context)
        }
        guard let generatorDefinition = effect.generator else { return compileLegacy(effect, context: context) }
        let targets = targets(for: effect, context: context)
        let resolvedTargets = resolveTargets(effect, targets: targets, definition: distribution(for: effect), context: context)
        let generator = CompiledEffectGenerator(definition: generatorDefinition)
        let isCurveFamily = effect.kind == .wave || effect.kind == .pulse
        let attribute = effect.attribute.isEmpty ? "intensity" : effect.attribute
        let isIntensity = attribute == "intensity"
        let propertyMapping: CompiledEffectPropertyMapping? = isCurveFamily && isIntensity
            ? .intensity(attribute: attribute)
            : nil
        var issues: [EffectCompatibilityIssue] = []
        issues.append(contentsOf: cellCompatibilityIssues(for: effect, context: context))
        if !isCurveFamily {
            issues.append(.init(id: "generator.unsupported-family", severity: .unsupported, message: "Curve generators require an intensity curve effect family."))
        } else if !isIntensity {
            issues.append(.init(id: "generator.unsupported-property", severity: .unsupported, message: "FX-4 curve generators support the semantic intensity property only."))
        }
        var compiledTiming: CompiledEffectTiming?
        if var timing = effect.timing {
            // `EffectInstance.phase` is the canonical phase parameter shared by
            // legacy and V2 effects. Runtime timing supplies cycle progression.
            timing.phase = 0
            compiledTiming = EffectTimingCompiler.compile(timing)
        }
        return CompiledPrismEffect(
            source: effect,
            resolvedTargets: resolvedTargets,
            timing: compiledTiming,
            generator: generator,
            waveformSamples: EffectGeneratorEvaluator.samples(generator: generator, count: 129).map {
                min(1, max(0, effect.base + effect.size * $0))
            },
            propertyMapping: propertyMapping,
            parameterDescriptors: descriptors(for: effect.kind),
            compatibilityIssues: issues
        )
    }

    private static func compilePattern(_ effect: EffectInstance, definition: EffectPatternDefinition, context: EffectDistributionContext) -> CompiledPrismEffect {
        let resolved = resolveTargets(effect, targets: targets(for: effect, context: context), definition: distribution(for: effect), context: context)
        let pattern = CompiledEffectPattern(definition: definition)
        var timing: CompiledEffectTiming?
        if var timingDefinition = effect.timing { timingDefinition.phase = 0; timing = EffectTimingCompiler.compile(timingDefinition) }
        return CompiledPrismEffect(
            source: effect, resolvedTargets: resolved, timing: timing, waveformSamples: pattern.previewSamples,
            propertyMapping: .pattern, pattern: pattern, parameterDescriptors: descriptors(for: effect.kind),
            compatibilityIssues: cellCompatibilityIssues(for: effect, context: context)
        )
    }

    private static func compileScalarFan(
        _ effect: EffectInstance,
        definition: EffectScalarFanDefinition,
        context: EffectDistributionContext
    ) -> CompiledPrismEffect {
        let targets = targets(for: effect, context: context)
        let resolved = resolveTargets(effect, targets: targets, definition: distribution(for: effect), context: context)
        return CompiledPrismEffect(
            source: effect,
            resolvedTargets: resolved,
            propertyMapping: .scalarFan(attribute: definition.attribute, start: definition.start, end: definition.end),
            parameterDescriptors: descriptors(for: effect.kind) + [
                EffectParameterDescriptor(id: .fanStart, displayName: "Fan Start", unit: .percent, range: 0...1, defaultValue: 0),
                EffectParameterDescriptor(id: .fanEnd, displayName: "Fan End", unit: .percent, range: 0...1, defaultValue: 1),
            ],
            compatibilityIssues: cellCompatibilityIssues(for: effect, context: context)
        )
    }

    private static func compileMovement(
        _ effect: EffectInstance,
        definition: EffectMovementDefinition,
        context: EffectDistributionContext
    ) -> CompiledPrismEffect {
        let targets = targets(for: effect, context: context)
        let resolved = resolveTargets(effect, targets: targets, definition: distribution(for: effect), context: context)
        let invalidCustom = definition.template == .customPath && definition.customPath.isEmpty
        let movement = invalidCustom ? nil : CompiledEffectMovement(definition: definition)
        var timing: CompiledEffectTiming?
        if var timingDefinition = effect.timing {
            timingDefinition.phase = 0
            timing = EffectTimingCompiler.compile(timingDefinition)
        }
        return CompiledPrismEffect(
            source: effect,
            resolvedTargets: resolved,
            timing: timing,
            propertyMapping: movement == nil ? nil : .movement,
            movement: movement,
            parameterDescriptors: descriptors(for: effect.kind),
            compatibilityIssues: cellCompatibilityIssues(for: effect, context: context) + (invalidCustom
                ? [.init(id: "movement.empty-path", severity: .unsupported, message: "A custom movement path requires at least one point.")]
                : [])
        )
    }

    private static func compileColorGradient(
        _ effect: EffectInstance,
        definition: EffectColorGradientDefinition,
        context: EffectDistributionContext
    ) -> CompiledPrismEffect {
        let targets = targets(for: effect, context: context)
        let resolved = resolveTargets(effect, targets: targets, definition: distribution(for: effect), context: context)
        guard let gradient = CompiledEffectColorGradient(definition, paletteColors: context.paletteColors) else {
            return CompiledPrismEffect(
                source: effect,
                resolvedTargets: resolved,
                parameterDescriptors: descriptors(for: effect.kind),
                compatibilityIssues: cellCompatibilityIssues(for: effect, context: context) + [.init(id: "gradient.empty", severity: .unsupported, message: "A color gradient requires at least one stop.")]
            )
        }
        let generator = effect.generator.map(CompiledEffectGenerator.init)
        var timing: CompiledEffectTiming?
        if effect.generator != nil, var timingDefinition = effect.timing {
            timingDefinition.phase = 0
            timing = EffectTimingCompiler.compile(timingDefinition)
        }
        let missingPalettes = definition.stops.compactMap(\.paletteID).filter { context.paletteColors[$0] == nil }
        return CompiledPrismEffect(
            source: effect,
            resolvedTargets: resolved,
            timing: timing,
            generator: generator,
            waveformSamples: generator.map { EffectGeneratorEvaluator.samples(generator: $0, count: 129) } ?? [],
            propertyMapping: .colorGradient,
            colorGradient: gradient,
            parameterDescriptors: descriptors(for: effect.kind),
            compatibilityIssues: cellCompatibilityIssues(for: effect, context: context) + missingPalettes.map {
                .init(id: "gradient.missing-palette.\($0.uuidString)", severity: .warning, message: "A linked gradient palette is missing; its literal fallback color is being used.")
            }
        )
    }

    public static func compileLegacy(_ effect: EffectInstance, context: EffectDistributionContext = .init()) -> CompiledPrismEffect {
        let targets = targets(for: effect, context: context)
        let resolvedTargets = resolveTargets(
            effect,
            targets: targets,
            definition: effect.cellTargeting == nil ? FixtureDistributionDefinition(order: .selection) : distribution(for: effect),
            context: context
        ).map { target in
            guard effect.direction < 0, targets.count > 1 else { return target }
            return ResolvedEffectTarget(
                target: target.target,
                orderIndex: target.orderIndex,
                distributionPosition: 1 - target.distributionPosition
            )
        }
        return CompiledPrismEffect(
            source: effect,
            resolvedTargets: resolvedTargets,
            parameterDescriptors: descriptors(for: effect.kind),
            compatibilityIssues: cellCompatibilityIssues(for: effect, context: context)
        )
    }

    private static func descriptors(for kind: EffectKind) -> [EffectParameterDescriptor] {
        var result = [
            EffectParameterDescriptor(id: .speed, displayName: "Speed", unit: .hertz, range: 0...100, defaultValue: 1),
            EffectParameterDescriptor(id: .amplitude, displayName: "Amplitude", unit: .percent, range: 0...1, defaultValue: 0.5),
            EffectParameterDescriptor(id: .phase, displayName: "Phase", unit: .normalized, range: 0...1, defaultValue: 0),
            EffectParameterDescriptor(id: .spread, displayName: "Fixture Spread", unit: .normalized, range: 0...1, defaultValue: 0),
            EffectParameterDescriptor(id: .blendAmount, displayName: "Layer Amount", unit: .percent, range: 0...1, defaultValue: 1),
            EffectParameterDescriptor(id: .distributionGrouping, displayName: "Distribution Grouping", unit: .count, range: 1...64, defaultValue: 1),
        ]
        if kind == .positionCircle || kind == .movement {
            result.append(
                EffectParameterDescriptor(id: .movementSize, displayName: "Movement Size", unit: .percent, range: 0...1, defaultValue: 0.5)
            )
        }
        if kind == .movement {
            result.append(contentsOf: [
                EffectParameterDescriptor(id: .movementWidth, displayName: "Movement Width", unit: .percent, range: 0...1, defaultValue: 0.5),
                EffectParameterDescriptor(id: .movementHeight, displayName: "Movement Height", unit: .percent, range: 0...1, defaultValue: 0.5),
                EffectParameterDescriptor(id: .movementRotation, displayName: "Movement Rotation", unit: .normalized, range: -1...1, defaultValue: 0),
                EffectParameterDescriptor(id: .movementCenterPan, displayName: "Pan Center", unit: .normalized, range: 0...1, defaultValue: 0.5),
                EffectParameterDescriptor(id: .movementCenterTilt, displayName: "Tilt Center", unit: .normalized, range: 0...1, defaultValue: 0.5),
            ])
        }
        if kind == .colorGradient {
            result.append(EffectParameterDescriptor(id: .gradientPosition, displayName: "Gradient Position", unit: .normalized, range: 0...1, defaultValue: 0))
        }
        if kind == .pattern {
            result.append(contentsOf: [
                EffectParameterDescriptor(id: .patternWidth, displayName: "Pattern Width", unit: .percent, range: 0...1, defaultValue: 0.2),
                EffectParameterDescriptor(id: .patternSoftness, displayName: "Pattern Softness", unit: .percent, range: 0...1, defaultValue: 0.1),
                EffectParameterDescriptor(id: .patternDensity, displayName: "Pattern Density", unit: .percent, range: 0...1, defaultValue: 0.2),
                EffectParameterDescriptor(id: .patternTrail, displayName: "Pattern Trail", unit: .percent, range: 0...1, defaultValue: 0.3),
            ])
        }
        result.append(EffectParameterDescriptor(id: .cellGrouping, displayName: "Cell Grouping", unit: .count, range: 1...64, defaultValue: 1))
        return result
    }

    private static func targets(for effect: EffectInstance, context: EffectDistributionContext) -> [EffectTargetID] {
        let expanded: [EffectTargetID]
        guard let targeting = effect.cellTargeting else {
            return effect.fixtureIDs.map { EffectTargetID(fixtureID: $0) }
        }
        switch targeting.mode {
        case .fixtures:
            expanded = effect.fixtureIDs.map { EffectTargetID(fixtureID: $0) }
        case .selectedCells:
            let eligible = Set(effect.fixtureIDs)
            expanded = targeting.selectedTargets.filter { target in
                guard eligible.contains(target.fixtureID), let elementID = target.elementID else { return false }
                guard let knownElements = context.fixtureElementIDs[target.fixtureID] else { return true }
                return knownElements.contains(elementID)
            }
        case .allCells:
            expanded = effect.fixtureIDs.flatMap { fixtureID -> [EffectTargetID] in
                let ids = context.fixtureElementIDs[fixtureID] ?? []
                let ordered: [String] = targeting.order == .forward ? ids : Array(ids.reversed())
                if ids.isEmpty { return [EffectTargetID(fixtureID: fixtureID)] }
                return ordered.map { EffectTargetID(fixtureID: fixtureID, elementID: $0) }
            }
        }
        return expanded
    }

    private static func distribution(for effect: EffectInstance) -> FixtureDistributionDefinition {
        var definition = effect.distribution ?? FixtureDistributionDefinition()
        if let cellGrouping = effect.cellTargeting?.grouping { definition.grouping = max(1, definition.grouping * cellGrouping) }
        return definition
    }

    private static func cellCompatibilityIssues(for effect: EffectInstance, context: EffectDistributionContext) -> [EffectCompatibilityIssue] {
        var issues: [EffectCompatibilityIssue] = []
        if effect.mask?.kind == .selectedTargets && effect.mask?.selectedTargets.isEmpty == true {
            issues.append(.init(id: "mask.empty-selection", severity: .unsupported, message: "The selected-target mask has no targets."))
        }
        if effect.mask?.kind == .fixtureGroup {
            if let groupID = effect.mask?.fixtureGroupID, context.fixtureGroups[groupID] != nil {
                // Resolved below.
            } else {
                issues.append(.init(id: "mask.missing-group", severity: .unsupported, message: "The fixture-group mask references a missing group."))
            }
        }
        guard let targeting = effect.cellTargeting, targeting.mode != .fixtures else { return issues }
        if targeting.mode == .selectedCells && targets(for: effect, context: context).isEmpty {
            issues.append(.init(id: "cells.empty-selection", severity: .unsupported, message: "The effect has no valid selected cells."))
        }
        if targeting.mode == .selectedCells {
            let eligible = Set(effect.fixtureIDs)
            for target in targeting.selectedTargets {
                let isKnown = target.elementID.map { context.fixtureElementIDs[target.fixtureID]?.contains($0) ?? true } ?? false
                if !eligible.contains(target.fixtureID) || !isKnown {
                    issues.append(.init(id: "cells.invalid.\(target.fixtureID.uuidString).\(target.elementID ?? "fixture")", severity: .warning, message: "A selected cell no longer exists and was ignored.", target: target))
                }
            }
        }
        if targeting.mode == .allCells {
            for fixtureID in effect.fixtureIDs where context.fixtureElementIDs[fixtureID]?.isEmpty == true {
                issues.append(.init(id: "cells.fixture-fallback.\(fixtureID.uuidString)", severity: .warning, message: "This fixture has no logical cells; the whole fixture is targeted instead.", target: .init(fixtureID: fixtureID)))
            }
        }
        return issues
    }

    private static func resolveTargets(
        _ effect: EffectInstance,
        targets: [EffectTargetID],
        definition: FixtureDistributionDefinition,
        context: EffectDistributionContext
    ) -> [ResolvedEffectTarget] {
        let resolved = EffectDistributionResolver.resolve(targets: targets, definition: definition, context: context)
        guard let mask = effect.mask, mask.kind != .none else { return resolved }
        let count = resolved.count
        switch mask.kind {
        case .none: return resolved
        case .fixtureGroup:
            guard let groupID = mask.fixtureGroupID, let members = context.fixtureGroups[groupID] else { return [] }
            return resolved.filter { members.contains($0.target.fixtureID) }
        case .odd: return resolved.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? nil : $0.element }
        case .even: return resolved.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
        case .firstHalf: return Array(resolved.prefix((count + 1) / 2))
        case .secondHalf: return Array(resolved.suffix(count / 2))
        case .center:
            guard count > 0 else { return [] }
            return count.isMultiple(of: 2) ? Array(resolved[(count / 2 - 1)...(count / 2)]) : [resolved[count / 2]]
        case .edges:
            guard count > 1 else { return resolved }
            return [resolved[0], resolved[count - 1]]
        case .everyNth:
            let stride = max(1, mask.everyNth)
            return resolved.enumerated().compactMap { $0.offset.isMultiple(of: stride) ? $0.element : nil }
        case .selectedTargets:
            let selected = Set(mask.selectedTargets)
            return resolved.filter { selected.contains($0.target) }
        case .spatialRegion:
            var placements: [UUID: StageFixturePlacement] = [:]
            for placement in context.stagePlacements where placements[placement.fixtureID] == nil { placements[placement.fixtureID] = placement }
            return resolved.filter { target in
                guard let placement = placements[target.target.fixtureID] else { return false }
                return (mask.minimumX...mask.maximumX).contains(placement.x) && (mask.minimumY...mask.maximumY).contains(placement.y)
            }
        }
    }

    private static func resolveTemplate(for instance: EffectInstance, context: EffectDistributionContext) -> (effect: EffectInstance, issues: [EffectCompatibilityIssue]) {
        guard instance.templateLinkMode == .linked, let firstID = instance.templateEffectID else { return (instance, []) }
        var templateID: UUID? = firstID
        var visited: Set<UUID> = [instance.id]
        var resolvedTemplate: EffectInstance?
        while let currentID = templateID {
            guard visited.insert(currentID).inserted else {
                return (instance, [.init(id: "template.cycle", severity: .unsupported, message: "The linked effect template contains a cycle.")])
            }
            guard let candidate = context.templateEffects[currentID] else {
                return (instance, [.init(id: "template.missing.\(currentID.uuidString)", severity: .unsupported, message: "The linked effect template is missing.")])
            }
            resolvedTemplate = candidate
            templateID = candidate.templateLinkMode == .linked ? candidate.templateEffectID : nil
        }
        guard var resolved = resolvedTemplate else { return (instance, []) }
        // Template owns creative parameters. The instance owns identity, target,
        // stack placement, enablement, composition, and its durable link.
        resolved.id = instance.id
        resolved.name = instance.name
        resolved.fixtureIDs = instance.fixtureIDs
        resolved.order = instance.order
        resolved.enabled = instance.enabled
        resolved.blendMode = instance.blendMode
        resolved.blendAmount = instance.blendAmount
        resolved.mask = instance.mask
        resolved.cellTargeting = instance.cellTargeting
        resolved.templateEffectID = instance.templateEffectID
        resolved.templateLinkMode = instance.templateLinkMode
        resolved.isFavorite = instance.isFavorite
        return (resolved, [])
    }
}
