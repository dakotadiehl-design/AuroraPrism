import Foundation

public enum AMEValidationSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct AMEValidationIssue: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var severity: AMEValidationSeverity
    public var code: String
    public var message: String
    public var relatedID: UUID?

    public init(
        id: UUID = UUID(),
        severity: AMEValidationSeverity,
        code: String,
        message: String,
        relatedID: UUID? = nil
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.relatedID = relatedID
    }
}

/// Product BPM range (aligned with MusicalNumeric intent).
public enum AMENumericLimits {
    public static let minBPM: Double = 20
    public static let maxBPM: Double = 400

    public static func isValidBPM(_ bpm: Double) -> Bool {
        bpm.isFinite && bpm >= minBPM && bpm <= maxBPM
    }

    public static func isNonNegativeFinite(_ v: Double) -> Bool {
        v.isFinite && v >= 0
    }

    public static func isMIDIDataByte(_ v: UInt8) -> Bool {
        v <= 127
    }
}

public enum AMEConfigurationValidator {
    public static func validate(project: ShowProject) -> [AMEValidationIssue] {
        validate(document: project.ame, project: project)
    }

    public static func validate(document: AMEProjectDocument, project: ShowProject) -> [AMEValidationIssue] {
        var issues: [AMEValidationIssue] = []

        let sectionIDs = Set(project.songs.flatMap(\.sections).map(\.id))
        let songIDs = Set(project.songs.map(\.id))
        let sectionToSong: [UUID: UUID] = {
            var map: [UUID: UUID] = [:]
            for song in project.songs {
                for section in song.sections {
                    map[section.id] = song.id
                }
            }
            return map
        }()
        let cueIDs = Set(project.cueLists.flatMap(\.cues).map(\.id))
        let presetIDs = Set(project.presets.map(\.id))
        let paletteIDs = Set(project.palettes.map(\.id))
        let behaviorIDs = Set(project.midiBehaviors.map(\.id))
        let effectIDs = Set(project.effects.map(\.id))
        let bindingIDs = Set(document.sourceBindings.map(\.id))
        let triggerIDs = Set(document.triggers.map(\.id))
        let groupIDs = Set(document.triggerGroups.map(\.id))
        let sequenceIDs = Set(document.sequences.map(\.id))
        let sequenceStepCounts: [UUID: Int] = {
            var map: [UUID: Int] = [:]
            for s in document.sequences where map[s.id] == nil {
                map[s.id] = s.steps.count
            }
            return map
        }()
        let mappingIDs = Set(document.mappings.map(\.id))
        let setIDs = Set(document.mappingSets.map(\.id))

        let dupMappingIDs = duplicateIDs(document.mappings.map(\.id))
        issues.append(contentsOf: duplicateIDIssues(document.triggers.map(\.id), code: "duplicate_trigger_id", label: "trigger"))
        issues.append(contentsOf: duplicateIDIssues(document.triggerGroups.map(\.id), code: "duplicate_group_id", label: "group"))
        issues.append(contentsOf: duplicateIDIssues(document.mappings.map(\.id), code: "duplicate_mapping_id", label: "mapping"))
        issues.append(contentsOf: duplicateIDIssues(document.mappingSets.map(\.id), code: "duplicate_mapping_set_id", label: "mapping set"))
        issues.append(contentsOf: duplicateIDIssues(document.sequences.map(\.id), code: "duplicate_sequence_id", label: "sequence"))
        issues.append(contentsOf: duplicateIDIssues(document.sourceBindings.map(\.id), code: "duplicate_binding_id", label: "source binding"))
        issues.append(contentsOf: duplicateIDIssues(project.songs.flatMap(\.sections).map(\.id), code: "duplicate_section_id", label: "section"))

        for group in document.triggerGroups {
            if group.memberTriggerIDs.isEmpty {
                issues.append(.init(severity: .warning, code: "empty_trigger_group", message: "Trigger group “\(group.name)” has no members.", relatedID: group.id))
            }
            for tid in group.memberTriggerIDs where !triggerIDs.contains(tid) {
                issues.append(.init(severity: .error, code: "missing_trigger", message: "Trigger group “\(group.name)” references missing trigger.", relatedID: group.id))
            }
        }

        for trigger in document.triggers {
            if let ch = trigger.channel, ch > 15 {
                issues.append(.init(severity: .error, code: "invalid_channel", message: "Trigger “\(trigger.name)” channel out of range.", relatedID: trigger.id))
            }
            for (label, v) in [
                ("data1Min", trigger.data1Min), ("data1Max", trigger.data1Max),
                ("data2Min", trigger.data2Min), ("data2Max", trigger.data2Max),
            ] {
                if let v, !AMENumericLimits.isMIDIDataByte(v) {
                    issues.append(.init(severity: .error, code: "invalid_midi_data", message: "Trigger “\(trigger.name)” \(label) must be 0…127.", relatedID: trigger.id))
                }
            }
            if let a = trigger.data1Min, let b = trigger.data1Max, a > b {
                issues.append(.init(severity: .error, code: "invalid_data_range", message: "Trigger “\(trigger.name)” data1 min > max.", relatedID: trigger.id))
            }
            if let a = trigger.data2Min, let b = trigger.data2Max, a > b {
                issues.append(.init(severity: .error, code: "invalid_data_range", message: "Trigger “\(trigger.name)” data2 min > max.", relatedID: trigger.id))
            }
            if let bid = trigger.sourceBindingID, !bindingIDs.contains(bid) {
                issues.append(.init(severity: .error, code: "unresolved_source_binding", message: "Trigger “\(trigger.name)” has unresolved source binding.", relatedID: trigger.id))
            }
        }

        var legacyMapClaims: [UUID: [UUID]] = [:]
        var legacyRuleClaims: [UUID: [UUID]] = [:]
        for m in document.mappings {
            if let id = m.claimsLegacyMappingID { legacyMapClaims[id, default: []].append(m.id) }
            if let id = m.claimsLegacyRuleID { legacyRuleClaims[id, default: []].append(m.id) }
        }
        for (legacy, owners) in legacyMapClaims where owners.count > 1 {
            issues.append(.init(severity: .error, code: "duplicate_legacy_mapping_claim", message: "Multiple AME mappings claim legacy mapping \(legacy).", relatedID: owners.first))
        }
        for (legacy, owners) in legacyRuleClaims where owners.count > 1 {
            issues.append(.init(severity: .error, code: "duplicate_legacy_rule_claim", message: "Multiple AME mappings claim legacy rule \(legacy).", relatedID: owners.first))
        }
        let projectLegacyMap = Set(project.midiMappings.map(\.id))
        let projectLegacyRule = Set(project.midiRules.map(\.id))
        for m in document.mappings {
            if let id = m.claimsLegacyMappingID, !projectLegacyMap.contains(id) {
                issues.append(.init(severity: .warning, code: "legacy_mapping_missing", message: "Mapping “\(m.name)” claims missing legacy mapping.", relatedID: m.id))
            }
            if let id = m.claimsLegacyRuleID, !projectLegacyRule.contains(id) {
                issues.append(.init(severity: .warning, code: "legacy_rule_missing", message: "Mapping “\(m.name)” claims missing legacy rule.", relatedID: m.id))
            }
        }

        // Inheritance: skip graph walk when duplicate IDs would trap uniqueKeysWithValues
        if dupMappingIDs.isEmpty {
            issues.append(contentsOf: validateInheritance(
                document.mappings,
                sectionToSong: sectionToSong
            ))
        }

        for mapping in document.mappings {
            let hasT = mapping.triggerID != nil
            let hasG = mapping.triggerGroupID != nil
            if !hasT && !hasG {
                issues.append(.init(severity: .error, code: "missing_when", message: "Mapping “\(mapping.name)” has neither trigger nor group.", relatedID: mapping.id))
            }
            if hasT && hasG {
                issues.append(.init(severity: .error, code: "ambiguous_when", message: "Mapping “\(mapping.name)” has both trigger and group.", relatedID: mapping.id))
            }
            if let tid = mapping.triggerID, !triggerIDs.contains(tid) {
                issues.append(.init(severity: .error, code: "missing_trigger", message: "Mapping “\(mapping.name)” references missing trigger.", relatedID: mapping.id))
            }
            if let gid = mapping.triggerGroupID, !groupIDs.contains(gid) {
                issues.append(.init(severity: .error, code: "missing_trigger_group", message: "Mapping “\(mapping.name)” references missing trigger group.", relatedID: mapping.id))
            }
            if let sid = mapping.sequenceID, !sequenceIDs.contains(sid) {
                issues.append(.init(severity: .error, code: "missing_sequence", message: "Mapping “\(mapping.name)” references missing sequence.", relatedID: mapping.id))
            }
            if case .song(let id) = mapping.scope, !songIDs.contains(id) {
                issues.append(.init(severity: .error, code: "missing_song", message: "Mapping “\(mapping.name)” references deleted song.", relatedID: mapping.id))
            }
            if case .section(let id) = mapping.scope, !sectionIDs.contains(id) {
                issues.append(.init(severity: .error, code: "missing_section", message: "Mapping “\(mapping.name)” references deleted section.", relatedID: mapping.id))
            }
            if mapping.timingRequirement == .externalSyncLocked,
               document.musicalSettings.timingPolicy == .internalOnly {
                issues.append(.init(severity: .warning, code: "sync_required_no_source", message: "Mapping “\(mapping.name)” requires external sync but policy is internal only.", relatedID: mapping.id))
            }
            if let q = mapping.quantizeBoundary, q != .immediate {
                if mapping.actions.contains(where: \.isSafetyCritical) {
                    issues.append(.init(severity: .error, code: "safety_quantized", message: "Mapping “\(mapping.name)” quantizes a safety-critical action.", relatedID: mapping.id))
                }
            }
            if let t = mapping.transform, !t.isStructurallyValid {
                issues.append(.init(severity: .error, code: "invalid_transform", message: "Mapping “\(mapping.name)” has invalid transform.", relatedID: mapping.id))
            }
            if !AMENumericLimits.isNonNegativeFinite(mapping.debounceMilliseconds) {
                issues.append(.init(severity: .error, code: "invalid_debounce", message: "Mapping “\(mapping.name)” debounce must be finite ≥ 0.", relatedID: mapping.id))
            }
            if let burst = mapping.burstSuppressionMilliseconds, !AMENumericLimits.isNonNegativeFinite(burst) {
                issues.append(.init(severity: .error, code: "invalid_burst_suppression", message: "Mapping “\(mapping.name)” burst suppression must be finite ≥ 0.", relatedID: mapping.id))
            }
            issues.append(contentsOf: validateActions(
                mapping.actions,
                context: "Mapping “\(mapping.name)”",
                relatedID: mapping.id,
                cueIDs: cueIDs, presetIDs: presetIDs, paletteIDs: paletteIDs,
                songIDs: songIDs, sectionIDs: sectionIDs, behaviorIDs: behaviorIDs,
                sequenceIDs: sequenceIDs, sequenceStepCounts: sequenceStepCounts, effectIDs: effectIDs,
                disallowSequenceControl: false
            ))
            issues.append(contentsOf: validateActions(
                mapping.releaseActions,
                context: "Mapping “\(mapping.name)” release",
                relatedID: mapping.id,
                cueIDs: cueIDs, presetIDs: presetIDs, paletteIDs: paletteIDs,
                songIDs: songIDs, sectionIDs: sectionIDs, behaviorIDs: behaviorIDs,
                sequenceIDs: sequenceIDs, sequenceStepCounts: sequenceStepCounts, effectIDs: effectIDs,
                disallowSequenceControl: false
            ))
            let heldLike: Set<AMETriggerBehavior> = [.momentary, .whileHeld, .heldGate]
            if heldLike.contains(mapping.behavior), mapping.releaseActions.isEmpty, !mapping.actions.isEmpty {
                issues.append(.init(
                    severity: .warning,
                    code: "missing_release_actions",
                    message: "Mapping “\(mapping.name)” is \(mapping.behavior.rawValue) but has empty releaseActions.",
                    relatedID: mapping.id
                ))
            }
        }

        for set in document.mappingSets {
            for mid in set.mappingIDs where !mappingIDs.contains(mid) {
                issues.append(.init(severity: .error, code: "missing_mapping_in_set", message: "Mapping set “\(set.name)” references missing mapping.", relatedID: set.id))
            }
        }

        for seq in document.sequences {
            if seq.steps.isEmpty {
                issues.append(.init(severity: .warning, code: "empty_sequence", message: "Sequence “\(seq.name)” has zero steps.", relatedID: seq.id))
            }
            if !seq.steps.isEmpty && seq.initialIndex >= seq.steps.count {
                issues.append(.init(severity: .error, code: "initial_index_oob", message: "Sequence “\(seq.name)” initialIndex out of range.", relatedID: seq.id))
            }
            issues.append(contentsOf: duplicateIDIssues(seq.steps.map(\.id), code: "duplicate_step_id", label: "sequence step"))
            if seq.mode == .weightedRandom {
                for step in seq.steps where !(step.weight.isFinite && step.weight > 0) {
                    issues.append(.init(severity: .error, code: "invalid_weights", message: "Sequence “\(seq.name)” has invalid step weight.", relatedID: seq.id))
                }
            }
            if seq.mode == .reverse, seq.initialIndex == 0, seq.steps.count > 1 {
                issues.append(.init(
                    severity: .info,
                    code: "reverse_starts_at_zero",
                    message: "Sequence “\(seq.name)” is reverse with initialIndex 0; editors usually start reverse at last step.",
                    relatedID: seq.id
                ))
            }
            for step in seq.steps {
                issues.append(contentsOf: validateActions(
                    step.actions,
                    context: "Sequence “\(seq.name)” step “\(step.name)”",
                    relatedID: seq.id,
                    cueIDs: cueIDs, presetIDs: presetIDs, paletteIDs: paletteIDs,
                    songIDs: songIDs, sectionIDs: sectionIDs, behaviorIDs: behaviorIDs,
                    sequenceIDs: sequenceIDs, sequenceStepCounts: sequenceStepCounts, effectIDs: effectIDs,
                    // Nested sequence-control inside steps is disallowed (no recursive execution graph).
                    disallowSequenceControl: true
                ))
            }
        }

        for song in project.songs {
            if let bpm = song.defaultTempoBPM, !AMENumericLimits.isValidBPM(bpm) {
                issues.append(.init(severity: .error, code: "invalid_song_bpm", message: "Song “\(song.title)” BPM out of range.", relatedID: song.id))
            }
            // defaultMeter already validated by ShowMusicalMeter init when constructed; re-check structure if present
            if let meter = song.defaultMeter {
                if meter.beatGrouping.reduce(0, +) != meter.numerator {
                    issues.append(.init(severity: .error, code: "invalid_song_meter", message: "Song “\(song.title)” meter grouping invalid.", relatedID: song.id))
                }
            }
            for section in song.sections {
                for setID in section.mappingSetIDs where !setIDs.contains(setID) {
                    issues.append(.init(severity: .error, code: "missing_mapping_set", message: "Section “\(section.name)” references missing mapping set.", relatedID: section.id))
                }
                for mid in section.localMappingIDs where !mappingIDs.contains(mid) {
                    issues.append(.init(severity: .error, code: "missing_local_mapping", message: "Section “\(section.name)” references missing local mapping.", relatedID: section.id))
                }
                for mid in section.localMappingIDs {
                    if let m = document.mappings.first(where: { $0.id == mid }) {
                        if case .section(let sid) = m.scope, sid != section.id {
                            issues.append(.init(severity: .warning, code: "local_mapping_scope_mismatch", message: "Local mapping scope does not match section “\(section.name)”.", relatedID: mid))
                        }
                    }
                }
                for sid in section.associatedSequenceIDs where !sequenceIDs.contains(sid) {
                    issues.append(.init(severity: .error, code: "missing_associated_sequence", message: "Section “\(section.name)” associates missing sequence.", relatedID: section.id))
                }
                issues.append(contentsOf: validateActions(
                    section.onEnterActions,
                    context: "Section “\(section.name)” onEnter",
                    relatedID: section.id,
                    cueIDs: cueIDs, presetIDs: presetIDs, paletteIDs: paletteIDs,
                    songIDs: songIDs, sectionIDs: sectionIDs, behaviorIDs: behaviorIDs,
                    sequenceIDs: sequenceIDs, sequenceStepCounts: sequenceStepCounts, effectIDs: effectIDs,
                    disallowSequenceControl: false
                ))
                issues.append(contentsOf: validateActions(
                    section.onExitActions,
                    context: "Section “\(section.name)” onExit",
                    relatedID: section.id,
                    cueIDs: cueIDs, presetIDs: presetIDs, paletteIDs: paletteIDs,
                    songIDs: songIDs, sectionIDs: sectionIDs, behaviorIDs: behaviorIDs,
                    sequenceIDs: sequenceIDs, sequenceStepCounts: sequenceStepCounts, effectIDs: effectIDs,
                    disallowSequenceControl: false
                ))
            }
        }

        let ms = document.musicalSettings
        if !AMENumericLimits.isValidBPM(ms.defaultTempoBPM) {
            issues.append(.init(severity: .error, code: "invalid_bpm", message: "Musical settings BPM invalid (expected \(AMENumericLimits.minBPM)…\(AMENumericLimits.maxBPM))."))
        }
        if !AMENumericLimits.isNonNegativeFinite(ms.freewheelSeconds) {
            issues.append(.init(severity: .error, code: "invalid_freewheel", message: "Musical settings freewheel duration invalid."))
        }
        if ms.defaultMeter.beatGrouping.reduce(0, +) != ms.defaultMeter.numerator {
            issues.append(.init(severity: .error, code: "invalid_meter", message: "Musical settings meter grouping invalid."))
        }
        if let bid = ms.selectedExternalSourceBindingID, !bindingIDs.contains(bid) {
            issues.append(.init(severity: .error, code: "missing_external_source", message: "Selected external source binding missing."))
        }
        if ms.timingPolicy != .internalOnly && ms.selectedExternalSourceBindingID == nil && document.sourceBindings.isEmpty {
            issues.append(.init(severity: .warning, code: "external_policy_no_source", message: "External timing policy with no source configured."))
        }

        return issues.sorted {
            if $0.code != $1.code { return $0.code < $1.code }
            let a = $0.relatedID?.uuidString ?? ""
            let b = $1.relatedID?.uuidString ?? ""
            if a != b { return a < b }
            return $0.message < $1.message
        }
    }

