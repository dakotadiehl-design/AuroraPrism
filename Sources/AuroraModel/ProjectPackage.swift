import AuroraDiagnostics
import Foundation

/// Errors thrown while reading or writing a Prism document package.
public enum ProjectPackageError: Error, Equatable, Sendable, LocalizedError {
    case notADirectory(URL)
    case missingFile(String)
    case unsupportedSchemaVersion(found: Int, supportedMaximum: Int)
    case encodingFailed(String)
    case decodingFailed(String)
    case writeFailed(String)

    public var errorDescription: String? { userMessage }
}

extension ProjectPackageError: PrismDiagnosableError {
    public var prismErrorCode: String {
        switch self {
        case .notADirectory: return "project.open.not_a_package"
        case .missingFile: return "project.open.missing_file"
        case .unsupportedSchemaVersion: return "project.open.unsupported_schema"
        case .encodingFailed: return "project.save.encode_failed"
        case .decodingFailed: return "project.open.decode_failed"
        case .writeFailed: return "project.save.write_failed"
        }
    }

    public var userTitle: String {
        switch self {
        case .encodingFailed, .writeFailed:
            return "Prism Couldn't Save the Show"
        default:
            return "Prism Couldn't Open the Show"
        }
    }

    public var userMessage: String {
        switch self {
        case .notADirectory:
            return "The selected item isn’t a Prism show package."
        case .missingFile:
            return "This show package is missing a required file."
        case .unsupportedSchemaVersion:
            return "This show was saved with a newer version of Prism."
        case .encodingFailed, .writeFailed:
            return "Prism couldn’t save the show."
        case .decodingFailed:
            return "Prism couldn’t read this show because part of the file is damaged."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .encodingFailed, .writeFailed:
            return "Try saving to another location, or contact support with the reference ID."
        case .unsupportedSchemaVersion:
            return "Open this show in a newer version of Prism."
        default:
            return "Choose another file, or contact support with the reference ID."
        }
    }

    public var technicalDetails: String {
        switch self {
        case .notADirectory(let url):
            return "notADirectory lastPathComponent=\(url.lastPathComponent)"
        case .missingFile(let name):
            return "missingFile \(name)"
        case .unsupportedSchemaVersion(let found, let supportedMaximum):
            return "unsupportedSchemaVersion found=\(found) max=\(supportedMaximum)"
        case .encodingFailed(let detail):
            return "encodingFailed \(detail)"
        case .decodingFailed(let detail):
            return "decodingFailed \(detail)"
        case .writeFailed(let detail):
            return "writeFailed \(detail)"
        }
    }

    public var prismCategory: PrismLogCategory { .projectDocument }
    public var prismSeverity: PrismLogLevel { .error }
}

/// On-disk Prism package (directory bundle) load/save for `ShowProject`.
///
/// Layout (schema v1):
/// ```
/// Show.prism/
///   project.json
///   universes.json
///   fixtures.json
///   definitions.json
///   groups.json
///   palettes.json
///   presets.json
///   songs.json
///   media-assets.json
///   midi-mappings.json
///   effects.json      (optional on load for older packages; always written)
///   cues/
///     <cueListId>.json
///   media/          (optional; asset binaries)
///   layouts/        (optional; reserved)
/// ```
public enum ProjectPackage {
    /// Preferred external extension for newly saved Prism projects.
    public static let packageExtension = "prism"
    /// Legacy Aurora extension retained for opening existing projects.
    public static let legacyPackageExtension = "aurora"

    public static func isSupportedPackageExtension(_ pathExtension: String) -> Bool {
        let normalized = pathExtension.lowercased()
        return normalized == packageExtension || normalized == legacyPackageExtension
    }

