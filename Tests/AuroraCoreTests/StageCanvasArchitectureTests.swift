import AuroraCore
import AuroraEngine
import AuroraModel
import XCTest

/// Checkpoint C1 — shared Stage model / geometry lock semantics (no pixel tests).
@MainActor
final class StageCanvasArchitectureTests: XCTestCase {
    private func dimmer() -> FixtureDefinition {
        FixtureDefinition(
            manufacturer: "Generic",
            model: "Dimmer",
            modeName: "1ch",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "Intensity", attribute: "intensity")]
        )
    }

    func testGeometryLockModeDoesNotRequireSeparateLayoutCopy() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let fx = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 1)
        var project = ShowProject.empty(name: "C1")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [fx]
        project.stageLayout = StageLayout(fixtures: [
            StageFixturePlacement(fixtureID: fx.id, x: 100, y: 200)
        ])
        let session = DocumentSession(project: project)

        // Simulate two hosts reading the same layout identity.
        let layoutA = session.project.stageLayout
        let layoutB = session.project.stageLayout
        XCTAssertEqual(layoutA.fixtures.first?.fixtureID, layoutB.fixtures.first?.fixtureID)
        XCTAssertEqual(layoutA.fixtures.first?.x, 100)

        // Only an explicit layout command mutates geometry.
        var next = session.project.stageLayout
        next.fixtures[0].x = 150
        try session.perform(UpdateStageLayoutCommand(layout: next))
        XCTAssertEqual(session.project.stageLayout.fixtures.first?.x, 150)

        // Remove From Stage preserves fixture identity / patch.
        try session.perform(RemoveFromStageCommand(fixtureIDs: [fx.id]))
        XCTAssertTrue(session.project.stageLayout.fixtures.isEmpty)
        XCTAssertEqual(session.project.fixtures.first?.id, fx.id)
        XCTAssertEqual(session.project.fixtures.first?.address, 1)
    }

    func testPreviewBuilderConsumesSameProjectFixtures() {
        let project = ShowProject.demoSummerNight()
        let look = ActiveLook(
            fixtureAttributes: Dictionary(
                uniqueKeysWithValues: project.fixtures.map { ($0.id, ["intensity": 0.5]) }
            )
        )
        let snap = StagePreviewBuilder.build(
            project: project,
            look: look,
            frameIndex: 1,
            time: 0,
            global: GlobalShowControlState()
        )
        XCTAssertEqual(snap.fixtures.count, project.fixtures.count)
        // Same fixture IDs appear in snapshot — one semantic truth.
        let snapIDs = Set(snap.fixtures.map(\.fixtureID))
        let projectIDs = Set(project.fixtures.map(\.id))
        XCTAssertEqual(snapIDs, projectIDs)
    }

    func testPlaceAndRemovePreservesPatchAndGroups() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let fx = PatchedFixture(name: "M", definitionId: def.id, universeId: universe.id, address: 4)
        var project = ShowProject.empty(name: "Place")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [fx]
        project.groups = [Group(name: "G", fixtureIds: [fx.id])]
        let session = DocumentSession(project: project)

        try session.perform(PlaceFixtureOnStageCommand(fixtureID: fx.id, x: 40, y: 60))
        XCTAssertEqual(session.project.stageLayout.fixtures.count, 1)
        try session.perform(RemoveFromStageCommand(fixtureIDs: [fx.id]))
        XCTAssertTrue(session.project.stageLayout.fixtures.isEmpty)
        XCTAssertTrue(session.project.groups[0].fixtureIds.contains(fx.id))
        XCTAssertEqual(session.project.fixtures.first?.address, 4)
    }
}
