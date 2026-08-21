import AuroraModel
import Foundation

/// Read-only semantic presentation for 2D Stage Live Preview (P0-A).
/// Derived from the same resolved path as physical output — never a second engine.
public struct PreviewColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }

    public static let black = PreviewColor(r: 0, g: 0, b: 0)
}

public struct FixturePreviewState: Equatable, Sendable, Identifiable {
    public var id: UUID { fixtureID }
    public var fixtureID: UUID
    public var intensity: Double
    public var color: PreviewColor?
    public var pan: Double?
    public var tilt: Double?
    public var isHighlight: Bool
    public var elements: [FixtureElementPreviewState]
    /// Live state projected onto stable physical-emitter identities.
    public var physicalEmitters: [FixtureElementPreviewState]
    public var environmental: [String: Double]

    public init(
        fixtureID: UUID,
        intensity: Double = 0,
        color: PreviewColor? = nil,
        pan: Double? = nil,
        tilt: Double? = nil,
        isHighlight: Bool = false,
        elements: [FixtureElementPreviewState] = [],
        physicalEmitters: [FixtureElementPreviewState] = [],
        environmental: [String: Double] = [:]
    ) {
        self.fixtureID = fixtureID
        self.intensity = min(1, max(0, intensity))
        self.color = color
        self.pan = pan
        self.tilt = tilt
        self.isHighlight = isHighlight
        self.elements = elements
        self.physicalEmitters = physicalEmitters
        self.environmental = environmental
    }
}

public struct FixtureElementPreviewState: Equatable, Sendable, Identifiable {
    public var id: String { elementID }
    public var elementID: String
    public var intensity: Double
    public var color: PreviewColor?

    public init(elementID: String, intensity: Double = 0, color: PreviewColor? = nil) {
        self.elementID = elementID
        self.intensity = min(1, max(0, intensity))
        self.color = color
    }
}

public struct StagePreviewSnapshot: Equatable, Sendable {
    public var frameIndex: UInt64
    public var timestamp: TimeInterval
    public var fixtures: [FixturePreviewState]
    public var dominantColor: PreviewColor
    public var blackout: Bool
    public var freeze: Bool
    public var masterIntensity: Double

    public init(
        frameIndex: UInt64 = 0,
        timestamp: TimeInterval = 0,
        fixtures: [FixturePreviewState] = [],
        dominantColor: PreviewColor = .black,
        blackout: Bool = false,
        freeze: Bool = false,
        masterIntensity: Double = 1
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.fixtures = fixtures
        self.dominantColor = dominantColor
        self.blackout = blackout
        self.freeze = freeze
        self.masterIntensity = masterIntensity
    }

    public static let empty = StagePreviewSnapshot()
}

/// Builds stage preview from a resolved ActiveLook (same authority as DMX merge).
public enum StagePreviewBuilder {
    public static func build(
        project: ShowProject,
        look: ActiveLook,
        frameIndex: UInt64,
        time: TimeInterval,
        global: GlobalShowControlState
    ) -> StagePreviewSnapshot {
        var fixtures: [FixturePreviewState] = []
        var weightedR = 0.0, weightedG = 0.0, weightedB = 0.0, weight = 0.0

        for fx in project.fixtures {
            let attrs = look.fixtureAttributes[fx.id] ?? [:]
            let definition = project.definition(id: fx.definitionId)
            let elementStates = definition?.elements.map { element in
                elementPreview(element: element, attributes: attrs, definition: definition)
            } ?? []
            let descriptor = definition.map { project.visualizationDescriptor(for: $0) }
            let physicalStates = definition.map {
                physicalEmitterPreviews(
                    descriptor: descriptor,
                    controlStates: elementStates,
                    mappings: $0.emitterMappings,
                    fixtureAttributes: attrs,
                    definition: $0
                )
            } ?? []
            var environmental: [String: Double] = [:]
            for indicator in descriptor?.indicators ?? [] {
                environmental[indicator.attribute] = attrs[indicator.attribute] ?? 0
            }
            let intensity = elementStates.map(\.intensity).max()
                ?? effectiveBeamLevel(attributes: attrs, definition: definition)
            let color = summaryColor(elements: elementStates) ?? previewColor(attributes: attrs, suffix: nil)
            fixtures.append(FixturePreviewState(
                fixtureID: fx.id,
                intensity: intensity,
                color: color,
                pan: attrs["pan"],
                tilt: attrs["tilt"],
                elements: elementStates,
                physicalEmitters: physicalStates,
                environmental: environmental
            ))
            let w = intensity
            if w > 0.001 {
                if let color {
                    weightedR += color.r * w
                    weightedG += color.g * w
                    weightedB += color.b * w
                } else {
                    weightedR += w
                    weightedG += w
                    weightedB += w
                }
                weight += w
            }
        }

        let dominant: PreviewColor
        if weight > 0.001 {
            dominant = PreviewColor(
                r: weightedR / weight,
                g: weightedG / weight,
                b: weightedB / weight
            )
        } else {
            dominant = .black
        }

        return StagePreviewSnapshot(
            frameIndex: frameIndex,
            timestamp: time,
            fixtures: fixtures,
            dominantColor: dominant,
            blackout: global.blackout,
            freeze: global.freeze,
            masterIntensity: global.masterIntensity
        )
    }

