import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class RenameFixtureCommandTests: XCTestCase {
    func testRenameTrimsAndUndoRestoresName() throws {
        let definition = FixtureDefinition(manufacturer: "Test", model: "PAR", modeName: "8ch", channels: [])
        let universe = Universe(number: 1, name: "Main")
        let fixture = PatchedFixture(
            name: "PAR 1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )
        var project = ShowProject.empty()
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [fixture]
        let session = DocumentSession(project: project)

        try session.perform(RenameFixtureCommand(
            fixtureID: fixture.id,
            newName: "  Dance Floor PAR 1  "
        ))
        XCTAssertEqual(session.project.fixtures.first?.name, "Dance Floor PAR 1")

        try session.undo()
        XCTAssertEqual(session.project.fixtures.first?.name, "PAR 1")
    }

    func testRenameRejectsBlankName() throws {
        let definition = FixtureDefinition(manufacturer: "Test", model: "PAR", modeName: "8ch", channels: [])
        let universe = Universe(number: 1, name: "Main")
        let fixture = PatchedFixture(
            name: "PAR 1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )
        var project = ShowProject.empty()
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [fixture]
        let session = DocumentSession(project: project)

        XCTAssertThrowsError(try session.perform(RenameFixtureCommand(
            fixtureID: fixture.id,
            newName: "   "
        )))
        XCTAssertEqual(session.project.fixtures.first?.name, "PAR 1")
    }

    func testRenameRejectsCaseAndWhitespaceEquivalentDuplicate() throws {
        let definition = FixtureDefinition(manufacturer: "Test", model: "PAR", modeName: "8ch", channels: [])
        let universe = Universe(number: 1, name: "Main")
        let first = PatchedFixture(
            name: "Dance Floor PAR 1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )
        let second = PatchedFixture(
            name: "Dance Floor PAR 2",
            definitionId: definition.id,
            universeId: universe.id,
            address: 2
        )
        var project = ShowProject.empty()
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [first, second]
        let session = DocumentSession(project: project)

        XCTAssertThrowsError(try session.perform(RenameFixtureCommand(
            fixtureID: second.id,
            newName: "  dance floor par 1  "
        ))) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "A fixture named ‘dance floor par 1’ already exists"
            )
        }
        XCTAssertEqual(session.project.fixtures.last?.name, "Dance Floor PAR 2")
    }

    func testCloneGeneratesUniqueNames() throws {
        let definition = FixtureDefinition(
            manufacturer: "Test",
            model: "PAR",
            modeName: "1ch",
            channels: [ChannelDef(offset: 1, name: "Dimmer", attribute: "intensity")]
        )
        let universe = Universe(number: 1, name: "Main")
        let fixture = PatchedFixture(
            name: "Dance Floor PAR 1",
            definitionId: definition.id,
            universeId: universe.id,
            address: 1
        )
        var project = ShowProject.empty()
        project.universes = [universe]
        project.fixtureDefinitions = [definition]
        project.fixtures = [fixture]
        let session = DocumentSession(project: project)

        try session.perform(ClonePatchedFixtureCommand(sourceFixtureID: fixture.id))
        try session.perform(ClonePatchedFixtureCommand(sourceFixtureID: fixture.id))

        XCTAssertEqual(
            session.project.fixtures.map(\.name),
            ["Dance Floor PAR 1", "Dance Floor PAR 1 copy", "Dance Floor PAR 1 copy 2"]
        )
    }
}
