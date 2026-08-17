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
        // C.E. 1.1: authoring H/S/V/WB + physical RGB + dedicated emitters.
        // Keep list local to AuroraModel (no Engine dependency).
        case .color:
            return [
                "colorHue", "colorSat", "colorVal", "colorWB",
                "colorR", "colorG", "colorB",
                "colorW", "colorA", "colorUV",
                "colorWarmWhite", "colorCoolWhite", "colorLime", "colorCyan",
            ]
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
        case "colorA": return "Amber"
        case "colorUV": return "UV"
        case "colorWarmWhite": return "Warm White"
        case "colorCoolWhite": return "Cool White"
        case "colorLime": return "Lime"
        case "colorCyan": return "Cyan"
        case "colorHue": return "Hue"
        case "colorSat": return "Saturation"
        case "colorVal": return "Brightness"
        case "colorWB": return "White Balance"
        case "intensity": return "Intensity"
        case "pan": return "Pan"
        case "tilt": return "Tilt"
        default: return key
        }
    }

    private static let softAuthoringKeys: Set<String> = [
        "colorHue", "colorSat", "colorVal", "colorWB",
    ]

    /// Fixture supports RGB Color Engine authoring (H/S/V/WB → RGB).
    public static func supportsRGBAuthoring(_ supported: Set<String>) -> Bool {
        supported.contains("colorR") && supported.contains("colorG") && supported.contains("colorB")
    }

    /// Intersect palette values with fixture-supported attributes (CR-01).
    /// Soft authoring H/S/V/WB apply only when the fixture supports RGB authoring (Pass 2 final).
    public static func filterValues(
        _ values: [String: Double],
        supported: Set<String>
    ) -> [String: Double] {
        let rgbOK = supportsRGBAuthoring(supported)
        return values.filter { key, _ in
            if softAuthoringKeys.contains(key) {
                return rgbOK
            }
            return supported.contains(key)
        }
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
            if softAuthoringKeys.contains(key) {
                // Soft authoring: record only when present; absent everywhere → skip (not mixed).
                var samples: [Double] = []
                for id in selectedFixtureIDs {
                    if let v = programmerValues[id]?[key] {
                        samples.append(v)
                    }
                }
                guard !samples.isEmpty else { continue }
                anyCapable = true
                let first = samples[0]
                if samples.allSatisfy({ abs($0 - first) < 1e-9 }) {
                    common[key] = first
                } else {
                    mixed.append(key)
                }
                continue
            }

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