    public static func isLegacyPackageURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == legacyPackageExtension
    }

    public static func preferredPackageURL(for url: URL) -> URL {
        guard isLegacyPackageURL(url) else { return url }
        return url.deletingPathExtension().appendingPathExtension(packageExtension)
    }
    /// v2: stage layout + fixture model extensions (generic params, multi-cell).
    /// v3: MIDI behaviors, drum profiles, feedback profiles.
    /// v4: AME document + song sections / musical settings.
    /// v5: Cue Blocks, Cue Block Groups, and optional `cueBlockRefs` on cues.
    public static let currentSchemaVersion = 5

    private static let projectFileName = "project.json"
    private static let universesFileName = "universes.json"
    private static let fixturesFileName = "fixtures.json"
    private static let definitionsFileName = "definitions.json"
    private static let physicalFixturesFileName = "physical-fixtures.json"
    private static let groupsFileName = "groups.json"
    private static let palettesFileName = "palettes.json"
    private static let presetsFileName = "presets.json"
    private static let cueBlockGroupsFileName = "cue-block-groups.json"
    private static let cueBlocksFileName = "cue-blocks.json"
    private static let songsFileName = "songs.json"
    private static let mediaAssetsFileName = "media-assets.json"
    private static let midiMappingsFileName = "midi-mappings.json"
    private static let midiRulesFileName = "midi-rules.json"
    private static let midiBehaviorsFileName = "midi-behaviors.json"
    private static let drumProfilesFileName = "drum-profiles.json"
    private static let midiFeedbackFileName = "midi-feedback.json"
    private static let effectsFileName = "effects.json"
    private static let stageLayoutFileName = "stage-layout.json"
    private static let ameFileName = "ame.json"
    private static let cuesDirectoryName = "cues"

    // MARK: - JSON coding

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Save

    /// Maximum JSON file size accepted on load (P2-10 defense-in-depth).
    public static let maxJSONFileBytes = 32 * 1024 * 1024

    /// Writes `project` as a directory package at `url` (e.g. `…/Show.aurora`).
    ///
    /// **Atomic:** stages a complete package under the system temporary directory,
    /// validates it, then moves/replaces the destination. Staging is **not** done as a
    /// sibling of the destination (e.g. `.Show.aurora.tmp-…` next to the show) because
    /// the App Sandbox often denies creating sibling files even when the user selected
    /// the final package URL via the save panel.
    ///
    /// **Media/layouts:** copies `media/` and `layouts/` from `preservingAssetsFrom`
    /// when provided (true Save As from an open package); otherwise from any existing
    /// package already at `url` (ordinary Save).
    /// Saves and returns the canonical `modifiedAt` stamped into the package (P2-21).
    @discardableResult
    public static func save(
        _ project: ShowProject,
        to url: URL,
        preservingAssetsFrom assetSource: URL? = nil
    ) throws -> Date {
        let fm = FileManager.default
        let writtenAt = Date()

        // Always-writable staging area (sandbox-safe).
        let stageRoot = fm.temporaryDirectory
            .appendingPathComponent("AuroraSave-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stageRoot, withIntermediateDirectories: true)
        let signpost = PrismSignposts.begin(PrismSignposts.projectSave)
        // Keep the same last path component so package layout mirrors the destination name.
        let tmpURL = stageRoot.appendingPathComponent(url.lastPathComponent, isDirectory: true)

        defer {
            try? fm.removeItem(at: stageRoot)
            PrismSignposts.end(PrismSignposts.projectSave, id: signpost)
        }

        do {
            let binariesFrom = assetSource ?? url
            var stamped = project
            stamped.metadata.modifiedAt = writtenAt
            try writePackageContents(stamped, to: tmpURL, preservingBinariesFrom: binariesFrom)
            _ = try loadPackage(from: tmpURL, emitOperationalEvent: false)

            if fm.fileExists(atPath: url.path) {
                // Replace existing package atomically without sibling .bak in the user folder
                // (sibling backups also hit sandbox parent-directory restrictions).
                do {
                    _ = try fm.replaceItemAt(
                        url,
                        withItemAt: tmpURL,
                        backupItemName: nil,
                        options: [.usingNewMetadataOnly]
                    )
                } catch {
                    throw ProjectPackageError.writeFailed("replace failed: \(error.localizedDescription)")
                }
            } else {
                // First save: move staged package into the user-selected path.
                // Parent directory access comes from the save-panel security scope.
                do {
                    try fm.moveItem(at: tmpURL, to: url)
                } catch {
                    throw ProjectPackageError.writeFailed("create failed: \(error.localizedDescription)")
                }
            }
            PrismLog.notice(
                .projectDocument,
                "project.document.saved",
                "Prism saved the show.",
                metadata: ["schemaVersion": .int(ProjectPackage.currentSchemaVersion, privacy: .public)]
            )
            return writtenAt
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError.writeFailed(error.localizedDescription)
        }
    }

    /// Recover orphan `.tmp-` / `.bak-` packages after crash during save (P2-8 / PRE-UI-7).
    /// Returns recovered package URL if a backup was restored into a missing destination.
    /// Chooses the newest backup by **file modification date**, not UUID lexical order.
    @discardableResult
    public static func recoverOrphanedPackages(around url: URL) throws -> URL? {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        let contents = try fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: keys,
            options: []
        )
        let bak = contents.filter { $0.lastPathComponent.hasPrefix(".\(base).bak-") }
        let tmp = contents.filter { $0.lastPathComponent.hasPrefix(".\(base).tmp-") }

        // Prefer restoring chronologically newest valid backup if destination missing.
        if !fm.fileExists(atPath: url.path) {
            let sorted = bak.sorted { a, b in
                Self.packageTimestamp(a) > Self.packageTimestamp(b)
            }
            for candidate in sorted {
                do {
                    _ = try load(from: candidate)
                    try fm.moveItem(at: candidate, to: url)
                    for t in tmp { try? fm.removeItem(at: t) }
                    for b in bak where b != candidate { try? fm.removeItem(at: b) }
                    return url
                } catch {
                    // Try next-newest valid backup.
                    continue
                }
            }
        }
        // Destination exists: only clean orphans after destination validates.
        if fm.fileExists(atPath: url.path) {
            do {
                _ = try load(from: url)
                for t in tmp { try? fm.removeItem(at: t) }
                for b in bak { try? fm.removeItem(at: b) }
            } catch {
                // Leave backups if destination is corrupt.
            }
        }
        return nil
    }

    /// Best-effort chronological ranking for orphan package directories.
    private static func packageTimestamp(_ url: URL) -> TimeInterval {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        if let mod = values?.contentModificationDate {
            return mod.timeIntervalSince1970
        }
        if let created = values?.creationDate {
            return created.timeIntervalSince1970
        }
        return 0
    }

    private static func writePackageContents(
        _ project: ShowProject,
        to destination: URL,
        preservingBinariesFrom existingPackage: URL?
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination.appendingPathComponent(cuesDirectoryName, isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: destination.appendingPathComponent("media", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: destination.appendingPathComponent("layouts", isDirectory: true), withIntermediateDirectories: true)

        if let existing = existingPackage, fm.fileExists(atPath: existing.path) {
            try copyDirectoryContents(
                from: existing.appendingPathComponent("media", isDirectory: true),
                to: destination.appendingPathComponent("media", isDirectory: true)
            )
            try copyDirectoryContents(
                from: existing.appendingPathComponent("layouts", isDirectory: true),
                to: destination.appendingPathComponent("layouts", isDirectory: true)
            )
        }

        var projectToWrite = project
        projectToWrite.schemaVersion = currentSchemaVersion
        // C4.5: embed Stage imported images into package media/stage and rewrite absolute mediaRefs.
        try StageMediaSupport.materializeStageMedia(into: destination, project: &projectToWrite)
        // modifiedAt is stamped by `save` before calling this (P2-21).

        let encoder = makeEncoder()

        let root = ProjectRootFile(
            schemaVersion: projectToWrite.schemaVersion,
            metadata: projectToWrite.metadata,
            preferences: projectToWrite.preferences,
            workspaceLayoutId: projectToWrite.workspaceLayoutId,
            cueListIds: projectToWrite.cueLists.map(\.id)
        )

        try writeJSON(root, to: destination.appendingPathComponent(projectFileName), encoder: encoder)
        try writeJSON(projectToWrite.universes, to: destination.appendingPathComponent(universesFileName), encoder: encoder)
        try writeJSON(projectToWrite.fixtures, to: destination.appendingPathComponent(fixturesFileName), encoder: encoder)
        try writeJSON(projectToWrite.fixtureDefinitions, to: destination.appendingPathComponent(definitionsFileName), encoder: encoder)
        try writeJSON(projectToWrite.physicalFixtureDefinitions ?? [], to: destination.appendingPathComponent(physicalFixturesFileName), encoder: encoder)
        try writeJSON(projectToWrite.groups, to: destination.appendingPathComponent(groupsFileName), encoder: encoder)
        try writeJSON(projectToWrite.palettes, to: destination.appendingPathComponent(palettesFileName), encoder: encoder)
        try writeJSON(projectToWrite.presets, to: destination.appendingPathComponent(presetsFileName), encoder: encoder)
        try writeJSON(projectToWrite.cueBlockGroups, to: destination.appendingPathComponent(cueBlockGroupsFileName), encoder: encoder)
        try writeJSON(projectToWrite.cueBlocks, to: destination.appendingPathComponent(cueBlocksFileName), encoder: encoder)
        try writeJSON(projectToWrite.songs, to: destination.appendingPathComponent(songsFileName), encoder: encoder)
        try writeJSON(projectToWrite.mediaAssets, to: destination.appendingPathComponent(mediaAssetsFileName), encoder: encoder)
        try writeJSON(projectToWrite.midiMappings, to: destination.appendingPathComponent(midiMappingsFileName), encoder: encoder)
        try writeJSON(projectToWrite.midiRules, to: destination.appendingPathComponent(midiRulesFileName), encoder: encoder)
        try writeJSON(projectToWrite.midiBehaviors, to: destination.appendingPathComponent(midiBehaviorsFileName), encoder: encoder)
        try writeJSON(projectToWrite.drumProfiles, to: destination.appendingPathComponent(drumProfilesFileName), encoder: encoder)
        try writeJSON(projectToWrite.midiFeedbackProfiles, to: destination.appendingPathComponent(midiFeedbackFileName), encoder: encoder)
        try writeJSON(projectToWrite.effects, to: destination.appendingPathComponent(effectsFileName), encoder: encoder)
        try writeJSON(projectToWrite.stageLayout, to: destination.appendingPathComponent(stageLayoutFileName), encoder: encoder)
        try writeJSON(projectToWrite.ame, to: destination.appendingPathComponent(ameFileName), encoder: encoder)

        let cuesDir = destination.appendingPathComponent(cuesDirectoryName, isDirectory: true)
        for list in projectToWrite.cueLists {
            let fileURL = cuesDir.appendingPathComponent("\(list.id.uuidString).json")
            try writeJSON(list, to: fileURL, encoder: encoder)
        }
    }

    private static func copyDirectoryContents(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for item in items {
            let target = dest.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: item, to: target)
        }
    }

    // MARK: - Load

    /// Loads a `ShowProject` from an `.aurora` package directory.
    public static func load(from url: URL) throws -> ShowProject {
        try loadPackage(from: url, emitOperationalEvent: true)
    }

    /// Shared decoder used by public opens and silent staged-save validation.
    private static func loadPackage(from url: URL, emitOperationalEvent: Bool) throws -> ShowProject {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectPackageError.notADirectory(url)
        }
        let signpost = PrismSignposts.begin(PrismSignposts.projectOpen)
        defer { PrismSignposts.end(PrismSignposts.projectOpen, id: signpost) }

        let decoder = makeDecoder()

        let root: ProjectRootFile = try readJSON(
            from: url.appendingPathComponent(projectFileName),
            as: ProjectRootFile.self,
            decoder: decoder,
            missingName: projectFileName
        )

        guard root.schemaVersion > 0, root.schemaVersion <= currentSchemaVersion else {
            throw ProjectPackageError.unsupportedSchemaVersion(
                found: root.schemaVersion,
                supportedMaximum: currentSchemaVersion
            )
        }

        // Schema v1: known collection files are required. Empty arrays are valid;
        // a missing file is package damage and must not silently become [].
        // (media/ and layouts/ binary dirs remain optional.)
        let universes: [Universe] = try readJSONArray(
            url.appendingPathComponent(universesFileName), decoder: decoder, name: universesFileName, required: true
        )
        let fixtures: [PatchedFixture] = try readJSONArray(
            url.appendingPathComponent(fixturesFileName), decoder: decoder, name: fixturesFileName, required: true
        )
        let definitions: [FixtureDefinition] = try readJSONArray(
            url.appendingPathComponent(definitionsFileName), decoder: decoder, name: definitionsFileName, required: true
        )
        let physicalFixtures: [FixturePhysicalDefinition] = try readJSONArray(
            url.appendingPathComponent(physicalFixturesFileName), decoder: decoder, name: physicalFixturesFileName, required: false
        )
        let groups: [Group] = try readJSONArray(
            url.appendingPathComponent(groupsFileName), decoder: decoder, name: groupsFileName, required: true
        )
        let palettes: [Palette] = try readJSONArray(
            url.appendingPathComponent(palettesFileName), decoder: decoder, name: palettesFileName, required: true
        )
        let presets: [Preset] = try readJSONArray(
            url.appendingPathComponent(presetsFileName), decoder: decoder, name: presetsFileName, required: true
        )
        // v5+: cue-blocks.json required. Older packages default to [].
        let requireCueBlocks = root.schemaVersion >= 5
        let cueBlockGroups: [CueBlockGroup] = try readJSONArray(
            url.appendingPathComponent(cueBlockGroupsFileName), decoder: decoder, name: cueBlockGroupsFileName, required: requireCueBlocks
        )
        let cueBlocks: [CueBlock] = try readJSONArray(
            url.appendingPathComponent(cueBlocksFileName), decoder: decoder, name: cueBlocksFileName, required: requireCueBlocks
        )
        let songs: [Song] = try readJSONArray(
            url.appendingPathComponent(songsFileName), decoder: decoder, name: songsFileName, required: true
        )
        let mediaAssets: [MediaAssetRef] = try readJSONArray(
            url.appendingPathComponent(mediaAssetsFileName), decoder: decoder, name: mediaAssetsFileName, required: true
        )
        let midiMappings: [MIDIMapping] = try readJSONArray(
            url.appendingPathComponent(midiMappingsFileName), decoder: decoder, name: midiMappingsFileName, required: true
        )
        // Schema-aware requiredness (Post-C6 audit): optional only for older packages.
        // v2+: stage-layout.json required. v3+: MIDI behavior/rule/profile files required.
        // v4+: ame.json required. effects.json required for schema >= 3 (always written since v3).
        let requireStage = root.schemaVersion >= 2
        let requireMIDIExt = root.schemaVersion >= 3
        let requireEffects = root.schemaVersion >= 3
        let requireAME = root.schemaVersion >= 4

        let midiRules: [MIDIRule] = try readJSONArray(
            url.appendingPathComponent(midiRulesFileName), decoder: decoder, name: midiRulesFileName, required: requireMIDIExt
        )
        let midiBehaviors: [MIDIBehaviorDefinition] = try readJSONArray(
            url.appendingPathComponent(midiBehaviorsFileName), decoder: decoder, name: midiBehaviorsFileName, required: requireMIDIExt
        )
        let drumProfiles: [DrumDeviceProfile] = try readJSONArray(
            url.appendingPathComponent(drumProfilesFileName), decoder: decoder, name: drumProfilesFileName, required: requireMIDIExt
        )
        let midiFeedbackProfiles: [MIDIFeedbackProfile] = try readJSONArray(
            url.appendingPathComponent(midiFeedbackFileName), decoder: decoder, name: midiFeedbackFileName, required: requireMIDIExt
        )
        let effects: [EffectDefinition] = try readJSONArray(
            url.appendingPathComponent(effectsFileName), decoder: decoder, name: effectsFileName, required: requireEffects
        )
        let stageLayout: StageLayout
        let stageURL = url.appendingPathComponent(stageLayoutFileName)
        if FileManager.default.fileExists(atPath: stageURL.path) {
            stageLayout = try readJSON(from: stageURL, as: StageLayout.self, decoder: decoder, missingName: stageLayoutFileName)
        } else if requireStage {
            throw ProjectPackageError.missingFile(stageLayoutFileName)
        } else {
            stageLayout = .empty
        }
        let ame: AMEProjectDocument
        let ameURL = url.appendingPathComponent(ameFileName)
        if FileManager.default.fileExists(atPath: ameURL.path) {
            ame = try readJSON(from: ameURL, as: AMEProjectDocument.self, decoder: decoder, missingName: ameFileName)
        } else if requireAME {
            throw ProjectPackageError.missingFile(ameFileName)
        } else {
            ame = .empty
        }

        let cuesDir = url.appendingPathComponent(cuesDirectoryName, isDirectory: true)
        var cueLists: [CueList] = []
        cueLists.reserveCapacity(root.cueListIds.count)

        for listId in root.cueListIds {
            let fileURL = cuesDir.appendingPathComponent("\(listId.uuidString).json")
            let list: CueList = try readJSON(
                from: fileURL,
                as: CueList.self,
                decoder: decoder,
                missingName: "\(cuesDirectoryName)/\(listId.uuidString).json"
            )
            guard list.id == listId else {
                throw ProjectPackageError.decodingFailed(
                    "Cue list file \(listId.uuidString).json has mismatched id \(list.id.uuidString)"
                )
            }
            cueLists.append(list)
        }

        let loaded = ShowProject(
            schemaVersion: root.schemaVersion,
            metadata: root.metadata,
            preferences: root.preferences,
            fixtureDefinitions: definitions,
            physicalFixtureDefinitions: physicalFixtures,
            universes: universes,
            fixtures: fixtures,
            groups: groups,
            palettes: palettes,
            presets: presets,
            cueBlockGroups: cueBlockGroups,
            cueBlocks: cueBlocks,
            cueLists: cueLists,
            songs: songs,
            mediaAssets: mediaAssets,
            midiMappings: midiMappings,
            midiRules: midiRules,
            midiBehaviors: midiBehaviors,
            drumProfiles: drumProfiles,
            midiFeedbackProfiles: midiFeedbackProfiles,
            effects: effects,
            workspaceLayoutId: root.workspaceLayoutId,
            stageLayout: stageLayout,
            ame: ame
        )
        let migrated = try SchemaMigration.migrate(loaded)
        if emitOperationalEvent {
            PrismLog.notice(
                .projectDocument,
                "project.document.opened",
                "Prism opened the show.",
                metadata: ["schemaVersion": .int(migrated.schemaVersion, privacy: .public)]
            )
        }
        return migrated
    }

    // MARK: - Helpers

    private struct ProjectRootFile: Codable, Equatable, Sendable {
        var schemaVersion: Int
        var metadata: ProjectMetadata
        var preferences: ProjectPreferences
        var workspaceLayoutId: UUID?
        var cueListIds: [UUID]
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder) throws {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError.writeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func readJSON<T: Decodable>(
        from url: URL,
        as type: T.Type,
        decoder: JSONDecoder,
        missingName: String
    ) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectPackageError.missingFile(missingName)
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > maxJSONFileBytes {
                throw ProjectPackageError.decodingFailed("\(missingName): file exceeds size limit")
            }
            let data = try Data(contentsOf: url)
            if data.count > maxJSONFileBytes {
                throw ProjectPackageError.decodingFailed("\(missingName): file exceeds size limit")
            }
            return try decoder.decode(T.self, from: data)
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError.decodingFailed("\(missingName): \(error.localizedDescription)")
        }
    }

    private static func readJSONArray<T: Decodable>(
        _ url: URL,
        decoder: JSONDecoder,
        name: String,
        required: Bool
    ) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if required {
                throw ProjectPackageError.missingFile(name)
            }
            // Optional future collections may default to empty.
            return []
        }
        return try readJSON(from: url, as: [T].self, decoder: decoder, missingName: name)
    }

    /// Schema v1 JSON files that must be present in a package (excluding cue list files).
    public static var schemaV1RequiredCollectionFiles: [String] {
        [
            universesFileName,
            fixturesFileName,
            definitionsFileName,
            groupsFileName,
            palettesFileName,
            presetsFileName,
            songsFileName,
            mediaAssetsFileName,
            midiMappingsFileName,
        ]
    }

    /// Files required for a package written at `currentSchemaVersion` (Post-C6 integrity).
    public static var currentSchemaRequiredCollectionFiles: [String] {
        schemaV1RequiredCollectionFiles + [
            midiRulesFileName,
            midiBehaviorsFileName,
            drumProfilesFileName,
            midiFeedbackFileName,
            effectsFileName,
            stageLayoutFileName,
            ameFileName,
            cueBlockGroupsFileName,
            cueBlocksFileName,
        ]
    }
}
