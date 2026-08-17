import Foundation

/// Immutable project validation result (P1-11).
public struct ProjectValidationSnapshot: Equatable, Sendable {
    public var issues: [ResolutionIssue]
    public var generatedAt: Date

    public init(issues: [ResolutionIssue], generatedAt: Date = Date()) {
        self.issues = issues
        self.generatedAt = generatedAt
    }

    public var isClean: Bool { issues.isEmpty }
}

/// Comprehensive project integrity checks, run after load/mutation — not on the engine frame path.
public enum ProjectValidator {
    public static func validate(_ project: ShowProject) -> ProjectValidationSnapshot {
        var issues: [ResolutionIssue] = []
        let fixtureIDs = Set(project.fixtures.map(\.id))
        let universeIDs = Set(project.universes.map(\.id))
        let definitionIDs = Set(project.fixtureDefinitions.map(\.id))
        let groupIDs = Set(project.groups.map(\.id))
        let paletteIDs = Set(project.palettes.map(\.id))
        let cueListIDs = Set(project.cueLists.map(\.id))
        var cueIDs = Set<UUID>()
        for list in project.cueLists {
            cueIDs.formUnion(list.cues.map(\.id))
        }

        // Duplicate IDs for every first-class entity (PRE-UI-1)
        issues.append(contentsOf: duplicateIDIssues(project.fixtures.map(\.id), label: "fixture"))
        issues.append(contentsOf: duplicateIDIssues(project.universes.map(\.id), label: "universe"))
        issues.append(contentsOf: duplicateIDIssues(project.groups.map(\.id), label: "group"))
        issues.append(contentsOf: duplicateIDIssues(project.palettes.map(\.id), label: "palette"))
        issues.append(contentsOf: duplicateIDIssues(project.fixtureDefinitions.map(\.id), label: "fixture-definition"))
        issues.append(contentsOf: duplicateIDIssues(project.presets.map(\.id), label: "preset"))
        issues.append(contentsOf: duplicateIDIssues(project.cueLists.map(\.id), label: "cue-list"))
        issues.append(contentsOf: duplicateIDIssues(project.songs.map(\.id), label: "song"))
        issues.append(contentsOf: duplicateIDIssues(project.midiMappings.map(\.id), label: "midi-mapping"))
        issues.append(contentsOf: duplicateIDIssues(project.effects.map(\.id), label: "effect"))

        // Media relative paths are dictionary keys on save/materialize — must be unique.
        var seenMediaPaths = Set<String>()
        for asset in project.mediaAssets {
            let key = asset.relativePath
            if !seenMediaPaths.insert(key).inserted {
                issues.append(stableIssue(
                    code: "duplicate-media-relative-path",
                    entity: asset.id,
                    message: "Duplicate media relative path \(key)"
                ))
            }
        }

        // Cue IDs unique across all lists
        var allCueIDs: [UUID] = []
        for list in project.cueLists {
            allCueIDs.append(contentsOf: list.cues.map(\.id))
        }
        issues.append(contentsOf: duplicateIDIssues(allCueIDs, label: "cue"))

        // Song entry IDs
        var songEntryIDs: [UUID] = []
        for song in project.songs {
            songEntryIDs.append(contentsOf: song.entries.map(\.id))
        }
        issues.append(contentsOf: duplicateIDIssues(songEntryIDs, label: "song-entry"))

        // Unique universe numbers (output/buffer key)
        var seenNumbers = Set<UInt16>()
        for universe in project.universes {
            if !seenNumbers.insert(universe.number).inserted {
                issues.append(stableIssue(
                    code: "duplicate-universe-number",
                    entity: universe.id,
                    message: "Duplicate universe number \(universe.number)"
                ))
            }
            if universe.channelCount == 0 {
                issues.append(stableIssue(
                    code: "invalid-channel-count",
                    entity: universe.id,
                    message: "Universe \(universe.number) channelCount must be > 0"
                ))
            } else if universe.channelCount > 512 {
                issues.append(stableIssue(
                    code: "channel-count-high",
                    entity: universe.id,
                    message: "Universe \(universe.number) channelCount \(universe.channelCount) exceeds typical DMX 512"
                ))
            }
        }

        // Effect order uniqueness (tie is undefined if duplicated)
        var seenEffectOrders = Set<Int>()
        for effect in project.effects {
            if !seenEffectOrders.insert(effect.order).inserted {
                issues.append(stableIssue(
                    code: "duplicate-effect-order",
                    entity: effect.id,
                    message: "Duplicate effect order \(effect.order) on \(effect.name)"
                ))
            }
        }

        // Fixture definitions: channel offsets unique and in range; wheels
        for def in project.fixtureDefinitions {
            issues.append(contentsOf: validateDefinition(def))
        }

        // Fixtures
        for fixture in project.fixtures {
            if !definitionIDs.contains(fixture.definitionId) {
                issues.append(stableIssue(
                    code: "missing-definition",
                    entity: fixture.id,
                    message: "Fixture \(fixture.name) missing definition \(fixture.definitionId.uuidString)"
                ))
            }
            if fixture.isPatched, !universeIDs.contains(fixture.universeId) {
                issues.append(stableIssue(
                    code: "missing-universe",
                    entity: fixture.id,
                    message: "Fixture \(fixture.name) missing universe \(fixture.universeId.uuidString)"
                ))
            }
            if fixture.isPatched,
               let def = project.definition(id: fixture.definitionId),
               let universe = project.universe(id: fixture.universeId) {
                let end = fixture.endAddress(channelCount: def.channelCount)
                if end > universe.channelCount {
                    issues.append(stableIssue(
                        code: "footprint-overflow",
                        entity: fixture.id,
                        message: "Fixture \(fixture.name) footprint exceeds universe \(universe.number)"
                    ))
                }
            }
        }

        // Patch overlaps
        issues.append(contentsOf: patchOverlapIssues(project))

        // Groups (authoritative Group.fixtureIds)
        for group in project.groups {
            for fid in group.fixtureIds where !fixtureIDs.contains(fid) {
                issues.append(stableIssue(
                    code: "missing-group-member",
                    entity: group.id,
                    message: "Group \(group.name) references missing fixture \(fid.uuidString)"
                ))
            }
        }
        // Divergent fixture.groupIds vs groups
        for fixture in project.fixtures {
            for gid in fixture.groupIds {
                if !groupIDs.contains(gid) {
                    issues.append(stableIssue(
                        code: "stale-fixture-group",
                        entity: fixture.id,
                        message: "Fixture \(fixture.name) lists unknown group \(gid.uuidString)"
                    ))
                } else if let group = project.groups.first(where: { $0.id == gid }),
                          !group.fixtureIds.contains(fixture.id) {
                    issues.append(stableIssue(
                        code: "group-membership-divergence",
                        entity: fixture.id,
                        message: "Fixture \(fixture.name) groupIds diverge from Group.fixtureIds"
                    ))
                }
            }
        }

        // Cues
        for list in project.cueLists {
            for cue in list.cues {
                for fx in cue.levels.fixtures {
                    if !fixtureIDs.contains(fx.fixtureId) {
                        issues.append(stableIssue(
                            code: "missing-cue-fixture",
                            entity: cue.id,
                            message: "Cue \(cue.name) references missing fixture",
                            cueID: cue.id
                        ))
                    }
                    for (attr, pid) in fx.paletteRefs where !paletteIDs.contains(pid) {
                        issues.append(stableIssue(
                            code: "missing-palette-ref",
                            entity: pid,
                            message: "Missing palette \(pid.uuidString) for \(attr)",
                            cueID: cue.id,
                            paletteID: pid,
                            attribute: attr
                        ))
                    }
                }
            }
        }

        // Presets
        for preset in project.presets {
            for fx in preset.levels.fixtures {
                if !fixtureIDs.contains(fx.fixtureId) {
                    issues.append(stableIssue(
                        code: "missing-preset-fixture",
                        entity: preset.id,
                        message: "Preset \(preset.name) references missing fixture"
                    ))
                }
                for (attr, pid) in fx.paletteRefs where !paletteIDs.contains(pid) {
                    issues.append(stableIssue(
                        code: "missing-preset-palette",
                        entity: pid,
                        message: "Preset \(preset.name) missing palette \(pid.uuidString)",
                        paletteID: pid,
                        attribute: attr
                    ))
                }
            }
        }

        // Songs
        for song in project.songs {
            for entry in song.entries {
                switch entry.target {
                case .cueList(let listID):
                    if !cueListIDs.contains(listID) {
                        issues.append(stableIssue(
                            code: "missing-song-list",
                            entity: song.id,
                            message: "Song \(song.title) entry missing cue list"
                        ))
                    }
                case .cue(let listID, let cueID):
                    if !cueListIDs.contains(listID) || !cueIDs.contains(cueID) {
                        issues.append(stableIssue(
                            code: "missing-song-cue",
                            entity: song.id,
                            message: "Song \(song.title) entry missing cue target"
                        ))
                    }
                }
            }
        }

        // Effects
        for effect in project.effects {
            for fid in effect.fixtureIDs where !fixtureIDs.contains(fid) {
                issues.append(stableIssue(
                    code: "missing-effect-fixture",
                    entity: effect.id,
                    message: "Effect \(effect.name) references missing fixture"
                ))
            }
        }

        // MIDI actions with fireCue parameter
        for mapping in project.midiMappings where mapping.action == "fireCue" {
            if let param = mapping.actionParameter, let id = UUID(uuidString: param), !cueIDs.contains(id) {
                issues.append(stableIssue(
                    code: "missing-midi-cue",
                    entity: mapping.id,
                    message: "MIDI mapping \(mapping.name) targets missing cue"
                ))
            }
        }

        return ProjectValidationSnapshot(issues: issues)
    }

