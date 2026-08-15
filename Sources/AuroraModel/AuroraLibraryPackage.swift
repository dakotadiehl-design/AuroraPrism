import Foundation

/// Portable cross-show Aurora Library package (P0-E).
/// Directory bundle of reusable assets independent of a full show.
public enum AuroraLibraryPackage {
    public static let packageExtension = "auroralib"
    public static let currentSchemaVersion = 1

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
        case io(String)
    }

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
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".auroralib-tmp-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        do {
            try writeJSON(contents.manifest, to: tmp.appendingPathComponent("manifest.json"))
            try writeJSON(contents.fixtureDefinitions, to: tmp.appendingPathComponent("definitions.json"))
            try writeJSON(contents.palettes, to: tmp.appendingPathComponent("palettes.json"))
            try writeJSON(contents.presets, to: tmp.appendingPathComponent("presets.json"))
            try writeJSON(contents.effects, to: tmp.appendingPathComponent("effects.json"))
            try writeJSON(contents.midiMappings, to: tmp.appendingPathComponent("midi-mappings.json"))
            try writeJSON(contents.midiRules, to: tmp.appendingPathComponent("midi-rules.json"))
            try writeJSON(contents.midiBehaviors, to: tmp.appendingPathComponent("midi-behaviors.json"))
            try writeJSON(contents.drumProfiles, to: tmp.appendingPathComponent("drum-profiles.json"))
            try writeJSON(contents.feedbackProfiles, to: tmp.appendingPathComponent("midi-feedback.json"))
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            try fm.moveItem(at: tmp, to: url)
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
        let manifest: Manifest = try readJSON(url.appendingPathComponent("manifest.json"))
        guard manifest.schemaVersion <= currentSchemaVersion else {
            throw LibraryError.unsupportedSchema(manifest.schemaVersion)
        }
        return Contents(
            manifest: manifest,
            fixtureDefinitions: (try? readJSON(url.appendingPathComponent("definitions.json"))) ?? [],
            palettes: (try? readJSON(url.appendingPathComponent("palettes.json"))) ?? [],
            presets: (try? readJSON(url.appendingPathComponent("presets.json"))) ?? [],
            effects: (try? readJSON(url.appendingPathComponent("effects.json"))) ?? [],
            midiMappings: (try? readJSON(url.appendingPathComponent("midi-mappings.json"))) ?? [],
            midiRules: (try? readJSON(url.appendingPathComponent("midi-rules.json"))) ?? [],
            midiBehaviors: (try? readJSON(url.appendingPathComponent("midi-behaviors.json"))) ?? [],
            drumProfiles: (try? readJSON(url.appendingPathComponent("drum-profiles.json"))) ?? [],
            feedbackProfiles: (try? readJSON(url.appendingPathComponent("midi-feedback.json"))) ?? []
        )
    }

    /// Merge library into show (new UUIDs optional — here we keep IDs and upsert by id).
    public static func merge(_ contents: Contents, into project: inout ShowProject, replaceExisting: Bool = false) {
        func upsert<T: Identifiable>(_ items: [T], into array: inout [T]) where T.ID == UUID, T: Equatable {
            for item in items {
                if let idx = array.firstIndex(where: { $0.id == item.id }) {
                    if replaceExisting { array[idx] = item }
                } else {
                    array.append(item)
                }
            }
        }
        upsert(contents.fixtureDefinitions, into: &project.fixtureDefinitions)
        upsert(contents.palettes, into: &project.palettes)
        upsert(contents.presets, into: &project.presets)
        upsert(contents.effects, into: &project.effects)
        upsert(contents.midiMappings, into: &project.midiMappings)
        upsert(contents.midiRules, into: &project.midiRules)
        upsert(contents.midiBehaviors, into: &project.midiBehaviors)
        upsert(contents.drumProfiles, into: &project.drumProfiles)
        upsert(contents.feedbackProfiles, into: &project.midiFeedbackProfiles)
        project.metadata.modifiedAt = Date()
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func readJSON<T: Decodable>(_ url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }
}
