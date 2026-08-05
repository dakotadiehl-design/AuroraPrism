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
    func isPaletteReferenced(_ paletteID: UUID) -> Bool {
        paletteReferenceCount(paletteID) > 0
    }

    /// Number of cue fixture-slots + preset fixture-slots that reference this palette.
    func paletteReferenceCount(_ paletteID: UUID) -> Int {
        var count = 0
        for list in cueLists {
            for cue in list.cues {
                for fx in cue.levels.fixtures {
                    if fx.paletteRefs.values.contains(paletteID) { count += 1 }
                }
            }
        }
        for preset in presets {
            for fx in preset.levels.fixtures {
                if fx.paletteRefs.values.contains(paletteID) { count += 1 }
            }
        }
        return count
    }

    /// Human-readable sites for delete confirmations (cues only; presets summarized separately).
    func paletteReferenceCueSummaries(_ paletteID: UUID) -> [String] {
        var lines: [String] = []
        for list in cueLists {
            for cue in list.cues {
                let hit = cue.levels.fixtures.contains { $0.paletteRefs.values.contains(paletteID) }
                if hit {
                    let name = cue.name.isEmpty ? "Cue \(cue.number)" : cue.name
                    lines.append("\(list.name) → \(name)")
                }
            }
        }
        let presetHits = presets.filter { preset in
            preset.levels.fixtures.contains { $0.paletteRefs.values.contains(paletteID) }
        }
        for preset in presetHits {
            lines.append("Preset: \(preset.name)")
        }
        return lines
    }
}

public extension Cue {
    /// Records palette *references* for the given fixtures (does not bake literals).
    /// Existing literals on those attributes are left alone (resolver: literals win).
    mutating func recordPaletteRef(palette: Palette, fixtureIDs: Set<UUID>) {
        guard !fixtureIDs.isEmpty else { return }
        var fixtures = levels.fixtures
        for id in fixtureIDs {
            if let idx = fixtures.firstIndex(where: { $0.fixtureId == id }) {
                fixtures[idx].paletteRefs[palette.type.rawValue] = palette.id
            } else {
                fixtures.append(
                    FixtureCueLevels(
                        fixtureId: id,
                        paletteRefs: [palette.type.rawValue: palette.id]
                    )
                )
            }
        }
        levels = CueLevelData(fixtures: fixtures)
    }
}

public extension ShowProject {
    /// Resolves which cue(s) should receive a palette ref from selection + fallbacks.
    /// Prefers selected cue IDs that still exist; else first cue of first list.
    func targetCuesForPaletteRecord(selectedCueIDs: Set<UUID>) -> [(listID: UUID, cue: Cue)] {
        var result: [(listID: UUID, cue: Cue)] = []
        if !selectedCueIDs.isEmpty {
            for list in cueLists {
                for cue in list.cues where selectedCueIDs.contains(cue.id) {
                    result.append((list.id, cue))
                }
            }
        }
        if result.isEmpty, let list = cueLists.first, let cue = list.cues.first {
            result.append((list.id, cue))
        }
        return result
    }
}
