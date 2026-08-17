import AuroraFixtureLib
import AuroraModel
import Foundation

enum UserFixtureLibraryStore {
    private static let directoryKey = "Prism.UserFixtureLibrary.Directory"

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Prism/Fixture Library", isDirectory: true)
    }

    static var configuredDirectory: URL {
        guard let path = UserDefaults.standard.string(forKey: directoryKey), !path.isEmpty else {
            return defaultDirectory
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setDirectory(_ url: URL?) throws {
        let directory = url ?? defaultDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if url == nil {
            UserDefaults.standard.removeObject(forKey: directoryKey)
        } else {
            UserDefaults.standard.set(directory.standardizedFileURL.path, forKey: directoryKey)
        }
    }

    static func load() throws -> [FixtureDefinition] {
        let directory = configuredDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        return try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap {
            try FixtureImporter.importDefinitions(from: $0)
        }
    }

    static func add(_ definitions: [FixtureDefinition]) throws {
        let directory = configuredDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for definition in definitions {
            let destination = directory.appendingPathComponent("\(definition.id.uuidString).json")
            try encoder.encode(definition).write(to: destination, options: .atomic)
        }
    }

    static func remove(ids: Set<UUID>) throws {
        let directory = configuredDirectory
        for id in ids {
            let url = directory.appendingPathComponent("\(id.uuidString).json")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