    private static func physicalEmitterPreviews(
        descriptor: FixtureVisualizationDescriptor?,
        controlStates: [FixtureElementPreviewState],
        mappings: [FixtureEmitterMapping],
        fixtureAttributes: [String: Double],
        definition: FixtureDefinition
    ) -> [FixtureElementPreviewState] {
        guard let descriptor else { return [] }
        let controls = Dictionary(uniqueKeysWithValues: controlStates.map { ($0.elementID, $0) })
        return descriptor.emitters.map { emitter in
            var relevant = mappings.filter { $0.physicalEmitterIDs.contains(emitter.id) }
            if relevant.isEmpty {
                let adapted = FixturePhysicalControlMapper.resolve(
                    physicalEmitterID: emitter.id,
                    descriptor: descriptor,
                    definition: definition
                )
                if case .controls(let controlIDs) = adapted.disposition, !controlIDs.isEmpty {
                    relevant = [FixtureEmitterMapping(
                        id: "preview-adapter-\(emitter.id)",
                        controlElementIDs: controlIDs,
                        physicalEmitterIDs: [emitter.id],
                        combination: .direct
                    )]
                }
            }
            let contributions = relevant.compactMap { mapping -> FixtureElementPreviewState? in
                let states = mapping.controlElementIDs.compactMap { controls[$0] }
                guard !states.isEmpty else { return nil }
                return combine(states: states, rule: mapping.combination, id: mapping.id)
            }
            if contributions.isEmpty {
                // A physical aperture without an independent control still reflects
                // shared fixture-wide output. It never acquires a control identity.
                return FixtureElementPreviewState(
                    elementID: emitter.id,
                    intensity: effectiveBeamLevel(attributes: fixtureAttributes, definition: definition),
                    color: previewColor(attributes: fixtureAttributes, suffix: nil)
                )
            }
            let intensity = min(1, contributions.map(\.intensity).reduce(0, +))
            let colored = contributions.compactMap { contribution -> (PreviewColor, Double)? in
                guard let color = contribution.color else { return nil }
                return (color, max(contribution.intensity, 0.0001))
            }
            let color: PreviewColor?
            if colored.isEmpty {
                color = nil
            } else {
                let weight = colored.reduce(0) { $0 + $1.1 }
                color = PreviewColor(
                    r: colored.reduce(0) { $0 + $1.0.r * $1.1 } / weight,
                    g: colored.reduce(0) { $0 + $1.0.g * $1.1 } / weight,
                    b: colored.reduce(0) { $0 + $1.0.b * $1.1 } / weight
                )
            }
            return FixtureElementPreviewState(elementID: emitter.id, intensity: intensity, color: color)
        }
    }

