import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class StagePlacementCommandTests: XCTestCase {
    private func sessionWithFixture() -> (DocumentSession, UUID) {
        var p = ShowProject.empty(name: "S")
        let u = Universe(number: 1)
        let def = FixtureDefinition(
            manufacturer: "G",
            model: "Dim",
            channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
        )
        let fx = UUID()
        p.universes = [u]
        p.fixtureDefinitions = [def]
        p.fixtures = [
            PatchedFixture(id: fx, name: "D1", definitionId: def.id, universeId: u.id, address: 1),
        ]
        return (DocumentSession(project: p), fx)
    }

    func testPlaceAndRemoveFromStageKeepsFixture() throws {
        let (session, fx) = sessionWithFixture()
        try session.perform(PlaceFixtureOnStageCommand(fixtureID: fx, x: 100, y: 120))
        XCTAssertEqual(session.project.stageLayout.fixtures.count, 1)
        XCTAssertEqual(session.project.fixtures.count, 1)

        try session.perform(RemoveFromStageCommand(fixtureIDs: [fx]))
        XCTAssertTrue(session.project.stageLayout.fixtures.isEmpty)
        XCTAssertEqual(session.project.fixtures.count, 1) // still patched
    }

    func testPlaceAllUnplaced() throws {
        let (session, fx) = sessionWithFixture()
        // add second fixture
        let def = session.project.fixtureDefinitions[0]
        let u = session.project.universes[0]
        let fx2 = UUID()
        try session.perform(AddPatchedFixtureCommand(fixture: PatchedFixture(
            id: fx2, name: "D2", definitionId: def.id, universeId: u.id, address: 2
        )))
        try session.perform(PlaceAllUnplacedCommand())
        XCTAssertEqual(session.project.stageLayout.fixtures.count, 2)
        try session.undo()
        XCTAssertTrue(session.project.stageLayout.fixtures.isEmpty)
        _ = fx
    }
}