    // MARK: - Helpers

    private static func duplicateIDs(_ ids: [UUID]) -> Set<UUID> {
        var seen = Set<UUID>()
        var dups = Set<UUID>()
        for id in ids {
            if !seen.insert(id).inserted { dups.insert(id) }
        }
        return dups
    }

    private static func duplicateIDIssues(_ ids: [UUID], code: String, label: String) -> [AMEValidationIssue] {
        duplicateIDs(ids).sorted { $0.uuidString < $1.uuidString }.map {
            AMEValidationIssue(severity: .error, code: code, message: "Duplicate \(label) id.", relatedID: $0)
        }
    }

    /// Defensive first-wins map (never traps on duplicate keys).
    private static func firstWinsMap(_ mappings: [AMEMapping]) -> [UUID: AMEMapping] {
        var map: [UUID: AMEMapping] = [:]
        for m in mappings {
            if map[m.id] == nil { map[m.id] = m }
        }
        return map
    }

    private enum ScopeKind: Equatable {
        case project
        case song(UUID)
        case section(UUID)
    }

    private static func scopeKind(_ scope: AMEMappingScope) -> ScopeKind {
        switch scope {
        case .project: return .project
        case .song(let id): return .song(id)
        case .section(let id): return .section(id)
        }
    }

    /// Child may override/disable parent only if parent is ancestor or same exact scope.
    private static func isLegalParentChild(
        child: AMEMappingScope,
        parent: AMEMappingScope,
        sectionToSong: [UUID: UUID]
    ) -> Bool {
        switch (child, parent) {
        case (.project, .project):
            return true
        case (.song, .project):
            return true
        case (.song(let cs), .song(let ps)):
            return cs == ps
        case (.section, .project):
            return true
        case (.section(let csec), .song(let ps)):
            return sectionToSong[csec] == ps
        case (.section(let csec), .section(let psec)):
            return csec == psec
        // Child project targeting song/section parent — illegal
        case (.project, .song), (.project, .section):
            return false
        case (.song, .section):
            return false
        }
    }

