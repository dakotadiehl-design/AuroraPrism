import AuroraDiagnostics
import AuroraModel
import Foundation

/// In-memory fixture personality library (bundled seed or caller-supplied definitions).
public final class FixtureLibrary: @unchecked Sendable {
    private let definitionsByID: [UUID: FixtureDefinition]
    private let ordered: [FixtureDefinition]

    public init(definitions: [FixtureDefinition]) throws {
        var map: [UUID: FixtureDefinition] = [:]
        for definition in definitions {
            try FixtureDefinitionValidation.validate(definition)
            if map[definition.id] != nil {
                throw FixtureLibraryError.definitionInvalid("duplicate definition id \(definition.id)")
            }
            map[definition.id] = definition
        }
        self.definitionsByID = map
        self.ordered = definitions
    }

    /// Loads the built-in seed catalog shipped with `AuroraFixtureLib`.
    public static func loadBundledSeed(decoder: JSONDecoder = JSONDecoder()) throws -> FixtureLibrary {
        try load(from: .module, decoder: decoder)
    }

    /// Loads a seed catalog from an arbitrary bundle (tests / alternate roots).
    public static func load(from bundle: Bundle, decoder: JSONDecoder = JSONDecoder()) throws -> FixtureLibrary {
        guard let catalogURL = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Seed")
            ?? bundle.url(forResource: "catalog", withExtension: "json")
        else {
            throw FixtureLibraryError.resourceMissing("Seed/catalog.json")
        }

        let catalogData: Data
        do {
            catalogData = try Data(contentsOf: catalogURL)
        } catch {
            throw FixtureLibraryError.resourceMissing("Seed/catalog.json: \(error.localizedDescription)")
        }

        let catalog: SeedCatalog
        do {
            catalog = try decoder.decode(SeedCatalog.self, from: catalogData)
        } catch {
            throw FixtureLibraryError.catalogInvalid(error.localizedDescription)
        }

        guard catalog.schemaVersion == 1 else {
            throw FixtureLibraryError.catalogInvalid("unsupported schemaVersion \(catalog.schemaVersion)")
        }

        var definitions: [FixtureDefinition] = []
        definitions.reserveCapacity(catalog.entries.count)

        for entry in catalog.entries {
            guard let fileURL = bundle.url(forResource: entry.file.replacingOccurrences(of: ".json", with: ""), withExtension: "json", subdirectory: "Seed")
                ?? bundle.url(forResource: (entry.file as NSString).deletingPathExtension, withExtension: "json", subdirectory: "Seed")
                ?? bundle.url(forResource: (entry.file as NSString).deletingPathExtension, withExtension: "json")
            else {
                throw FixtureLibraryError.resourceMissing("Seed/\(entry.file)")
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw FixtureLibraryError.resourceMissing("Seed/\(entry.file): \(error.localizedDescription)")
            }

            let definition: FixtureDefinition
            do {
                definition = try decoder.decode(FixtureDefinition.self, from: data)
            } catch {
                throw FixtureLibraryError.decodingFailed("\(entry.file): \(error.localizedDescription)")
            }

            if definition.id != entry.id {
                throw FixtureLibraryError.catalogInvalid(
                    "catalog id \(entry.id) does not match file id \(definition.id) for \(entry.file)"
                )
            }
            try FixtureDefinitionValidation.validate(definition)
            definitions.append(definition)
        }

        let library = try FixtureLibrary(definitions: definitions)
        PrismLog.notice(
            .fixtureLibrary,
            "fixture.library.loaded",
            "Loaded fixture personalities.",
            metadata: ["count": .count(library.definitions.count)]
        )
        return library
    }

    public var definitions: [FixtureDefinition] { ordered }

    public var manufacturers: [String] {
        Array(Set(ordered.map(\.manufacturer))).sorted()
    }

    public func definitions(manufacturer: String) -> [FixtureDefinition] {
        ordered.filter { $0.manufacturer.caseInsensitiveCompare(manufacturer) == .orderedSame }
    }

    public func lookup(manufacturer: String, model: String, modeName: String) -> FixtureDefinition? {
        ordered.first {
            $0.manufacturer.caseInsensitiveCompare(manufacturer) == .orderedSame
                && $0.model.caseInsensitiveCompare(model) == .orderedSame
                && $0.modeName.caseInsensitiveCompare(modeName) == .orderedSame
        }
    }

    public func definition(id: UUID) -> FixtureDefinition? {
        definitionsByID[id]
    }

    public func search(_ query: String) -> [FixtureDefinition] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return ordered }
        return ordered.filter { definition in
            definition.manufacturer.localizedCaseInsensitiveContains(q)
                || definition.model.localizedCaseInsensitiveContains(q)
                || definition.modeName.localizedCaseInsensitiveContains(q)
                || definition.displayName.localizedCaseInsensitiveContains(q)
        }
    }

    /// Returns a copy safe to embed in a project. Regenerates definition and channel/wheel ids by default.
    public func makeEmbeddableCopy(
        _ definition: FixtureDefinition,
        newID: UUID = UUID(),
        regenerateChildIDs: Bool = true
    ) -> FixtureDefinition {
        var copy = definition
        copy.id = newID
        if regenerateChildIDs {
            copy.channels = definition.channels.map { channel in
                var c = channel
                c.id = UUID()
                return c
            }
            copy.wheels = definition.wheels.map { wheel in
                var w = wheel
                w.id = UUID()
                w.slots = wheel.slots.map { slot in
                    var s = slot
                    s.id = UUID()
                    return s
                }
                return w
            }
        }
        return copy
    }
}
