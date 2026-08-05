import Foundation

/// Errors thrown while reading or writing an `.aurora` document package.
public enum ProjectPackageError: Error, Equatable, Sendable {
    case notADirectory(URL)
    case missingFile(String)
    case unsupportedSchemaVersion(found: Int, supportedMaximum: Int)
    case encodingFailed(String)
    case decodingFailed(String)
    case writeFailed(String)
}

/// On-disk `.aurora` package (directory bundle) load/save for `ShowProject`.
///
/// Layout (schema v1):
/// ```
/// Show.aurora/
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
    public static let packageExtension = "aurora"
    public static let currentSchemaVersion = 1

    private static let projectFileName = "project.json"
    private static let universesFileName = "universes.json"
    private static let fixturesFileName = "fixtures.json"
    private static let definitionsFileName = "definitions.json"
    private static let groupsFileName = "groups.json"
    private static let palettesFileName = "palettes.json"
    private static let presetsFileName = "presets.json"
    private static let songsFileName = "songs.json"
    private static let mediaAssetsFileName = "media-assets.json"
    private static let midiMappingsFileName = "midi-mappings.json"
    private static let effectsFileName = "effects.json"
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
    /// **Atomic:** writes a temporary package, validates it, then replaces the
    /// destination so a failed write cannot erase a valid existing show.
    /// **Media/layouts:** copies `media/` and `layouts/` from `preservingAssetsFrom`
    /// when provided (true Save As from an open package); otherwise from any existing
    /// package already at `url` (ordinary Save).
    public static func save(
        _ project: ShowProject,
        to url: URL,
        preservingAssetsFrom assetSource: URL? = nil
    ) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        let tmpName = ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
        let tmpURL = parent.appendingPathComponent(tmpName, isDirectory: true)

        if fm.fileExists(atPath: tmpURL.path) {
            try? fm.removeItem(at: tmpURL)
        }

        do {
            let binariesFrom = assetSource ?? url
            try writePackageContents(project, to: tmpURL, preservingBinariesFrom: binariesFrom)
            _ = try load(from: tmpURL)

            if fm.fileExists(atPath: url.path) {
                let backupName = ".\(url.lastPathComponent).bak-\(UUID().uuidString)"
                let backupURL = parent.appendingPathComponent(backupName, isDirectory: true)
                try fm.moveItem(at: url, to: backupURL)
                do {
                    try fm.moveItem(at: tmpURL, to: url)
                    try? fm.removeItem(at: backupURL)
                } catch {
                    try? fm.removeItem(at: url)
                    try? fm.moveItem(at: backupURL, to: url)
                    try? fm.removeItem(at: tmpURL)
                    throw ProjectPackageError.writeFailed("replace failed: \(error.localizedDescription)")
                }
            } else {
                try fm.moveItem(at: tmpURL, to: url)
            }
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw error
        }
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
        projectToWrite.metadata.modifiedAt = Date()

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
        try writeJSON(projectToWrite.groups, to: destination.appendingPathComponent(groupsFileName), encoder: encoder)
        try writeJSON(projectToWrite.palettes, to: destination.appendingPathComponent(palettesFileName), encoder: encoder)
        try writeJSON(projectToWrite.presets, to: destination.appendingPathComponent(presetsFileName), encoder: encoder)
        try writeJSON(projectToWrite.songs, to: destination.appendingPathComponent(songsFileName), encoder: encoder)
        try writeJSON(projectToWrite.mediaAssets, to: destination.appendingPathComponent(mediaAssetsFileName), encoder: encoder)
        try writeJSON(projectToWrite.midiMappings, to: destination.appendingPathComponent(midiMappingsFileName), encoder: encoder)
        try writeJSON(projectToWrite.effects, to: destination.appendingPathComponent(effectsFileName), encoder: encoder)

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
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectPackageError.notADirectory(url)
        }

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
        let groups: [Group] = try readJSONArray(
            url.appendingPathComponent(groupsFileName), decoder: decoder, name: groupsFileName, required: true
        )
        let palettes: [Palette] = try readJSONArray(
            url.appendingPathComponent(palettesFileName), decoder: decoder, name: palettesFileName, required: true
        )
        let presets: [Preset] = try readJSONArray(
            url.appendingPathComponent(presetsFileName), decoder: decoder, name: presetsFileName, required: true
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
        // Additive: older packages may omit effects.json.
        let effects: [EffectDefinition] = try readJSONArray(
            url.appendingPathComponent(effectsFileName), decoder: decoder, name: effectsFileName, required: false
        )

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

        return ShowProject(
            schemaVersion: root.schemaVersion,
            metadata: root.metadata,
            preferences: root.preferences,
            fixtureDefinitions: definitions,
            universes: universes,
            fixtures: fixtures,
            groups: groups,
            palettes: palettes,
            presets: presets,
            cueLists: cueLists,
            songs: songs,
            mediaAssets: mediaAssets,
            midiMappings: midiMappings,
            effects: effects,
            workspaceLayoutId: root.workspaceLayoutId
        )
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
}
