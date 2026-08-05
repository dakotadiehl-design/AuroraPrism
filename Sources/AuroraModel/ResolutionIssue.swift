import Foundation

/// Non-fatal project/reference problems (missing palette, etc.).
public struct ResolutionIssue: Equatable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var message: String
    public var cueID: UUID?
    public var paletteID: UUID?
    public var attribute: String?

    public init(
        id: UUID = UUID(),
        message: String,
        cueID: UUID? = nil,
        paletteID: UUID? = nil,
        attribute: String? = nil
    ) {
        self.id = id
        self.message = message
        self.cueID = cueID
        self.paletteID = paletteID
        self.attribute = attribute
    }
}

public extension ShowProject {
    /// Reports broken palette refs and other structural reference issues.
    func validateReferences() -> [ResolutionIssue] {
        var issues: [ResolutionIssue] = []
        let paletteIDs = Set(palettes.map(\.id))
        for list in cueLists {
            for cue in list.cues {
                for fx in cue.levels.fixtures {
                    for (attr, pid) in fx.paletteRefs {
                        if !paletteIDs.contains(pid) {
                            issues.append(ResolutionIssue(
                                message: "Missing palette \(pid.uuidString) for \(attr)",
                                cueID: cue.id,
                                paletteID: pid,
                                attribute: attr
                            ))
                        }
                    }
                }
            }
        }
        return issues
    }

    func isPaletteReferenced(_ paletteID: UUID) -> Bool {
        for list in cueLists {
            for cue in list.cues {
                for fx in cue.levels.fixtures {
                    if fx.paletteRefs.values.contains(paletteID) { return true }
                }
            }
        }
        for preset in presets {
            for fx in preset.levels.fixtures {
                if fx.paletteRefs.values.contains(paletteID) { return true }
            }
        }
        return false
    }
}
