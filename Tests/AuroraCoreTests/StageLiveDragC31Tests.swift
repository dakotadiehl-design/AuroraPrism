import AuroraCore
import AuroraModel
import XCTest

/// C3.1 — one drag = one undoable layout command (commit semantics).
@MainActor
final class StageLiveDragC31Tests: XCTestCase {
    private func setup() throws -> (DocumentSession, UUID, UUID) {
        let universe = Universe(number: 1)
        let def = FixtureDefinition(
            manufacturer: "G", model: "D", modeName: "1", channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
        )
        let a = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 1)
        let b = PatchedFixture(name: "B", definitionId: def.id, universeId: universe.id, address: 2)
        var project = ShowProject.empty(name: "Drag")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [a, b]
        project.stageLayout = StageLayout(fixtures: [
            StageFixturePlacement(fixtureID: a.id, x: 100, y: 100),
            StageFixturePlacement(fixtureID: b.id, x: 150, y: 100),
        ])
        return (DocumentSession(project: project), a.id, b.id)
    }

    func testSingleMoveOneUndo() throws {
        let (session, a, _) = try setup()
        var layout = session.project.stageLayout
        layout.fixtures[0].x = 140
        layout.fixtures[0].y = 80
        try session.perform(UpdateStageLayoutCommand(layout: layout))
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == a }?.x, 140)
        try session.undo()
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == a }?.x, 100)
        try session.redo()
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == a }?.x, 140)
    }

    func testMultiMovePreservesSpacingAndOneUndo() throws {
        let (session, a, b) = try setup()
        var layout = session.project.stageLayout
        // Same delta (+40, -20) for both
        for i in layout.fixtures.indices {
            layout.fixtures[i].x += 40
            layout.fixtures[i].y -= 20
        }
        try session.perform(UpdateStageLayoutCommand(layout: layout))
        let pa = session.project.stageLayout.fixtures.first { $0.fixtureID == a }!
        let pb = session.project.stageLayout.fixtures.first { $0.fixtureID == b }!
        XCTAssertEqual(pb.x - pa.x, 50, accuracy: 0.001)
        try session.undo()
        let pa2 = session.project.stageLayout.fixtures.first { $0.fixtureID == a }!
        let pb2 = session.project.stageLayout.fixtures.first { $0.fixtureID == b }!
        XCTAssertEqual(pa2.x, 100, accuracy: 0.001)
        XCTAssertEqual(pb2.x, 150, accuracy: 0.001)
    }

    func testLockedFixtureUnchangedWhenOthersMove() throws {
        let (session, a, b) = try setup()
        var layout = session.project.stageLayout
        if let i = layout.fixtures.firstIndex(where: { $0.fixtureID == a }) {
            layout.fixtures[i].locked = true
        }
        try session.perform(UpdateStageLayoutCommand(layout: layout))

        var next = session.project.stageLayout
        // Only move B
        if let i = next.fixtures.firstIndex(where: { $0.fixtureID == b }) {
            next.fixtures[i].x = 200
        }
        try session.perform(UpdateStageLayoutCommand(layout: next))
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == a }?.x, 100)
        XCTAssertEqual(session.project.stageLayout.fixtures.first { $0.fixtureID == b }?.x, 200)
    }
}
