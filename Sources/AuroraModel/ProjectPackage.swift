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

    /// Writes `project` as a directory package at `url` (e.g. `…/Show.aurora`).
    /// Replaces an existing package at the same path.
    public static func save(_ project: ShowProject, to url: URL) throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }

        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent(cuesDirectoryName, isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("media", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("layouts", isDirectory: true), withIntermediateDirectories: true)

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

        try writeJSON(root, to: url.appendingPathComponent(projectFileName), encoder: encoder)
        try writeJSON(projectToWrite.universes, to: url.appendingPathComponent(universesFileName), encoder: encoder)
        try writeJSON(projectToWrite.fixtures, to: url.appendingPathComponent(fixturesFileName), encoder: encoder)
        try writeJSON(projectToWrite.fixtureDefinitions, to: url.appendingPathComponent(definitionsFileName), encoder: encoder)
        try writeJSON(projectToWrite.groups, to: url.appendingPathComponent(groupsFileName), encoder: encoder)
        try writeJSON(projectToWrite.palettes, to: url.appendingPathComponent(palettesFileName), encoder: encoder)
        try writeJSON(projectToWrite.presets, to: url.appendingPathComponent(presetsFileName), encoder: encoder)
        try writeJSON(projectToWrite.songs, to: url.appendingPathComponent(songsFileName), encoder: encoder)
        try writeJSON(projectToWrite.mediaAssets, to: url.appendingPathComponent(mediaAssetsFileName), encoder: encoder)
        try writeJSON(projectToWrite.midiMappings, to: url.appendingPathComponent(midiMappingsFileName), encoder: encoder)

        let cuesDir = url.appendingPathComponent(cuesDirectoryName, isDirectory: true)
        for list in projectToWrite.cueLists {
            let fileURL = cuesDir.appendingPathComponent("\(list.id.uuidString).json")
            try writeJSON(list, to: fileURL, encoder: encoder)
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

        let universes: [Universe] = try readJSONArray(url.appendingPathComponent(universesFileName), decoder: decoder, name: universesFileName)
        let fixtures: [PatchedFixture] = try readJSONArray(url.appendingPathComponent(fixturesFileName), decoder: decoder, name: fixturesFileName)
        let definitions: [FixtureDefinition] = try readJSONArray(url.appendingPathComponent(definitionsFileName), decoder: decoder, name: definitionsFileName)
        let groups: [Group] = try readJSONArray(url.appendingPathComponent(groupsFileName), decoder: decoder, name: groupsFileName)
        let palettes: [Palette] = try readJSONArray(url.appendingPathComponent(palettesFileName), decoder: decoder, name: palettesFileName)
        let presets: [Preset] = try readJSONArray(url.appendingPathComponent(presetsFileName), decoder: decoder, name: presetsFileName)
        let songs: [Song] = try readJSONArray(url.appendingPathComponent(songsFileName), decoder: decoder, name: songsFileName)
        let mediaAssets: [MediaAssetRef] = try readJSONArray(url.appendingPathComponent(mediaAssetsFileName), decoder: decoder, name: mediaAssetsFileName)
        let midiMappings: [MIDIMapping] = try readJSONArray(url.appendingPathComponent(midiMappingsFileName), decoder: decoder, name: midiMappingsFileName)

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
            let data = try Data(contentsOf: url)
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
        name: String
    ) throws -> [T] {
        // Missing optional collections default to empty for forward-friendly packages.
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        return try readJSON(from: url, as: [T].self, decoder: decoder, missingName: name)
    }
}
