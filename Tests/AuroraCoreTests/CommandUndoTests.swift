import AuroraCore
import AuroraModel
import Foundation
import XCTest

@MainActor
final class CommandUndoTests: XCTestCase {
    private func makeBaseline() -> ShowProject {
        var project = ShowProject.empty(name: "Baseline")
        let universeID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let definitionID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        project.universes = [
            Universe(id: universeID, number: 1, name: "U1")
        ]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "Generic",
                model: "Dimmer",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "Int", attribute: "intensity")]
            )
        ]
        project.groups = [
            Group(id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!, name: "All", fixtureIds: [])
        ]
        return project
    }

    private func makeFixture(
        id: UUID = UUID(),
        address: UInt16,
        project: ShowProject
    ) -> PatchedFixture {
        PatchedFixture(
            id: id,
            name: "F\(address)",
            definitionId: project.fixtureDefinitions[0].id,
            universeId: project.universes[0].id,
            address: address,
            groupIds: project.groups.isEmpty ? [] : [project.groups[0].id]
        )
    }

    func testAddThenUndoRestoresProject() throws {
        let baseline = makeBaseline()
        let session = DocumentSession(project: baseline)
        let fixture = makeFixture(address: 1, project: baseline)

        try session.perform(AddPatchedFixtureCommand(fixture: fixture))
        XCTAssertEqual(session.project.fixtures.count, 1)
        XCTAssertTrue(session.canUndo)
        XCTAssertTrue(session.isDirty)

        try session.undo()
        XCTAssertEqual(session.project.fixtures.count, 0)
        XCTAssertEqual(session.project.fixtures, baseline.fixtures)
        XCTAssertTrue(session.canRedo)
    }

    func testAddUndoRedo() throws {
        let baseline = makeBaseline()
        let session = DocumentSession(project: baseline)
        let fixture = makeFixture(address: 1, project: baseline)

        try session.perform(AddPatchedFixtureCommand(fixture: fixture))
        try session.undo()
        try session.redo()
        XCTAssertEqual(session.project.fixtures.count, 1)
        XCTAssertEqual(session.project.fixtures[0].id, fixture.id)
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    func testRemoveRestoresGroupMembershipOnUndo() throws {
        var baseline = makeBaseline()
        let fixtureID = UUID(uuidString: "10000000-0000-4000-8000-000000000010")!
        let fixture = makeFixture(id: fixtureID, address: 1, project: baseline)
        baseline.fixtures = [fixture]
        baseline.groups[0].fixtureIds = [fixtureID]

        let session = DocumentSession(project: baseline)
        try session.perform(RemovePatchedFixtureCommand(fixtureID: fixtureID))
        XCTAssertTrue(session.project.fixtures.isEmpty)
        XCTAssertTrue(session.project.groups[0].fixtureIds.isEmpty)

        try session.undo()
        XCTAssertEqual(session.project.fixtures.count, 1)
        XCTAssertEqual(session.project.groups[0].fixtureIds, [fixtureID])
    }

    func testRenameUndoRedo() throws {
        let session = DocumentSession(project: makeBaseline())
        try session.perform(RenameProjectCommand(newName: "Show A"))
        XCTAssertEqual(session.project.metadata.name, "Show A")
        try session.undo()
        XCTAssertEqual(session.project.metadata.name, "Baseline")
        try session.redo()
        XCTAssertEqual(session.project.metadata.name, "Show A")
    }

    func testGroupOfTwoAddsUndoesAsOne() throws {
        let baseline = makeBaseline()
        let session = DocumentSession(project: baseline)
        let a = makeFixture(address: 1, project: baseline)
        let b = makeFixture(address: 2, project: baseline)

        try session.beginGroup(named: "Add pair")
        try session.perform(AddPatchedFixtureCommand(fixture: a))
        try session.perform(AddPatchedFixtureCommand(fixture: b))
        try session.endGroup()

        XCTAssertEqual(session.project.fixtures.count, 2)
        try session.undo()
        XCTAssertEqual(session.project.fixtures.count, 0)
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.canRedo)
    }

    func testCoalesceRenames() throws {
        let session = DocumentSession(project: makeBaseline())
        try session.perform(RenameProjectCommand(newName: "A"))
        try session.perform(RenameProjectCommand(newName: "B"))
        try session.perform(RenameProjectCommand(newName: "C"))
        XCTAssertEqual(session.project.metadata.name, "C")
        // Coalesced into one undo step.
        try session.undo()
        XCTAssertEqual(session.project.metadata.name, "Baseline")
        XCTAssertFalse(session.canUndo)
    }

    func testAddMissingUniverseLeavesProjectUnchanged() throws {
        let baseline = makeBaseline()
        let session = DocumentSession(project: baseline)
        let fixture = PatchedFixture(
            name: "X",
            definitionId: baseline.fixtureDefinitions[0].id,
            universeId: UUID(),
            address: 1
        )
        XCTAssertThrowsError(try session.perform(AddPatchedFixtureCommand(fixture: fixture))) { error in
            guard case CommandError.universeNotFound = error else {
                return XCTFail("Unexpected \(error)")
            }
        }
        XCTAssertEqual(session.project.fixtures, baseline.fixtures)
        XCTAssertFalse(session.canUndo)
    }

    func testRemoveMissingFixtureThrows() throws {
        let session = DocumentSession(project: makeBaseline())
        XCTAssertThrowsError(try session.perform(RemovePatchedFixtureCommand(fixtureID: UUID()))) { error in
            guard case CommandError.fixtureNotFound = error else {
                return XCTFail("Unexpected \(error)")
            }
        }
    }

    func testPatchOverlapThrows() throws {
        var baseline = makeBaseline()
        let existing = makeFixture(address: 1, project: baseline)
        baseline.fixtures = [existing]
        let session = DocumentSession(project: baseline)
        let overlap = makeFixture(address: 1, project: baseline)
        XCTAssertThrowsError(try session.perform(AddPatchedFixtureCommand(fixture: overlap))) { error in
            guard case CommandError.patchOverlap = error else {
                return XCTFail("Unexpected \(error)")
            }
        }
        XCTAssertEqual(session.project.fixtures.count, 1)
    }
}
