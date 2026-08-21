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
        let physicalFixtureIDs = Set((project.physicalFixtureDefinitions ?? []).map(\.id))
        let groupIDs = Set(project.groups.map(\.id))
        let cueBlockGroupIDs = Set(project.cueBlockGroups.map(\.id))
        let paletteIDs = Set(project.palettes.map(\.id))
        let cueListIDs = Set(project.cueLists.map(\.id))
        let effectIDs = Set(project.effects.map(\.id))
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
        issues.append(contentsOf: duplicateIDIssues((project.physicalFixtureDefinitions ?? []).map(\.id), label: "physical-fixture-definition"))
        issues.append(contentsOf: duplicateIDIssues(project.presets.map(\.id), label: "preset"))
        issues.append(contentsOf: duplicateIDIssues(project.cueBlocks.map(\.id), label: "cue-block"))
        issues.append(contentsOf: duplicateIDIssues(project.cueBlockGroups.map(\.id), label: "cue-block-group"))
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
            if effect.templateLinkMode == .linked {
                if let templateID = effect.templateEffectID, effectIDs.contains(templateID) {
                    if templateID == effect.id || effectTemplateCycle(startingAt: effect.id, effects: project.effects) {
                        issues.append(stableIssue(code: "cyclic-effect-template", entity: effect.id, message: "Effect \(effect.name) has a cyclic template link"))
                    }
                } else {
                    issues.append(stableIssue(code: "missing-effect-template", entity: effect.id, message: "Effect \(effect.name) references a missing template"))
                }
            }
            if effect.mask?.kind == .fixtureGroup,
               effect.mask?.fixtureGroupID.map({ !groupIDs.contains($0) }) != false {
                issues.append(stableIssue(code: "missing-effect-mask-group", entity: effect.id, message: "Effect \(effect.name) mask references a missing fixture group"))
            }
            for target in effect.cellTargeting?.selectedTargets ?? [] where !fixtureIDs.contains(target.fixtureID) {
                issues.append(stableIssue(code: "missing-effect-cell-fixture", entity: effect.id, message: "Effect \(effect.name) references a cell on a missing fixture"))
            }
            for target in effect.mask?.selectedTargets ?? [] where !fixtureIDs.contains(target.fixtureID) {
                issues.append(stableIssue(code: "missing-effect-mask-target", entity: effect.id, message: "Effect \(effect.name) mask references a missing target"))
            }
            for paletteID in effect.colorGradient?.stops.compactMap(\.paletteID) ?? [] where !paletteIDs.contains(paletteID) {
                issues.append(stableIssue(code: "missing-effect-gradient-palette", entity: effect.id, message: "Effect \(effect.name) gradient references a missing palette", paletteID: paletteID))
            }
        }

        // Fixture definitions: channel offsets unique and in range; wheels
        for def in project.fixtureDefinitions {
            issues.append(contentsOf: validateDefinition(def))
            if let physicalID = def.physicalFixtureID,
               !physicalFixtureIDs.contains(physicalID),
               def.portablePhysicalDefinition?.id != physicalID {
                issues.append(stableIssue(
                    code: "missing-physical-fixture",
                    entity: def.id,
                    message: "Personality \(def.displayName) references missing physical fixture \(physicalID.uuidString)"
                ))
            }
        }
        for physical in project.physicalFixtureDefinitions ?? [] {
            let emitterIDs = physical.emitters.map(\.id)
            if Set(emitterIDs).count != emitterIDs.count {
                issues.append(stableIssue(code: "duplicate-physical-emitter", entity: physical.id, message: "Physical fixture \(physical.manufacturer) \(physical.model) contains duplicate emitter identities"))
            }
            let known = Set(emitterIDs)
            if physical.componentGroups.flatMap(\.emitterIDs).contains(where: { !known.contains($0) }) {
                issues.append(stableIssue(code: "unknown-component-emitter", entity: physical.id, message: "Physical fixture \(physical.manufacturer) \(physical.model) has a component group referencing an unknown emitter"))
            }
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

        let cueBlockIDs = Set(project.cueBlocks.map(\.id))

        for group in project.cueBlockGroups {
            if let sourceID = group.sourceFixtureGroupID, !groupIDs.contains(sourceID) {
                issues.append(stableIssue(
                    code: "missing-cue-block-group-source",
                    entity: group.id,
                    message: "Cue Block Group \(group.name) source fixture group \(sourceID.uuidString) is missing"
                ))
            }
        }

        // Cue Blocks
        for block in project.cueBlocks {
            if block.levels.fixtures.isEmpty {
                issues.append(stableIssue(
                    code: "empty-cue-block",
                    entity: block.id,
                    message: "Cue Block \(block.name) has no fixture levels"
                ))
            }
            if let gid = block.sourceGroupID, !groupIDs.contains(gid) {
                issues.append(stableIssue(
                    code: "missing-cue-block-source-group",
                    entity: block.id,
                    message: "Cue Block \(block.name) source group \(gid.uuidString) is missing"
                ))
            }
            if let folderID = block.cueBlockGroupID, !cueBlockGroupIDs.contains(folderID) {
                issues.append(stableIssue(
                    code: "missing-cue-block-group",
                    entity: block.id,
                    message: "Cue Block \(block.name) references missing Cue Block Group \(folderID.uuidString)"
                ))
            }
            for fx in block.levels.fixtures {
                if !fixtureIDs.contains(fx.fixtureId) {
                    issues.append(stableIssue(
                        code: "missing-cue-block-fixture",
                        entity: block.id,
                        message: "Cue Block \(block.name) references missing fixture \(fx.fixtureId.uuidString)"
                    ))
                }
                for (attr, pid) in fx.paletteRefs where !paletteIDs.contains(pid) {
                    issues.append(stableIssue(
                        code: "missing-cue-block-palette",
                        entity: pid,
                        message: "Cue Block \(block.name) missing palette \(pid.uuidString)",
                        paletteID: pid,
                        attribute: attr
                    ))
                }
                for (attr, _) in fx.attributes {
                    if block.type != .general,
                       !CueBlockAttributeFamily.isAllowed(attr, for: block.type) {
                        issues.append(stableIssue(
                            code: "cue-block-type-attribute-mismatch",
                            entity: block.id,
                            message: "Cue Block \(block.name) type \(block.type.rawValue) contains attribute \(attr)",
                            attribute: attr
                        ))
                    }
                }
                for (slot, pid) in fx.paletteRefs {
                    if let palette = project.palettes.first(where: { $0.id == pid }),
                       block.type != .general,
                       let slotType = CueBlockType(rawValue: slot),
                       slotType != block.type,
                       palette.type != .general {
                        issues.append(stableIssue(
                            code: "cue-block-type-attribute-mismatch",
                            entity: block.id,
                            message: "Cue Block \(block.name) palette ref slot \(slot) incompatible with block type",
                            paletteID: pid,
                            attribute: slot
                        ))
                    }
                }
            }
        }

        // Cues
        for list in project.cueLists {
            for cue in list.cues {
                var seenBlockIDs = Set<UUID>()
                var seenRefIDs = Set<UUID>()
                for ref in cue.cueBlockRefs {
                    if !seenRefIDs.insert(ref.id).inserted {
                        issues.append(stableIssue(
                            code: "duplicate-cue-block-ref-id",
                            entity: ref.id,
                            message: "Cue \(cue.name) has duplicate Cue Block reference id",
                            cueID: cue.id
                        ))
                    }
                    if !seenBlockIDs.insert(ref.cueBlockID).inserted {
                        issues.append(stableIssue(
                            code: "duplicate-cue-block-ref",
                            entity: ref.cueBlockID,
                            message: "Cue \(cue.name) references Cue Block \(ref.cueBlockID.uuidString) more than once",
                            cueID: cue.id
                        ))
                    }
                    // Structural: missing block is broken even when disabled.
                    if !cueBlockIDs.contains(ref.cueBlockID) {
                        issues.append(stableIssue(
                            code: "missing-cue-block-ref",
                            entity: ref.cueBlockID,
                            message: "Cue \(cue.name) references missing Cue Block \(ref.cueBlockID.uuidString)",
                            cueID: cue.id
                        ))
                    }
                }
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

    private static func effectTemplateCycle(startingAt start: UUID, effects: [EffectDefinition]) -> Bool {
        var byID: [UUID: EffectDefinition] = [:]
        for effect in effects where byID[effect.id] == nil { byID[effect.id] = effect }
        var visited: Set<UUID> = []
        var current: UUID? = start
        while let id = current, let effect = byID[id], effect.templateLinkMode == .linked {
            guard visited.insert(id).inserted else { return true }
            current = effect.templateEffectID
        }
        return false
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
