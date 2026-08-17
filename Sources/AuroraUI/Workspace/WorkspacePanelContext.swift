import AuroraCore
import AuroraModel
import Foundation

/// Dependencies injected into workspace panels.
@MainActor
public struct WorkspacePanelContext {
    public var session: DocumentSession
    public var project: ShowProject { session.project }
    /// Optional library for fixture browser (nil → placeholder / empty).
    public var fixtureLibrary: FixtureLibraryBox?
    /// Open Prism package URL when the document is on disk (C4.5 Stage media resolution).
    public var packageURL: URL?

    public init(
        session: DocumentSession,
        fixtureLibrary: FixtureLibraryBox? = nil,
        packageURL: URL? = nil
    ) {
        self.session = session
        self.fixtureLibrary = fixtureLibrary
        self.packageURL = packageURL
    }
}

/// Type-erased fixture library surface so AuroraUI need not import AuroraFixtureLib.
@MainActor
public struct FixtureLibraryBox {
    public var definitions: [FixtureDefinition]
    public var builtInDefinitionIDs: Set<UUID>
    public var userDefinitionIDs: Set<UUID>
    public var search: (String) -> [FixtureDefinition]
    public var makeEmbeddableCopy: (FixtureDefinition) -> FixtureDefinition
    public var removeUserDefinitions: (Set<UUID>) throws -> Void

    public init(
        definitions: [FixtureDefinition],
        builtInDefinitionIDs: Set<UUID> = [],
        userDefinitionIDs: Set<UUID> = [],
        search: @escaping (String) -> [FixtureDefinition],
        makeEmbeddableCopy: @escaping (FixtureDefinition) -> FixtureDefinition,
        removeUserDefinitions: @escaping (Set<UUID>) throws -> Void = { _ in }
    ) {
        self.definitions = definitions
        self.builtInDefinitionIDs = builtInDefinitionIDs
        self.userDefinitionIDs = userDefinitionIDs
        self.search = search
        self.makeEmbeddableCopy = makeEmbeddableCopy
        self.removeUserDefinitions = removeUserDefinitions
    }
}
