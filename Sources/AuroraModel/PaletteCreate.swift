import Foundation

/// Typed palette create request from Programmer (UI-04).
public enum PaletteCreateKind: String, Sendable, Equatable, CaseIterable {
    case color
    case intensity
    case position

    public var paletteType: PaletteType {
        switch self {
        case .color: return .color
        case .intensity: return .intensity
        case .position: return .position
        }
    }

    public var attributeKeys: [String] {
        switch self {
        case .color: return ["colorR", "colorG", "colorB", "colorW"]
        case .intensity: return ["intensity"]
        case .position: return ["pan", "tilt"]
        }
    }

    public var defaultNamePrefix: String {
        switch self {
        case .color: return "Color"
        case .intensity: return "Intensity"
        case .position: return "Position"
        }
    }
}

/// Outcome of creating a palette from multi-fixture Programmer data (UI-04 / CR-03).
public enum PaletteCreateOutcome: Equatable, Sendable {
    case created(Palette, mixedSkipped: [String])
    case refusedEmpty
    case refusedNoProgrammerData
}

/// Capability-aware palette helpers (CR-01 / CR-02 / CR-03).
public enum PaletteCreate {
    public static func displayName(forAttribute key: String) -> String {
        switch key {
        case "colorR": return "Red"
        case "colorG": return "Green"
        case "colorB": return "Blue"
        case "colorW": return "White"
        case "intensity": return "Intensity"
        case "pan": return "Pan"
        case "tilt": return "Tilt"
        default: return key
        }
    }

    /// Intersect palette values with fixture-supported attributes (CR-01).
    public static func filterValues(
        _ values: [String: Double],
        supported: Set<String>
    ) -> [String: Double] {
        values.filter { supported.contains($0.key) }
    }

    /// Fixtures that support at least one key in `values` (CR-02).
    public static func compatibleFixtureIDs(
        selection: Set<UUID>,
        values: [String: Double],
        capabilityMap: [UUID: Set<String>]
    ) -> Set<UUID> {
        let keys = Set(values.keys)
        guard !keys.isEmpty else { return [] }
        return Set(selection.filter { id in
            let caps = capabilityMap[id] ?? []
            return !caps.isDisjoint(with: keys)
        })
    }

    /// Build a palette from Programmer values for the given kind.
    ///
    /// When `capabilityMap` is provided (CR-03):
    /// - Only **capable** fixtures participate in common/mixed comparison.
    /// - Capable + untouched blocks false “common” (mixed/skip).
    /// - Unsupported fixtures are excluded from comparison.
    public static func fromProgrammer(
        kind: PaletteCreateKind,
        programmerValues: [UUID: [String: Double]],
        selectedFixtureIDs: [UUID],
        existingPaletteCount: Int,
        name: String? = nil,
        capabilityMap: [UUID: Set<String>]? = nil
    ) -> PaletteCreateOutcome {
        let scope: [UUID]
        if !selectedFixtureIDs.isEmpty {
            scope = selectedFixtureIDs
        } else {
            scope = Array(programmerValues.keys)
        }
        guard !scope.isEmpty else { return .refusedNoProgrammerData }

        if let caps = capabilityMap {
            return fromProgrammerCapabilityAware(
                kind: kind,
                programmerValues: programmerValues,
                selectedFixtureIDs: scope,
                existingPaletteCount: existingPaletteCount,
                name: name,
                capabilityMap: caps
            )
        }

        let hasAny = scope.contains { id in
            guard let attrs = programmerValues[id] else { return false }
            return kind.attributeKeys.contains { attrs[$0] != nil }
        }
        guard hasAny else { return .refusedNoProgrammerData }

        let record = PaletteRecord.fromProgrammer(
            programmerValues: programmerValues,
            selectedFixtureIDs: scope,
            attributeKeys: kind.attributeKeys
        )
        guard !record.values.isEmpty else { return .refusedEmpty }

        let palette = Palette(
            name: name ?? "\(kind.defaultNamePrefix) \(existingPaletteCount + 1)",
            type: kind.paletteType,
            values: record.values
        )
        return .created(palette, mixedSkipped: record.mixedAttributes)
    }

    private static func fromProgrammerCapabilityAware(
        kind: PaletteCreateKind,
        programmerValues: [UUID: [String: Double]],
        selectedFixtureIDs: [UUID],
        existingPaletteCount: Int,
        name: String?,
        capabilityMap: [UUID: Set<String>]
    ) -> PaletteCreateOutcome {
        var common: [String: Double] = [:]
        var mixed: [String] = []
        var anyCapable = false

        for key in kind.attributeKeys {
            let capable = selectedFixtureIDs.filter { (capabilityMap[$0] ?? []).contains(key) }
            guard !capable.isEmpty else { continue }
            anyCapable = true

            var samples: [Double] = []
            var allOwned = true
            for id in capable {
                if let v = programmerValues[id]?[key] {
                    samples.append(v)
                } else {
                    allOwned = false
                }
            }

            if !allOwned || samples.isEmpty {
                mixed.append(key)
                continue
            }

            let first = samples[0]
            if samples.allSatisfy({ abs($0 - first) < 1e-9 }) {
                common[key] = first
            } else {
                mixed.append(key)
            }
        }

        guard anyCapable else { return .refusedNoProgrammerData }
        guard !common.isEmpty else { return .refusedEmpty }

        let palette = Palette(
            name: name ?? "\(kind.defaultNamePrefix) \(existingPaletteCount + 1)",
            type: kind.paletteType,
            values: common
        )
        return .created(palette, mixedSkipped: mixed)
    }

    public static func statusMessage(for outcome: PaletteCreateOutcome) -> String {
        switch outcome {
        case .created(let palette, let mixed) where mixed.isEmpty:
            return "Created \(palette.name)"
        case .created(let palette, let mixed):
            let labels = mixed.map(displayName(forAttribute:)).joined(separator: ", ")
            return "Created \(palette.name) · Skipped mixed: \(labels)"
        case .refusedEmpty:
            return "Nothing to store — all candidate attributes are mixed, untouched, or empty"
        case .refusedNoProgrammerData:
            return "No capable fixtures / programmer values for this palette type"
        }
    }
}
