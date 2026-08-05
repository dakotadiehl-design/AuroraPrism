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

    public init(
        orderedFixtureIDs: [UUID] = [],
        intensity: ProgrammerAttributeState = .unsupported,
        pan: ProgrammerAttributeState = .unsupported,
        tilt: ProgrammerAttributeState = .unsupported,
        colorR: ProgrammerAttributeState = .unsupported,
        colorG: ProgrammerAttributeState = .unsupported,
        colorB: ProgrammerAttributeState = .unsupported,
        colorW: ProgrammerAttributeState = .unsupported,
        technicalColorAttributes: [String] = []
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
    }

    public static let empty = ProgrammerAttributePresentation()

    public var hasIntensity: Bool { intensity.isSupported }
    public var hasPosition: Bool { pan.isSupported || tilt.isSupported }

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
}

public enum ProgrammerAttributePresentationResolver {
    public static let primaryColorAttributes = ["colorR", "colorG", "colorB", "colorW"]
    public static let knownTechnicalColorExtras = ["colorA", "colorUV", "cyan", "magenta", "yellow"]

    public static func resolve(
        orderedFixtureIDs: [UUID],
        project: ShowProject,
        programmer: ProgrammerState
    ) -> ProgrammerAttributePresentation {
        guard !orderedFixtureIDs.isEmpty else { return .empty }

        let caps = capabilityMap(orderedFixtureIDs: orderedFixtureIDs, project: project)
        let values = programmer.values

        let intensity = resolveAttribute("intensity", ordered: orderedFixtureIDs, caps: caps, values: values)
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

        return ProgrammerAttributePresentation(
            orderedFixtureIDs: orderedFixtureIDs,
            intensity: intensity,
            pan: pan,
            tilt: tilt,
            colorR: colorR,
            colorG: colorG,
            colorB: colorB,
            colorW: colorW,
            technicalColorAttributes: tech
        )
    }

    public static func capableFixtureIDs(
        attribute: String,
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [UUID] {
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

    public static func capabilityMap(
        orderedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [UUID: Set<String>] {
        // Build fixture lookup once (avoid repeated linear scans).
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
                attrs = Set(def.channels.map(\.attribute))
            } else {
                attrs = []
            }
            defCache[fixture.definitionId] = attrs
            map[id] = attrs
        }
        return map
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
