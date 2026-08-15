import AuroraCore
import AuroraModel
import XCTest

/// Checkpoint C3 — Edit Stage semantics (geometry vs identity).
@MainActor
final class EditStageC3Tests: XCTestCase {
    private func dimmer() -> FixtureDefinition {
        FixtureDefinition(
            manufacturer: "G",
            model: "D",
            modeName: "1",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
        )
    }

    func testRemoveFromStagePreservesFixturePatchAndGroups() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let fx = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 7)
        var project = ShowProject.empty(name: "C3")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [fx]
        project.groups = [Group(name: "G", fixtureIds: [fx.id])]
        project.stageLayout = StageLayout(fixtures: [
            StageFixturePlacement(fixtureID: fx.id, x: 50, y: 60)
        ])
        let session = DocumentSession(project: project)

        try session.perform(RemoveFromStageCommand(fixtureIDs: [fx.id]))
        XCTAssertTrue(session.project.stageLayout.fixtures.isEmpty)
        XCTAssertEqual(session.project.fixtures.first?.id, fx.id)
        XCTAssertEqual(session.project.fixtures.first?.address, 7)
        XCTAssertTrue(session.project.groups[0].fixtureIds.contains(fx.id))
    }

    func testPlaceThenRemoveReturnsToUnplaced() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let fx = PatchedFixture(name: "B", definitionId: def.id, universeId: universe.id, address: 1)
        var project = ShowProject.empty(name: "C3b")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [fx]
        let session = DocumentSession(project: project)

        try session.perform(PlaceFixtureOnStageCommand(fixtureID: fx.id, x: 10, y: 20))
        XCTAssertEqual(session.project.stageLayout.fixtures.count, 1)
        let unplacedBeforeRemove = session.project.fixtures.filter {
            !session.project.stageLayout.fixtures.map(\.fixtureID).contains($0.id)
        }
        XCTAssertTrue(unplacedBeforeRemove.isEmpty)

        try session.perform(RemoveFromStageCommand(fixtureIDs: [fx.id]))
        let unplaced = session.project.fixtures.filter {
            !session.project.stageLayout.fixtures.map(\.fixtureID).contains($0.id)
        }
        XCTAssertEqual(unplaced.map(\.id), [fx.id])
    }

    func testLayoutMutationDoesNotChangePatchAddresses() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let fx = PatchedFixture(name: "C", definitionId: def.id, universeId: universe.id, address: 12)
        var project = ShowProject.empty(name: "C3c")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [fx]
        project.stageLayout = StageLayout(fixtures: [
            StageFixturePlacement(fixtureID: fx.id, x: 100, y: 100)
        ])
        let session = DocumentSession(project: project)

        var layout = session.project.stageLayout
        layout.fixtures[0].x = 200
        layout.fixtures[0].y = 150
        try session.perform(UpdateStageLayoutCommand(layout: layout))
        XCTAssertEqual(session.project.stageLayout.fixtures.first?.x, 200)
        XCTAssertEqual(session.project.fixtures.first?.address, 12)
    }
}
