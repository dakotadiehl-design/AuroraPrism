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

    public init(session: DocumentSession, fixtureLibrary: FixtureLibraryBox? = nil) {
        self.session = session
        self.fixtureLibrary = fixtureLibrary
    }
}

/// Type-erased fixture library surface so AuroraUI need not import AuroraFixtureLib.
@MainActor
public struct FixtureLibraryBox {
    public var definitions: [FixtureDefinition]
    public var search: (String) -> [FixtureDefinition]
    public var makeEmbeddableCopy: (FixtureDefinition) -> FixtureDefinition

    public init(
        definitions: [FixtureDefinition],
        search: @escaping (String) -> [FixtureDefinition],
        makeEmbeddableCopy: @escaping (FixtureDefinition) -> FixtureDefinition
    ) {
        self.definitions = definitions
        self.search = search
        self.makeEmbeddableCopy = makeEmbeddableCopy
    }
}
