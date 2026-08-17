import AuroraModel
import Foundation

// MARK: - Orthogonal support × value (UI-03)

/// How many selected fixtures support a given attribute.
public enum AttributeSupportState: Equatable, Sendable {
    case none
    case partial
    case all
}

/// Programmer-owned values across capable fixtures in the selection.
public enum ProgrammerValueState: Equatable, Sendable {
    case untouched
    case common(Double)
    case mixed
}

public struct ProgrammerAttributeState: Equatable, Sendable {
    public var support: AttributeSupportState
    public var value: ProgrammerValueState

    public init(support: AttributeSupportState = .none, value: ProgrammerValueState = .untouched) {
        self.support = support
        self.value = value
    }

    public static let unsupported = ProgrammerAttributeState(support: .none, value: .untouched)

    public var isSupported: Bool { support != .none }

    public var displayValue: Double? {
        if case .common(let v) = value { return v }
        return nil
    }

    public var isMixed: Bool {
        if case .mixed = value { return true }
        return false
    }

    public var isUntouched: Bool {
        if case .untouched = value { return true }
        return false
    }

    /// First capable must have a programmer-owned value for Align to First.
    public var hasOwnedValue: Bool {
        if case .common = value { return true }
        if case .mixed = value { return true }
        return false
    }
}

/// Pure presentation of programmer state for the current ordered selection.
public struct ProgrammerAttributePresentation: Equatable, Sendable {
    public var orderedFixtureIDs: [UUID]
    public var intensity: ProgrammerAttributeState
    public var pan: ProgrammerAttributeState
    public var tilt: ProgrammerAttributeState
    public var colorR: ProgrammerAttributeState
    public var colorG: ProgrammerAttributeState
    public var colorB: ProgrammerAttributeState
    public var colorW: ProgrammerAttributeState
    /// Color channels the selection supports (stable order) for technical UI.
    public var technicalColorAttributes: [String]
    /// Beam family attributes supported by the selection (stable order).
    public var beamAttributes: [String]
    /// Shutter/strobe family attributes.
    public var strobeAttributes: [String]
    /// Generic / raw / remaining controllable attributes not covered above.
    public var genericAttributes: [String]
    /// Per-attribute state for beam/strobe/generic (key = attribute).
    public var extendedStates: [String: ProgrammerAttributeState]

    public init(
        orderedFixtureIDs: [UUID] = [],
        intensity: ProgrammerAttributeState = .unsupported,
        pan: ProgrammerAttributeState = .unsupported,
        tilt: ProgrammerAttributeState = .unsupported,
        colorR: ProgrammerAttributeState = .unsupported,
        colorG: ProgrammerAttributeState = .unsupported,
        colorB: ProgrammerAttributeState = .unsupported,
        colorW: ProgrammerAttributeState = .unsupported,
        technicalColorAttributes: [String] = [],
        beamAttributes: [String] = [],
        strobeAttributes: [String] = [],
        genericAttributes: [String] = [],
        extendedStates: [String: ProgrammerAttributeState] = [:]
    ) {
        self.orderedFixtureIDs = orderedFixtureIDs
        self.intensity = intensity
        self.pan = pan
        self.tilt = tilt
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.colorW = colorW
        self.technicalColorAttributes = technicalColorAttributes
        self.beamAttributes = beamAttributes
        self.strobeAttributes = strobeAttributes
        self.genericAttributes = genericAttributes
        self.extendedStates = extendedStates
    }

    public static let empty = ProgrammerAttributePresentation()

    public var hasIntensity: Bool { intensity.isSupported }
    public var hasPosition: Bool { pan.isSupported || tilt.isSupported }
    public var hasBeam: Bool { !beamAttributes.isEmpty }
    public var hasStrobe: Bool { !strobeAttributes.isEmpty }
    public var hasGeneric: Bool { !genericAttributes.isEmpty }

    /// HSV wheel only when selection has RGB mapping the wheel can write.
    public var hasRGBColor: Bool {
        colorR.isSupported || colorG.isSupported || colorB.isSupported
    }

    public var hasTechnicalColor: Bool {
        !technicalColorAttributes.isEmpty
    }

    /// Any color-related section (wheel and/or technical).
    public var hasColor: Bool {
        hasRGBColor || hasTechnicalColor
    }

    public var selectionCount: Int { orderedFixtureIDs.count }

    /// True when any of R/G/B is mixed (composite wheel should be indeterminate).
    public var isRGBMixed: Bool {
        [colorR, colorG, colorB].contains(where: \.isMixed)
    }