    /// Effective context key for simultaneous activation (project-wide, song, or section).
    private static func effectiveContextKey(_ scope: AMEMappingScope) -> String {
        switch scope {
        case .project: return "project"
        case .song(let id): return "song:\(id.uuidString)"
        case .section(let id): return "section:\(id.uuidString)"
        }
    }

    private static func validateInheritance(
        _ mappings: [AMEMapping],
        sectionToSong: [UUID: UUID]
    ) -> [AMEValidationIssue] {
        var issues: [AMEValidationIssue] = []
        let byID = firstWinsMap(mappings)

        for m in mappings {
            if let p = m.overrideParentID {
                if p == m.id {
                    issues.append(.init(severity: .error, code: "self_override", message: "Mapping “\(m.name)” overrides itself.", relatedID: m.id))
                } else if let parent = byID[p] {
                    if !isLegalParentChild(child: m.scope, parent: parent.scope, sectionToSong: sectionToSong) {
                        issues.append(.init(severity: .error, code: "illegal_override_scope", message: "Mapping “\(m.name)” override parent has illegal scope ancestry.", relatedID: m.id))
                    }
                } else {
                    issues.append(.init(severity: .error, code: "missing_override_parent", message: "Mapping “\(m.name)” override parent missing.", relatedID: m.id))
                }
            }
            if let p = m.disablesParentID {
                if p == m.id {
                    issues.append(.init(severity: .error, code: "self_disable", message: "Mapping “\(m.name)” disables itself.", relatedID: m.id))
                } else if let parent = byID[p] {
                    if !isLegalParentChild(child: m.scope, parent: parent.scope, sectionToSong: sectionToSong) {
                        issues.append(.init(severity: .error, code: "illegal_disable_scope", message: "Mapping “\(m.name)” disable parent has illegal scope ancestry.", relatedID: m.id))
                    }
                } else {
                    issues.append(.init(severity: .error, code: "missing_disable_parent", message: "Mapping “\(m.name)” disable parent missing.", relatedID: m.id))
                }
            }
            if let o = m.overrideParentID, let d = m.disablesParentID, o == d {
                issues.append(.init(severity: .error, code: "override_and_disable_same", message: "Mapping “\(m.name)” both overrides and disables same parent.", relatedID: m.id))
            }
        }

        func walk(_ start: UUID, edge: (AMEMapping) -> UUID?) -> Bool {
            var seen = Set<UUID>()
            var cur: UUID? = start
            while let c = cur {
                if !seen.insert(c).inserted { return true }
                guard let m = byID[c] else { return false }
                cur = edge(m)
            }
            return false
        }
        for m in mappings {
            if walk(m.id, edge: { $0.overrideParentID }) {
                issues.append(.init(severity: .error, code: "override_cycle", message: "Mapping “\(m.name)” participates in override cycle.", relatedID: m.id))
            }
            if walk(m.id, edge: { $0.disablesParentID }) {
                issues.append(.init(severity: .error, code: "disable_cycle", message: "Mapping “\(m.name)” participates in disable cycle.", relatedID: m.id))
            }
        }

        // Ambiguity only within the same effective context (not global across exclusive sections).
        var byParent: [UUID: [AMEMapping]] = [:]
        for m in mappings {
            if let p = m.overrideParentID { byParent[p, default: []].append(m) }
        }
        for (parent, children) in byParent {
            let byContext = Dictionary(grouping: children, by: { effectiveContextKey($0.scope) })
            for (_, list) in byContext {
                let byPri = Dictionary(grouping: list, by: \.priority)
                for (pri, same) in byPri where same.count > 1 {
                    issues.append(.init(
                        severity: .warning,
                        code: "ambiguous_override",
                        message: "Multiple mappings priority \(pri) override parent \(parent) in the same effective scope.",
                        relatedID: parent
                    ))
                }
            }
        }
        return issues
    }

