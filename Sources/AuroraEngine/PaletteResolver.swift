import AuroraModel
import Foundation

/// Expands palette references in cue/preset levels to literal attributes.
public enum PaletteResolver {
    public struct Result: Equatable, Sendable {
        public var levels: CueLevelData
        public var issues: [ResolutionIssue]
    }

    /// Refs expand first; literals override the same attribute key.
    public static func resolve(levels: CueLevelData, project: ShowProject, cueID: UUID? = nil) -> Result {
        var issues: [ResolutionIssue] = []
        var paletteByID: [UUID: Palette] = [:]
        for p in project.palettes { paletteByID[p.id] = p }

        var fixtures: [FixtureCueLevels] = []
        for fx in levels.fixtures {
            var attrs: [String: Double] = [:]
            // Deterministic ref order (sorted keys) — P1-10.
            for (key, paletteID) in fx.paletteRefs.sorted(by: { $0.key < $1.key }) {
                guard let palette = paletteByID[paletteID] else {
                    issues.append(ResolutionIssue(
                        message: "Missing palette \(paletteID)",
                        cueID: cueID,
                        paletteID: paletteID,
                        attribute: key
                    ))
                    continue
                }
                // Family/type compatibility (P1-10).
                if let slotType = PaletteType(rawValue: key), slotType != palette.type, palette.type != .general {
                    issues.append(ResolutionIssue(
                        message: "Palette type \(palette.type.rawValue) incompatible with slot \(key)",
                        cueID: cueID,
                        paletteID: paletteID,
                        attribute: key
                    ))
                    continue
                }
                // If key matches a single attribute in palette, use it; else merge all palette values.
                if let v = palette.values[key] {
                    attrs[key] = v
                } else {
                    for (pk, pv) in palette.values.sorted(by: { $0.key < $1.key }) {
                        attrs[pk] = pv
                    }
                }
            }
            for (k, v) in fx.attributes {
                attrs[k] = v // literals win
            }
            fixtures.append(FixtureCueLevels(fixtureId: fx.fixtureId, attributes: attrs, paletteRefs: [:]))
        }
        return Result(levels: CueLevelData(fixtures: fixtures), issues: issues)
    }
}