    public func state(for attribute: String) -> ProgrammerAttributeState {
        switch attribute {
        case "intensity": return intensity
        case "pan": return pan
        case "tilt": return tilt
        case "colorR": return colorR
        case "colorG": return colorG
        case "colorB": return colorB
        case "colorW": return colorW
        default: return extendedStates[attribute] ?? .unsupported
        }
    }
}

public enum ProgrammerAttributePresentationResolver {
    public static let primaryColorAttributes = ["colorR", "colorG", "colorB", "colorW"]
    public static let knownTechnicalColorExtras = [
        "colorA", "colorUV", "colorCoolWhite", "colorWarmWhite",
        "colorLime", "colorCyan", "cyan", "magenta", "yellow",
    ]
    public static let beamAttributeNames = [
        "zoom", "focus", "iris", "frost", "prism", "prismRotate", "gobo", "goboRotate",
        "goboIndex", "beam", "diffusion", "blade1", "blade2", "blade3", "blade4",
    ]
    public static let strobeAttributeNames = [
        "shutter", "strobe", "strobeRate", "strobeDuration", "shutterStrobe",
    ]
    private static let coreAttributes: Set<String> = [
        "intensity", "dimmer", "dim", "pan", "tilt",
        "colorR", "colorG", "colorB", "colorW",
        "colorA", "colorUV", "colorCoolWhite", "colorWarmWhite",
        "colorLime", "colorCyan", "cyan", "magenta", "yellow",
    ]

    public static func resolve(
        orderedFixtureIDs: [UUID],
        project: ShowProject,
        programmer: ProgrammerState
    ) -> ProgrammerAttributePresentation {
        guard !orderedFixtureIDs.isEmpty else { return .empty }

        let physicalCaps = physicalCapabilityMap(orderedFixtureIDs: orderedFixtureIDs, project: project)
        let caps = effectiveCapabilityMap(fromPhysical: physicalCaps)
        let values = programmer.values

        let intensity = resolveIntensity(
            ordered: orderedFixtureIDs,
            physicalCaps: physicalCaps,
            effectiveCaps: caps,
            values: values
        )
        let pan = resolveAttribute("pan", ordered: orderedFixtureIDs, caps: caps, values: values)
        let tilt = resolveAttribute("tilt", ordered: orderedFixtureIDs, caps: caps, values: values)
        let colorR = resolveAttribute("colorR", ordered: orderedFixtureIDs, caps: caps, values: values)
        let colorG = resolveAttribute("colorG", ordered: orderedFixtureIDs, caps: caps, values: values)
        let colorB = resolveAttribute("colorB", ordered: orderedFixtureIDs, caps: caps, values: values)
        let colorW = resolveAttribute("colorW", ordered: orderedFixtureIDs, caps: caps, values: values)

        // Technical list: supported color channels only (no dead loop).
        let tech = (Self.primaryColorAttributes + Self.knownTechnicalColorExtras).filter { attr in
            orderedFixtureIDs.contains { caps[$0]?.contains(attr) == true }
        }

        let beam = beamAttributeNames.filter { attr in
            orderedFixtureIDs.contains { caps[$0]?.contains(attr) == true }
        }
        let strobe = strobeAttributeNames.filter { attr in
            orderedFixtureIDs.contains { caps[$0]?.contains(attr) == true }
        }

        // Generic: any supported attr not in intensity/position/color/beam/strobe families.
        let known = coreAttributes
            .union(beamAttributeNames)
            .union(strobeAttributeNames)
            .union(primaryColorAttributes)
            .union(knownTechnicalColorExtras)
        var genericSet = Set<String>()
        for id in orderedFixtureIDs {
            for attr in caps[id] ?? [] {
                let base = attr.split(separator: "@").first.map(String.init) ?? attr
                if known.contains(base) || known.contains(attr) { continue }
                if attr.isEmpty { continue }
                genericSet.insert(attr)
            }
        }
        let generic = genericSet.sorted()

        var extended: [String: ProgrammerAttributeState] = [:]
        for attr in beam + strobe + generic {
            extended[attr] = resolveAttribute(attr, ordered: orderedFixtureIDs, caps: caps, values: values)
        }

        return ProgrammerAttributePresentation(
            orderedFixtureIDs: orderedFixtureIDs,
            intensity: intensity,
            pan: pan,
            tilt: tilt,
            colorR: colorR,
            colorG: colorG,
            colorB: colorB,
            colorW: colorW,
            technicalColorAttributes: tech,
            beamAttributes: beam,
            strobeAttributes: strobe,
            genericAttributes: generic,
            extendedStates: extended
        )
    }

