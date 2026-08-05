import Foundation

/// Result of recording a palette from multi-fixture programmer data (P1-14).
public struct PaletteRecordResult: Equatable, Sendable {
    public var values: [String: Double]
    public var commonAttributes: [String]
    public var mixedAttributes: [String]
    public var isMixed: Bool { !mixedAttributes.isEmpty }

    public init(
        values: [String: Double],
        commonAttributes: [String],
        mixedAttributes: [String]
    ) {
        self.values = values
        self.commonAttributes = commonAttributes
        self.mixedAttributes = mixedAttributes
    }
}

public enum PaletteRecord {
    /// Build palette values from selected fixtures' programmer data.
    ///
    /// - Common attributes (same value on all selected fixtures with that attr) are recorded.
    /// - Mixed attributes are listed but not written (deterministic; no “first wins”).
    public static func fromProgrammer(
        programmerValues: [UUID: [String: Double]],
        selectedFixtureIDs: [UUID],
        attributeKeys: [String]? = nil
    ) -> PaletteRecordResult {
        let keys = attributeKeys ?? ["colorR", "colorG", "colorB", "colorW", "intensity", "pan", "tilt"]
        guard !selectedFixtureIDs.isEmpty else {
            return PaletteRecordResult(values: [:], commonAttributes: [], mixedAttributes: [])
        }

        var common: [String: Double] = [:]
        var mixed: [String] = []
        var present: [String] = []

        for key in keys {
            var samples: [Double] = []
            for id in selectedFixtureIDs {
                if let v = programmerValues[id]?[key] {
                    samples.append(v)
                }
            }
            guard !samples.isEmpty else { continue }
            present.append(key)
            let first = samples[0]
            if samples.allSatisfy({ abs($0 - first) < 1e-9 }) {
                common[key] = first
            } else {
                mixed.append(key)
            }
        }

        return PaletteRecordResult(
            values: common,
            commonAttributes: present.filter { common[$0] != nil },
            mixedAttributes: mixed
        )
    }

    /// Apply preset/palette levels to programmer; returns skipped fixture IDs (missing from selection or empty).
    public static func applyIssues(
        levels: CueLevelData,
        selection: Set<UUID>
    ) -> (applied: Int, skippedMissingSelection: Int, empty: Bool) {
        if levels.fixtures.isEmpty {
            return (0, 0, true)
        }
        var applied = 0
        var skipped = 0
        for fx in levels.fixtures {
            if selection.contains(fx.fixtureId) || selection.isEmpty {
                if !fx.attributes.isEmpty || !fx.paletteRefs.isEmpty {
                    applied += 1
                }
            } else {
                skipped += 1
            }
        }
        return (applied, skipped, false)
    }
}