    private static func combine(
        states: [FixtureElementPreviewState],
        rule: FixtureEmitterCombinationRule,
        id: String
    ) -> FixtureElementPreviewState {
        let levels = states.map(\.intensity)
        let level: Double
        switch rule {
        case .average: level = levels.reduce(0, +) / Double(levels.count)
        case .additive, .component: level = min(1, levels.reduce(0, +))
        case .master: level = levels.reduce(1, *)
        case .maximum, .direct, .customFallback: level = levels.max() ?? 0
        }
        let colored = states.compactMap { state -> (PreviewColor, Double)? in
            guard let color = state.color else { return nil }
            return (color, max(state.intensity, 0.0001))
        }
        guard !colored.isEmpty else { return .init(elementID: id, intensity: level) }
        let color: PreviewColor
        switch rule {
        case .maximum, .customFallback:
            color = colored.max(by: { $0.1 < $1.1 })!.0
        case .additive, .component:
            color = PreviewColor(
                r: colored.reduce(0) { $0 + $1.0.r * $1.1 },
                g: colored.reduce(0) { $0 + $1.0.g * $1.1 },
                b: colored.reduce(0) { $0 + $1.0.b * $1.1 }
            )
        case .average, .direct, .master:
            let weight = colored.reduce(0) { $0 + $1.1 }
            color = PreviewColor(
                r: colored.reduce(0) { $0 + $1.0.r * $1.1 } / weight,
                g: colored.reduce(0) { $0 + $1.0.g * $1.1 } / weight,
                b: colored.reduce(0) { $0 + $1.0.b * $1.1 } / weight
            )
        }
        return .init(elementID: id, intensity: level, color: color)
    }

    private static func elementPreview(
        element: FixtureElement,
        attributes: [String: Double],
        definition: FixtureDefinition?
    ) -> FixtureElementPreviewState {
        let explicitOwner = definition?.channels.contains { $0.elementID == element.id } == true
        let suffix = explicitOwner ? "@\(element.id)" : "@\(element.index)"
        // Keep shared fixture attributes, then overlay only this element's values.
        // Other cells must not contribute brightness/color to this element.
        var scoped = attributes.filter { !$0.key.contains("@") }
        // Absent cell emitter values mean DMX zero, not an uncolored open beam.
        let elementChannels = explicitOwner
            ? (definition?.channels.filter { $0.elementID == element.id } ?? [])
            : (definition?.cellBlock?.channels ?? [])
        for channel in elementChannels
        where ColorEmitterKind.isPhysicalEmitter(channel.attribute) {
            scoped[channel.attribute] = 0
        }
        for (key, value) in attributes where key.hasSuffix(suffix) {
            scoped[String(key.dropLast(suffix.count))] = value
        }
        return FixtureElementPreviewState(
            elementID: element.id,
            intensity: effectiveBeamLevel(attributes: scoped, definition: definition),
            color: previewColor(attributes: attributes, suffix: suffix) ?? previewColor(attributes: attributes, suffix: nil)
        )
    }

    private static func previewColor(attributes: [String: Double], suffix: String?) -> PreviewColor? {
        let tail = suffix ?? ""
        // Approximate visible chroma for every physical emitter. This is deliberately
        // presentation-only; DMX output continues to use the personality's raw channels.
        let emitterColors: [(String, Double, Double, Double)] = [
            ("colorR", 1.00, 0.00, 0.00),
            ("colorG", 0.00, 1.00, 0.00),
            ("colorB", 0.00, 0.00, 1.00),
            ("colorW", 1.00, 1.00, 1.00),
            ("colorWarmWhite", 1.00, 0.72, 0.42),
            ("colorWW", 1.00, 0.72, 0.42),
            ("colorCoolWhite", 0.72, 0.86, 1.00),
            ("colorCW", 0.72, 0.86, 1.00),
            ("colorA", 1.00, 0.32, 0.01),
            ("colorUV", 0.48, 0.06, 1.00),
            ("colorLime", 0.62, 1.00, 0.05),
            ("colorCyan", 0.00, 1.00, 1.00),
            ("colorC", 0.00, 1.00, 1.00),
            ("colorM", 1.00, 0.00, 1.00),
            ("colorY", 1.00, 1.00, 0.00),
        ]
        var r = 0.0, g = 0.0, b = 0.0
        var found = false
        for (attribute, cr, cg, cb) in emitterColors {
            guard let level = attributes["\(attribute)\(tail)"] else { continue }
            found = true
            r += level * cr
            g += level * cg
            b += level * cb
        }
        guard found else { return nil }
        let peak = max(r, max(g, b))
        let divisor = peak > 1e-9 ? peak : 1
        return PreviewColor(r: r / divisor, g: g / divisor, b: b / divisor)
    }