    private static func validateActions(
        _ actions: [AuroraAction],
        context: String,
        relatedID: UUID?,
        cueIDs: Set<UUID>,
        presetIDs: Set<UUID>,
        paletteIDs: Set<UUID>,
        songIDs: Set<UUID>,
        sectionIDs: Set<UUID>,
        behaviorIDs: Set<UUID>,
        sequenceIDs: Set<UUID>,
        sequenceStepCounts: [UUID: Int],
        effectIDs: Set<UUID>,
        disallowSequenceControl: Bool
    ) -> [AMEValidationIssue] {
        var issues: [AMEValidationIssue] = []
        func walk(_ action: AuroraAction) {
            switch action {
            case .fireCue(let id) where !cueIDs.contains(id):
                issues.append(.init(severity: .error, code: "missing_cue", message: "\(context) missing cue.", relatedID: relatedID))
            case .firePreset(let id) where !presetIDs.contains(id):
                issues.append(.init(severity: .error, code: "missing_preset", message: "\(context) missing preset.", relatedID: relatedID))
            case .firePalette(let id) where !paletteIDs.contains(id):
                issues.append(.init(severity: .error, code: "missing_palette", message: "\(context) missing palette.", relatedID: relatedID))
            case .selectSong(let id) where !songIDs.contains(id):
                issues.append(.init(severity: .error, code: "missing_song_ref", message: "\(context) missing song.", relatedID: relatedID))
            case .enterSection(let id) where !sectionIDs.contains(id):
                issues.append(.init(severity: .error, code: "missing_section_ref", message: "\(context) missing section.", relatedID: relatedID))
            case .runBehavior(let id) where !behaviorIDs.contains(id):
                issues.append(.init(severity: .error, code: "missing_behavior", message: "\(context) missing MIDI behavior.", relatedID: relatedID))
            case .advanceSequence(let id), .resetSequence(let id):
                if disallowSequenceControl {
                    issues.append(.init(
                        severity: .error,
                        code: "nested_sequence_control",
                        message: "\(context) must not contain sequence-control actions.",
                        relatedID: relatedID
                    ))
                } else if !sequenceIDs.contains(id) {
                    issues.append(.init(severity: .error, code: "missing_sequence_ref", message: "\(context) missing sequence.", relatedID: relatedID))
                }
            case .fireSequenceStep(let id, let stepIndex):
                if disallowSequenceControl {
                    issues.append(.init(
                        severity: .error,
                        code: "nested_sequence_control",
                        message: "\(context) must not contain sequence-control actions.",
                        relatedID: relatedID
                    ))
                } else if !sequenceIDs.contains(id) {
                    issues.append(.init(severity: .error, code: "missing_sequence_ref", message: "\(context) missing sequence.", relatedID: relatedID))
                } else if let count = sequenceStepCounts[id], (stepIndex < 0 || stepIndex >= count) {
                    issues.append(.init(
                        severity: .error,
                        code: "sequence_step_oob",
                        message: "\(context) fireSequenceStep index \(stepIndex) out of bounds (count=\(count)).",
                        relatedID: relatedID
                    ))
                }
            case .triggerEffect(let id), .setEffectRate(let id, _), .setEffectDepth(let id, _):
                if !effectIDs.contains(id) {
                    issues.append(.init(severity: .error, code: "missing_effect", message: "\(context) missing effect.", relatedID: relatedID))
                }
            case .compound(let nested):
                nested.forEach(walk)
            default:
                break
            }
        }
        actions.forEach(walk)
        return issues
    }
}