    private static func validateDefinition(_ def: FixtureDefinition) -> [ResolutionIssue] {
        var issues: [ResolutionIssue] = []
        var seenOffsets = Set<UInt16>()
        var coarseCount: [String: Int] = [:]
        var fineCount: [String: Int] = [:]

        for ch in def.channels {
            if ch.offset < 1 || ch.offset > def.channelCount {
                issues.append(stableIssue(
                    code: "channel-offset-oob",
                    entity: def.id,
                    message: "Definition \(def.model) channel \(ch.name) offset \(ch.offset) outside 1…\(def.channelCount)"
                ))
            }
            if !seenOffsets.insert(ch.offset).inserted {
                issues.append(stableIssue(
                    code: "duplicate-channel-offset",
                    entity: def.id,
                    message: "Definition \(def.model) duplicate channel offset \(ch.offset)"
                ))
            }
            switch ch.resolution {
            case .coarse:
                coarseCount[ch.attribute, default: 0] += 1
            case .fine:
                fineCount[ch.attribute, default: 0] += 1
            case .eightBit:
                break
            }
        }

        for (attr, count) in coarseCount where count > 1 {
            issues.append(stableIssue(
                code: "duplicate-coarse-attribute",
                entity: def.id,
                message: "Definition \(def.model) has \(count) coarse channels for \(attr)",
                attribute: attr
            ))
        }
        for (attr, count) in fineCount where count > 1 {
            issues.append(stableIssue(
                code: "duplicate-fine-attribute",
                entity: def.id,
                message: "Definition \(def.model) has \(count) fine channels for \(attr)",
                attribute: attr
            ))
        }

        for wheel in def.wheels {
            var seenIdx = Set<UInt16>()
            for slot in wheel.slots {
                if !seenIdx.insert(slot.index).inserted {
                    issues.append(stableIssue(
                        code: "duplicate-wheel-index",
                        entity: def.id,
                        message: "Definition \(def.model) wheel \(wheel.name) duplicate index \(slot.index)"
                    ))
                }
            }
        }

        return issues
    }

