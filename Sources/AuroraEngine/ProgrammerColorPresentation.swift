import AuroraModel
import Foundation

// MARK: - Color Engine presentation (capability-driven)

public struct EmitterControlPresentation: Equatable, Sendable, Identifiable {
    public var id: String { attribute }
    public var kind: ColorEmitterKind
    public var attribute: String
    public var state: ProgrammerAttributeState
    public var accent: EmitterAccent

    public init(
        kind: ColorEmitterKind,
        attribute: String? = nil,
        state: ProgrammerAttributeState,
        accent: EmitterAccent? = nil
    ) {
        self.kind = kind
        self.attribute = attribute ?? kind.attribute
        self.state = state
        self.accent = accent ?? EmitterAccent.forKind(kind)
    }
}

public struct ColorSwatchDefinition: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var hue: Double
    public var saturation: Double
    public var brightness: Double

    public init(name: String, hue: Double, saturation: Double = 1, brightness: Double = 1) {
        self.name = name
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    public var authoring: ColorAuthoringState {
        ColorAuthoringState(hue: hue, saturation: saturation, brightness: brightness, whiteBalance: 0)
    }
}

/// Pure Color tab presentation for the current ordered selection.
public struct ProgrammerColorPresentation: Equatable, Sendable {
    public var orderedFixtureIDs: [UUID]
    public var dimmer: ProgrammerAttributeState
    public var hasRGB: Bool
    public var hue: Double?
    public var saturation: Double?
    public var brightness: Double?
    public var whiteBalance: Double?
    public var isRGBMixed: Bool
    public var isAuthoringMixed: Bool
    public var previewRGB: RGBColor
    public var emitters: [EmitterControlPresentation]
    public var swatches: [ColorSwatchDefinition]

    public init(
        orderedFixtureIDs: [UUID] = [],
        dimmer: ProgrammerAttributeState = .unsupported,
        hasRGB: Bool = false,
        hue: Double? = nil,
        saturation: Double? = nil,
        brightness: Double? = nil,
        whiteBalance: Double? = nil,
        isRGBMixed: Bool = false,
        isAuthoringMixed: Bool = false,
        previewRGB: RGBColor = RGBColor(r: 0, g: 0, b: 0),
        emitters: [EmitterControlPresentation] = [],
        swatches: [ColorSwatchDefinition] = ProgrammerColorPresentation.defaultSwatches
    ) {
        self.orderedFixtureIDs = orderedFixtureIDs
        self.dimmer = dimmer
        self.hasRGB = hasRGB
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
        self.whiteBalance = whiteBalance
        self.isRGBMixed = isRGBMixed
        self.isAuthoringMixed = isAuthoringMixed
        self.previewRGB = previewRGB
        self.emitters = emitters
        self.swatches = swatches
    }

    public static let empty = ProgrammerColorPresentation()

    public static let defaultSwatches: [ColorSwatchDefinition] = [
        .init(name: "White", hue: 0, saturation: 0, brightness: 1),
        .init(name: "Red", hue: 0),
        .init(name: "Orange", hue: 30),
        .init(name: "Yellow", hue: 55),
        .init(name: "Green", hue: 120),
        .init(name: "Cyan", hue: 180),
        .init(name: "Blue", hue: 220),
        .init(name: "Purple", hue: 275),
        .init(name: "Magenta", hue: 310),
    ]

    public var authoring: ColorAuthoringState {
        ColorAuthoringState(
            hue: hue ?? 0,
            saturation: saturation ?? 1,
            brightness: brightness ?? 1,
            whiteBalance: whiteBalance ?? 0
        )
    }
}

public enum ProgrammerColorPresentationResolver {
    /// Dedicated emitter attributes considered for the right-hand column.
    /// Full UI order (W / WW / CW / A / Lime / Cyan / UV) so Cool White fixtures
    /// (e.g. Shehds RGBWA+UV) get a White fader, not only generic `colorW`.
    public static let dedicatedEmitterAttributes: [String] = ColorEmitterKind.dedicatedUIOrder.map(\.attribute)

