import AuroraDiagnostics
import Foundation

/// Portable cross-show Aurora Library package (P0-E / Post-C6 integrity).
/// Directory bundle of reusable assets independent of a full show.
public enum AuroraLibraryPackage {
    /// Preferred external extension for Prism library exports.
    public static let packageExtension = "prismlib"
    /// Legacy Aurora extension retained for importing existing libraries.
    public static let legacyPackageExtension = "auroralib"
    public static let currentSchemaVersion = 1
    /// Defense-in-depth JSON size cap (same order as project packages).
    public static let maxJSONFileBytes = 32 * 1024 * 1024

    public struct Manifest: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var name: String
        public var createdAt: Date
        public var notes: String

        public init(
            schemaVersion: Int = AuroraLibraryPackage.currentSchemaVersion,
            name: String,
            createdAt: Date = Date(),
            notes: String = ""
        ) {
            self.schemaVersion = schemaVersion
            self.name = name
            self.createdAt = createdAt
            self.notes = notes
        }
    }

    public struct Contents: Equatable, Sendable {
        public var manifest: Manifest
        public var fixtureDefinitions: [FixtureDefinition]
        public var physicalFixtureDefinitions: [FixturePhysicalDefinition]
        public var palettes: [Palette]
        public var presets: [Preset]
        public var effects: [EffectDefinition]
        public var midiMappings: [MIDIMapping]
        public var midiRules: [MIDIRule]
        public var midiBehaviors: [MIDIBehaviorDefinition]
        public var drumProfiles: [DrumDeviceProfile]
        public var feedbackProfiles: [MIDIFeedbackProfile]

        public init(
            manifest: Manifest,
            fixtureDefinitions: [FixtureDefinition] = [],
            physicalFixtureDefinitions: [FixturePhysicalDefinition] = [],
            palettes: [Palette] = [],
            presets: [Preset] = [],
            effects: [EffectDefinition] = [],
            midiMappings: [MIDIMapping] = [],
            midiRules: [MIDIRule] = [],
            midiBehaviors: [MIDIBehaviorDefinition] = [],
            drumProfiles: [DrumDeviceProfile] = [],
            feedbackProfiles: [MIDIFeedbackProfile] = []
        ) {
            self.manifest = manifest
            self.fixtureDefinitions = fixtureDefinitions
            self.physicalFixtureDefinitions = physicalFixtureDefinitions
            self.palettes = palettes
            self.presets = presets
            self.effects = effects
            self.midiMappings = midiMappings
            self.midiRules = midiRules
            self.midiBehaviors = midiBehaviors
            self.drumProfiles = drumProfiles
            self.feedbackProfiles = feedbackProfiles
        }

        /// Slice assets from a show for export.
        public static func from(project: ShowProject, name: String) -> Contents {
            Contents(
                manifest: Manifest(name: name),
                fixtureDefinitions: project.fixtureDefinitions,
                physicalFixtureDefinitions: project.physicalFixtureDefinitions ?? [],
                palettes: project.palettes,
                presets: project.presets,
                effects: project.effects,
                midiMappings: project.midiMappings,
                midiRules: project.midiRules,
                midiBehaviors: project.midiBehaviors,
                drumProfiles: project.drumProfiles,
                feedbackProfiles: project.midiFeedbackProfiles
            )
        }
    }

    public enum LibraryError: Error, Equatable, Sendable {
        case notADirectory
        case unsupportedSchema(Int)
        case missingFile(String)
        case decodingFailed(String)
        case io(String)
    }

    /// Content files always written for schema v1 — required on load.
    public static let requiredContentFiles: [String] = [
        "definitions.json",
        "palettes.json",
        "presets.json",
        "effects.json",
        "midi-mappings.json",
        "midi-rules.json",
        "midi-behaviors.json",
        "drum-profiles.json",
        "midi-feedback.json",
    ]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func save(_ contents: Contents, to url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        let tmp = parent.appendingPathComponent(".auroralib-tmp-\(UUID().uuidString)")
        let backup = parent.appendingPathComponent(".auroralib-bak-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            try writeJSON(contents.manifest, to: tmp.appendingPathComponent("manifest.json"))
            try writeJSON(contents.fixtureDefinitions, to: tmp.appendingPathComponent("definitions.json"))
            try writeJSON(contents.physicalFixtureDefinitions, to: tmp.appendingPathComponent("physical-fixtures.json"))
            try writeJSON(contents.palettes, to: tmp.appendingPathComponent("palettes.json"))
            try writeJSON(contents.presets, to: tmp.appendingPathComponent("presets.json"))
            try writeJSON(contents.effects, to: tmp.appendingPathComponent("effects.json"))
            try writeJSON(contents.midiMappings, to: tmp.appendingPathComponent("midi-mappings.json"))
            try writeJSON(contents.midiRules, to: tmp.appendingPathComponent("midi-rules.json"))
            try writeJSON(contents.midiBehaviors, to: tmp.appendingPathComponent("midi-behaviors.json"))
            try writeJSON(contents.drumProfiles, to: tmp.appendingPathComponent("drum-profiles.json"))
            try writeJSON(contents.feedbackProfiles, to: tmp.appendingPathComponent("midi-feedback.json"))

            // Backup/replace so a failed move cannot erase a valid library (Post-C6).
            if fm.fileExists(atPath: url.path) {
                if fm.fileExists(atPath: backup.path) { try? fm.removeItem(at: backup) }
                try fm.moveItem(at: url, to: backup)
            }
            do {
                try fm.moveItem(at: tmp, to: url)
            } catch {
                if fm.fileExists(atPath: backup.path) {
                    try? fm.removeItem(at: url)
                    try? fm.moveItem(at: backup, to: url)
                }
                try? fm.removeItem(at: tmp)
                throw LibraryError.io(error.localizedDescription)
            }
            try? fm.removeItem(at: backup)
        } catch let error as LibraryError {
            try? fm.removeItem(at: tmp)
            throw error
        } catch {
            try? fm.removeItem(at: tmp)
            throw LibraryError.io(error.localizedDescription)
        }
    }

    public static func load(from url: URL) throws -> Contents {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw LibraryError.notADirectory
        }
        let manifest: Manifest = try readJSON(url.appendingPathComponent("manifest.json"), name: "manifest.json")
        guard manifest.schemaVersion <= currentSchemaVersion else {
            throw LibraryError.unsupportedSchema(manifest.schemaVersion)
        }
        // Schema v1: all content files are required; empty arrays are valid, missing files are not.
        return Contents(
            manifest: manifest,
            fixtureDefinitions: try readJSON(url.appendingPathComponent("definitions.json"), name: "definitions.json"),
            physicalFixtureDefinitions: (try? readJSON(url.appendingPathComponent("physical-fixtures.json"), name: "physical-fixtures.json")) ?? [],
            palettes: try readJSON(url.appendingPathComponent("palettes.json"), name: "palettes.json"),
            presets: try readJSON(url.appendingPathComponent("presets.json"), name: "presets.json"),
            effects: try readJSON(url.appendingPathComponent("effects.json"), name: "effects.json"),
            midiMappings: try readJSON(url.appendingPathComponent("midi-mappings.json"), name: "midi-mappings.json"),
            midiRules: try readJSON(url.appendingPathComponent("midi-rules.json"), name: "midi-rules.json"),
            midiBehaviors: try readJSON(url.appendingPathComponent("midi-behaviors.json"), name: "midi-behaviors.json"),
            drumProfiles: try readJSON(url.appendingPathComponent("drum-profiles.json"), name: "drum-profiles.json"),
            feedbackProfiles: try readJSON(url.appendingPathComponent("midi-feedback.json"), name: "midi-feedback.json")
        )
    }

    /// Merge library into show (new UUIDs optional — here we keep IDs and upsert by id).
    public static func merge(_ contents: Contents, into project: inout ShowProject, replaceExisting: Bool = false) {
        func upsert<T: Identifiable>(_ items: [T], into array: inout [T]) where T.ID == UUID {
            for item in items {
                if let idx = array.firstIndex(where: { $0.id == item.id }) {
                    if replaceExisting { array[idx] = item }
                } else {
                    array.append(item)
                }
            }
        }
        upsert(contents.fixtureDefinitions, into: &project.fixtureDefinitions)
        var physical = project.physicalFixtureDefinitions ?? []
        upsert(contents.physicalFixtureDefinitions, into: &physical)
        project.physicalFixtureDefinitions = physical
        upsert(contents.palettes, into: &project.palettes)
        upsert(contents.presets, into: &project.presets)
        upsert(contents.effects, into: &project.effects)
        upsert(contents.midiMappings, into: &project.midiMappings)
        upsert(contents.midiRules, into: &project.midiRules)
        upsert(contents.midiBehaviors, into: &project.midiBehaviors)
        upsert(contents.drumProfiles, into: &project.drumProfiles)
        upsert(contents.feedbackProfiles, into: &project.midiFeedbackProfiles)
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func readJSON<T: Decodable>(_ url: URL, name: String) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryError.missingFile(name)
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs[.size] as? NSNumber, size.intValue > maxJSONFileBytes {
                throw LibraryError.decodingFailed("\(name): file exceeds size limit")
            }
            let data = try Data(contentsOf: url)
            if data.count > maxJSONFileBytes {
                throw LibraryError.decodingFailed("\(name): file exceeds size limit")
            }
            return try decoder.decode(T.self, from: data)
        } catch let error as LibraryError {
            throw error
        } catch {
            throw LibraryError.decodingFailed("\(name): \(error.localizedDescription)")
        }
    }
}

extension AuroraLibraryPackage.LibraryError: LocalizedError, PrismDiagnosableError {
    public var errorDescription: String? { userMessage }
    public var prismErrorCode: String {
        switch self {
        case .notADirectory: return "fixture.library.not_a_package"
        case .unsupportedSchema: return "fixture.library.unsupported_schema"
        case .missingFile: return "fixture.library.missing_file"
        case .decodingFailed: return "fixture.library.decode_failed"
        case .io: return "fixture.library.io_failed"
        }
    }
    public var userTitle: String { "Prism Couldn't Open That Library" }
    public var userMessage: String { "Prism couldn’t open that fixture library package." }
    public var recoverySuggestion: String? { "Choose another library file, or export a new library from Prism." }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .fixtureLibrary }
    public var prismSeverity: PrismLogLevel { .error }
}