    private static func duplicateIDIssues(_ ids: [UUID], label: String) -> [ResolutionIssue] {
        var seen = Set<UUID>()
        var issues: [ResolutionIssue] = []
        for id in ids {
            if !seen.insert(id).inserted {
                issues.append(stableIssue(
                    code: "duplicate-\(label)",
                    entity: id,
                    message: "Duplicate \(label) id \(id.uuidString)"
                ))
            }
        }
        return issues
    }

    private static func patchOverlapIssues(_ project: ShowProject) -> [ResolutionIssue] {
        var issues: [ResolutionIssue] = []
        var byUniverse: [UUID: [(UUID, ClosedRange<UInt16>)]] = [:]
        for fixture in project.fixtures {
            guard let def = project.definition(id: fixture.definitionId) else { continue }
            let end = fixture.endAddress(channelCount: def.channelCount)
            let range = fixture.address...end
            byUniverse[fixture.universeId, default: []].append((fixture.id, range))
        }
        for (_, ranges) in byUniverse {
            for i in 0..<ranges.count {
                for j in (i + 1)..<ranges.count {
                    if ranges[i].1.overlaps(ranges[j].1) {
                        issues.append(stableIssue(
                            code: "patch-overlap",
                            entity: ranges[i].0,
                            message: "Patch overlap between fixtures \(ranges[i].0.uuidString) and \(ranges[j].0.uuidString)"
                        ))
                    }
                }
            }
        }
        return issues
    }

    /// Deterministic issue identity from code + entity (not random per frame).
    private static func stableIssue(
        code: String,
        entity: UUID,
        message: String,
        cueID: UUID? = nil,
        paletteID: UUID? = nil,
        attribute: String? = nil
    ) -> ResolutionIssue {
        let material = "\(code)|\(entity.uuidString)|\(cueID?.uuidString ?? "")|\(paletteID?.uuidString ?? "")|\(attribute ?? "")"
        let id = uuidFromStableString(material)
        return ResolutionIssue(
            id: id,
            message: message,
            cueID: cueID,
            paletteID: paletteID,
            attribute: attribute
        )
    }

    private static func uuidFromStableString(_ string: String) -> UUID {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((hash >> (UInt64(i) * 8)) & 0xFF)
        }
        // Cosmetic: was `var hash2` never mutated (review warning).
        let hash2 = hash &* 0x9E3779B97F4A7C15
        for i in 0..<8 {
            bytes[8 + i] = UInt8((hash2 >> (UInt64(i) * 8)) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public extension ShowProject {
    /// Full project validation (P1-11). Prefer caching via engine load/update rather than per-frame.
    func validateReferences() -> [ResolutionIssue] {
        ProjectValidator.validate(self).issues
    }
}
