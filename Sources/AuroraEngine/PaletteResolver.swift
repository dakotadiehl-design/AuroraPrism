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
            for (key, paletteID) in fx.paletteRefs {
                guard let palette = paletteByID[paletteID] else {
                    issues.append(ResolutionIssue(
                        message: "Missing palette \(paletteID)",
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
                    for (pk, pv) in palette.values {
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