    private static func summaryColor(elements: [FixtureElementPreviewState]) -> PreviewColor? {
        let lit = elements.filter { $0.intensity > 0.001 && $0.color != nil }
        guard !lit.isEmpty else { return nil }
        let weight = lit.reduce(0.0) { $0 + $1.intensity }
        guard weight > 0 else { return nil }
        return PreviewColor(
            r: lit.reduce(0.0) { $0 + ($1.color?.r ?? 0) * $1.intensity } / weight,
            g: lit.reduce(0.0) { $0 + ($1.color?.g ?? 0) * $1.intensity } / weight,
            b: lit.reduce(0.0) { $0 + ($1.color?.b ?? 0) * $1.intensity } / weight
        )
    }

    /// Approximate emitted light from the already-resolved semantic look.
    /// Physical-dimmer fixtures combine dimmer and active color brightness;
    /// color-only fixtures combine their virtual dimmer with emitter output.
    public static func effectiveBeamLevel(
        attributes: [String: Double],
        definition: FixtureDefinition?
    ) -> Double {
        let physicalAttributes = definition.map {
            $0.channels.map(\.attribute) + ($0.cellBlock?.channels.map(\.attribute) ?? [])
        } ?? []
        let hasPhysicalDimmer = physicalAttributes.contains(where: GlobalShowControl.isDimmerAttribute)
        let dimmer = attributes["intensity"] ?? attributes["dimmer"] ?? attributes["dim"]
        let colorValue = attributes[ColorAuthoringAttribute.brightness]
        let rgbAttributes = Set(ColorEmitterKind.rgbAttributes)
        let rgbPeak = attributes.reduce(0.0) { partial, item in
            let base = item.key.split(separator: "@").first.map(String.init) ?? item.key
            guard rgbAttributes.contains(base) else { return partial }
            return max(partial, item.value)
        }
        let dedicatedPeak = attributes.reduce(0.0) { partial, item in
            let base = item.key.split(separator: "@").first.map(String.init) ?? item.key
            guard ColorEmitterKind.isPhysicalEmitter(base), !rgbAttributes.contains(base) else { return partial }
            return max(partial, item.value)
        }
        let hasRGBData = attributes.keys.contains { key in
            let base = key.split(separator: "@").first.map(String.init) ?? key
            return rgbAttributes.contains(base)
        }
        let hasDedicatedData = attributes.keys.contains { key in
            let base = key.split(separator: "@").first.map(String.init) ?? key
            return ColorEmitterKind.isPhysicalEmitter(base) && !rgbAttributes.contains(base)
        }
        let emitterPeak = max(rgbPeak, dedicatedPeak)
        let hasEmitterData = hasRGBData || hasDedicatedData

        let level: Double
        if hasPhysicalDimmer {
            // HSV value belongs to the RGB color engine only. Dedicated emitters
            // (white variants, amber, UV, etc.) remain independently controlled.
            let rgbLevel = hasRGBData ? rgbPeak : (colorValue ?? 0)
            let chromaticLevel = hasEmitterData ? max(rgbLevel, dedicatedPeak) : (colorValue ?? 1)
            level = (dimmer ?? 0) * chromaticLevel
        } else if hasEmitterData {
            level = (dimmer ?? 1) * emitterPeak
        } else {
            level = dimmer ?? 0
        }
        return min(1, max(0, level))
    }
}