    public static func capableFixtureIDs(
        attribute: String,
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [UUID] {
        // Always use **effective** capabilities (virtual intensity included).
        let caps = capabilityMap(orderedFixtureIDs: orderedFixtureIDs, project: project)
        return orderedFixtureIDs.filter { caps[$0]?.contains(attribute) == true }
    }

    public static func capableFixtureIDs(
        attribute: String,
        orderedFixtureIDs: [UUID],
        caps: [UUID: Set<String>]
    ) -> [UUID] {
        orderedFixtureIDs.filter { caps[$0]?.contains(attribute) == true }
    }

    public static func firstCapableID(
        attribute: String,
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> UUID? {
        capableFixtureIDs(attribute: attribute, orderedFixtureIDs: orderedFixtureIDs, project: project).first
    }

    public static func resolveAttribute(
        _ attribute: String,
        ordered: [UUID],
        caps: [UUID: Set<String>],
        values: [UUID: [String: Double]]
    ) -> ProgrammerAttributeState {
        if attribute == "intensity" || attribute == "dimmer" || attribute == "dim" {
            // Prefer resolveIntensity when physical map available; fallback without virtual defaults.
            return resolveIntensity(
                ordered: ordered,
                physicalCaps: caps,
                effectiveCaps: caps,
                values: values
            )
        }
        return resolveAttributeGeneric(attribute, ordered: ordered, caps: caps, values: values)
    }

    private static func resolveAttributeGeneric(
        _ attribute: String,
        ordered: [UUID],
        caps: [UUID: Set<String>],
        values: [UUID: [String: Double]]
    ) -> ProgrammerAttributeState {
        let capable = ordered.filter { caps[$0]?.contains(attribute) == true }
        guard !capable.isEmpty else {
            return .unsupported
        }
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
        // Mixed if values disagree OR some capable fixtures are untouched while others have values.
        if found.count < capable.count {
            return ProgrammerAttributeState(support: support, value: .mixed)
        }
        let first = found[0]
        let allSame = found.allSatisfy { abs($0 - first) < 1e-9 }
        if allSame {
            return ProgrammerAttributeState(support: support, value: .common(first))
        }
        return ProgrammerAttributeState(support: support, value: .mixed)
    }

    // MARK: - Effective intensity (physical dimmer vs virtual emitter scale)

    public enum EffectiveIntensityMode: Equatable, Sendable {
        case physical
        case virtualEmitterScale
        case unsupported
    }

    public static func hasPhysicalDimmer(_ caps: Set<String>) -> Bool {
        caps.contains("intensity") || caps.contains("dimmer") || caps.contains("dim")
            || caps.contains(where: { GlobalShowControl.isDimmerAttribute($0) && !$0.hasPrefix("color") })
    }

    public static func hasLightProducingEmitters(_ caps: Set<String>) -> Bool {
        caps.contains(where: { ColorEmitterKind.isPhysicalEmitter($0) })
    }

    public static func supportsRGBAuthoring(_ caps: Set<String>) -> Bool {
        // Meaningful H/S/V/WB resolution requires RGB emitters.
        caps.contains("colorR") && caps.contains("colorG") && caps.contains("colorB")
    }

    public static func effectiveIntensityMode(physicalCaps: Set<String>) -> EffectiveIntensityMode {
        if hasPhysicalDimmer(physicalCaps) { return .physical }
        if hasLightProducingEmitters(physicalCaps) { return .virtualEmitterScale }
        return .unsupported
    }

    /// Raw fixture channel/capability attributes (no virtual intensity injection).
    public static func physicalCapabilityMap(
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [UUID: Set<String>] {
        var byID: [UUID: PatchedFixture] = [:]
        byID.reserveCapacity(project.fixtures.count)
        for f in project.fixtures {
            byID[f.id] = f
        }

        var map: [UUID: Set<String>] = [:]
        var defCache: [UUID: Set<String>] = [:]
        for id in orderedFixtureIDs {
            guard let fixture = byID[id] else {
                map[id] = []
                continue
            }
            if let cached = defCache[fixture.definitionId] {
                map[id] = cached
                continue
            }
            let attrs: Set<String>
            if let def = project.definition(id: fixture.definitionId) {
                attrs = Set(CompiledShow.compileAttributeWrites(definition: def).map(\.attribute))
                    .union(def.channels.map(\.attribute))
            } else {
                attrs = []
            }
            defCache[fixture.definitionId] = attrs
            map[id] = attrs
        }
        return map
    }

    /// Inject virtual intensity into a physical capability set when appropriate.
    public static func withEffectiveIntensity(_ physical: Set<String>) -> Set<String> {
        var set = physical
        if effectiveIntensityMode(physicalCaps: physical) == .virtualEmitterScale {
            set.insert("intensity")
        }
        return set
    }

    public static func effectiveCapabilityMap(
        fromPhysical physical: [UUID: Set<String>]
    ) -> [UUID: Set<String>] {
        var map: [UUID: Set<String>] = [:]
        map.reserveCapacity(physical.count)
        for (id, caps) in physical {
            map[id] = withEffectiveIntensity(caps)
        }
        return map
    }

    /// **Effective** capability map used by Programmer, Fan, Align, Color Engine, etc.
    /// Includes virtual `intensity` for light-producing fixtures without a physical dimmer.
    public static func capabilityMap(
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [UUID: Set<String>] {
        effectiveCapabilityMap(
            fromPhysical: physicalCapabilityMap(orderedFixtureIDs: orderedFixtureIDs, project: project)
        )
    }

    /// Intensity presentation using effective values (virtual default = 1.0 when unset).
    public static func resolveIntensity(
        ordered: [UUID],
        physicalCaps: [UUID: Set<String>],
        effectiveCaps: [UUID: Set<String>],
        values: [UUID: [String: Double]]
    ) -> ProgrammerAttributeState {
        let capable = ordered.filter { effectiveCaps[$0]?.contains("intensity") == true }
        guard !capable.isEmpty else { return .unsupported }
        let support: AttributeSupportState = capable.count == ordered.count ? .all : .partial

        var effective: [Double] = []
        effective.reserveCapacity(capable.count)
        var anyOwned = false
        var anyVirtualDefault = false
        var anyPhysicalUntouched = false

        for id in capable {
            let physical = physicalCaps[id] ?? []
            let mode = effectiveIntensityMode(physicalCaps: physical)
            if let v = values[id]?["intensity"] ?? values[id]?["dimmer"] ?? values[id]?["dim"] {
                effective.append(v)
                anyOwned = true
            } else if mode == .virtualEmitterScale {
                // Untouched virtual intensity → effective 100% (neutral multiplier).
                effective.append(1.0)
                anyVirtualDefault = true
            } else {
                // Physical dimmer untouched — keep existing semantics (no fabricated 1.0).
                anyPhysicalUntouched = true
            }
        }

        if effective.isEmpty {
            return ProgrammerAttributeState(support: support, value: .untouched)
        }

        // Partial ownership: some physical fixtures untouched while others have values.
        if anyPhysicalUntouched && anyOwned {
            return ProgrammerAttributeState(support: support, value: .mixed)
        }
        if anyPhysicalUntouched && !anyOwned && !anyVirtualDefault {
            return ProgrammerAttributeState(support: support, value: .untouched)
        }
        if anyPhysicalUntouched && anyVirtualDefault && !anyOwned {
            // Physical untouched (no value) + virtual default 1.0 → mixed presentation
            // unless we only have virtual fixtures (already handled as all effective).
            return ProgrammerAttributeState(support: support, value: .mixed)
        }

        // All capable contributed an effective value.
        if effective.count < capable.count {
            return ProgrammerAttributeState(support: support, value: .mixed)
        }
        let first = effective[0]
        let allSame = effective.allSatisfy { abs($0 - first) < 1e-9 }
        if allSame {
            // Virtual-only defaults at 1.0 appear as common 1.0 (display 100%) without ownership.
            return ProgrammerAttributeState(support: support, value: .common(first))
        }
        return ProgrammerAttributeState(support: support, value: .mixed)
    }
}

// MARK: - Family visual (no fake .common(0))

public enum ProgrammerColorFamilyVisual: Equatable, Sendable {
    case unavailable
    case untouched
    case owned
    case mixed

    public static func resolve(from presentation: ProgrammerAttributePresentation) -> ProgrammerColorFamilyVisual {
        let parts = [presentation.colorR, presentation.colorG, presentation.colorB, presentation.colorW]
            .filter(\.isSupported)
        guard !parts.isEmpty else { return .unavailable }
        if parts.contains(where: \.isMixed) { return .mixed }
        if parts.allSatisfy(\.isUntouched) { return .untouched }
        return .owned
    }
}