    public static func resolve(
        orderedFixtureIDs: [UUID],
        project: ShowProject,
        programmer: ProgrammerState
    ) -> ProgrammerColorPresentation {
        guard !orderedFixtureIDs.isEmpty else { return .empty }

        let base = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: orderedFixtureIDs,
            project: project,
            programmer: programmer
        )
        let caps = ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: orderedFixtureIDs,
            project: project
        )
        let values = programmer.values

        let hasRGB = base.hasRGBColor
        let isRGBMixed = base.isRGBMixed

        // Authoring: prefer first-class keys; fall back to RGB inverse (WB = 0).
        let hueState = resolveAuthoring(
            ColorAuthoringAttribute.hue,
            ordered: orderedFixtureIDs,
            hasRGB: hasRGB,
            caps: caps,
            values: values
        )
        let satState = resolveAuthoring(
            ColorAuthoringAttribute.saturation,
            ordered: orderedFixtureIDs,
            hasRGB: hasRGB,
            caps: caps,
            values: values
        )
        let valState = resolveAuthoring(
            ColorAuthoringAttribute.brightness,
            ordered: orderedFixtureIDs,
            hasRGB: hasRGB,
            caps: caps,
            values: values
        )
        let wbState = resolveAuthoring(
            ColorAuthoringAttribute.whiteBalance,
            ordered: orderedFixtureIDs,
            hasRGB: hasRGB,
            caps: caps,
            values: values
        )

        var hue = hueState.displayValue
        var sat = satState.displayValue
        var bri = valState.displayValue
        var wb = wbState.displayValue
        var authoringMixed = [hueState, satState, valState, wbState].contains(where: \.isMixed)

        let anyAuthoring = [hue, sat, bri, wb].contains { $0 != nil }
        if !anyAuthoring, hasRGB, !isRGBMixed,
           let r = base.colorR.displayValue,
           let g = base.colorG.displayValue,
           let b = base.colorB.displayValue {
            let auth = ColorMath.authoringFromRGB(RGBColor(r: r, g: g, b: b))
            hue = auth.hue
            sat = auth.saturation
            bri = auth.brightness
            wb = 0
        } else if !anyAuthoring, hasRGB, isRGBMixed {
            authoringMixed = true
        }

        let authoring = ColorAuthoringState(
            hue: hue ?? 0,
            saturation: sat ?? (hasRGB ? 0.85 : 0),
            brightness: bri ?? (hasRGB ? 1 : 0),
            whiteBalance: wb ?? 0
        )
        let preview: RGBColor
        if hasRGB, !authoringMixed || hue != nil {
            preview = ColorMath.resolvedRGB(from: authoring)
        } else if hasRGB, isRGBMixed {
            preview = RGBColor(r: 0.45, g: 0.45, b: 0.5)
        } else {
            preview = RGBColor(r: 0.15, g: 0.15, b: 0.18)
        }

        // Emitters: show if any selected fixture supports; partial via state.support.
        // Use dedicatedUIOrder so Cool/Warm White appear beside Amber/UV when present.
        var emitters: [EmitterControlPresentation] = []
        for kind in ColorEmitterKind.dedicatedUIOrder {
            let attr = kind.attribute
            let supported = orderedFixtureIDs.contains { caps[$0]?.contains(attr) == true }
            guard supported else { continue }
            let state = ProgrammerAttributePresentationResolver.resolveAttribute(
                attr,
                ordered: orderedFixtureIDs,
                caps: caps,
                values: values
            )
            emitters.append(EmitterControlPresentation(kind: kind, state: state))
        }

        return ProgrammerColorPresentation(
            orderedFixtureIDs: orderedFixtureIDs,
            dimmer: base.intensity,
            hasRGB: hasRGB,
            hue: hue,
            saturation: sat,
            brightness: bri,
            whiteBalance: wb,
            isRGBMixed: isRGBMixed || authoringMixed,
            isAuthoringMixed: authoringMixed,
            previewRGB: preview,
            emitters: emitters
        )
    }

    /// Authoring attributes apply to fixtures that support RGB (not fixture DMX channels).
    private static func resolveAuthoring(
        _ attribute: String,
        ordered: [UUID],
        hasRGB: Bool,
        caps: [UUID: Set<String>],
        values: [UUID: [String: Double]]
    ) -> ProgrammerAttributeState {
        guard hasRGB else { return .unsupported }
        let capable = ordered.filter {
            caps[$0]?.contains("colorR") == true
                || caps[$0]?.contains("colorG") == true
                || caps[$0]?.contains("colorB") == true
        }
        guard !capable.isEmpty else { return .unsupported }
        let support: AttributeSupportState = capable.count == ordered.count ? .all : .partial
        var found: [Double] = []
        for id in capable {
            if let v = values[id]?[attribute] {
                found.append(v)
            }
        }
        if found.isEmpty {
            return ProgrammerAttributeState(support: support, value: .untouched)
        }
        if found.count < capable.count {
            return ProgrammerAttributeState(support: support, value: .mixed)
        }
        let first = found[0]
        let allSame = found.allSatisfy { abs($0 - first) < 1e-6 }
        if allSame {
            return ProgrammerAttributeState(support: support, value: .common(first))
        }
        return ProgrammerAttributeState(support: support, value: .mixed)
    }

    /// Fixtures that receive RGB / authoring color writes.
    public static func rgbCapableIDs(
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [UUID] {
        let caps = ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: orderedFixtureIDs,
            project: project
        )
        return orderedFixtureIDs.filter {
            let c = caps[$0] ?? []
            return c.contains("colorR") || c.contains("colorG") || c.contains("colorB")
        }
    }
}
