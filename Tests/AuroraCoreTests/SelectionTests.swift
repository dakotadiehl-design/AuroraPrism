import AuroraCore
import AuroraModel
import Foundation
import XCTest

@MainActor
final class SelectionTests: XCTestCase {
    private func projectWithFixture() -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "S")
        let universeID = UUID()
        let definitionID = UUID()
        let fixtureID = UUID()
        project.universes = [Universe(id: universeID, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "G",
                model: "D",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "F1",
                definitionId: definitionID,
                universeId: universeID,
                address: 1
            )
        ]
        return (project, fixtureID)
    }

    func testSelectAndClearFixtures() {
        let session = DocumentSession(project: ShowProject.empty())
        let id = UUID()
        var events: [AppEvent] = []
        _ = session.eventBus.subscribe { events.append($0) }

        session.selectFixtures([id])
        XCTAssertEqual(session.selection.snapshot.fixtureIDs, [id])
        XCTAssertEqual(events.last, .selectionChanged(SelectionSnapshot(fixtureIDs: [id])))

        session.clearSelection()
        XCTAssertTrue(session.selection.snapshot.isEmpty)
    }

    func testMultiSelectExtending() {
        let session = DocumentSession(project: ShowProject.empty())
        let a = UUID()
        let b = UUID()
        session.selectFixtures([a])
        session.selectFixtures([b], extending: true)
        XCTAssertEqual(session.selection.snapshot.fixtureIDs, [a, b])
    }

    func testOrderedFixtureSelectionPreservesClickOrder() {
        let session = DocumentSession(project: ShowProject.empty())
        let a = UUID()
        let b = UUID()
        let c = UUID()
        session.selectFixturesOrdered([c, a, b])
        XCTAssertEqual(session.selection.snapshot.orderedFixtureIDs, [c, a, b])
        XCTAssertEqual(session.selection.snapshot.fixtureIDs, Set([a, b, c]))

        session.selectFixturesOrdered([a], extending: true) // already selected — no change
        XCTAssertEqual(session.selection.snapshot.orderedFixtureIDs, [c, a, b])

        let d = UUID()
        session.selectFixturesOrdered([d], extending: true)
        XCTAssertEqual(session.selection.snapshot.orderedFixtureIDs, [c, a, b, d])
    }

    func testTogglePreservesOrderOfRemaining() {
        let manager = SelectionManager()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        manager.selectFixturesOrdered([a, b, c])
        manager.toggleFixture(b)
        XCTAssertEqual(manager.snapshot.orderedFixtureIDs, [a, c])
        manager.toggleFixture(b)
        XCTAssertEqual(manager.snapshot.orderedFixtureIDs, [a, c, b])
    }

    func testRemoveSelectedFixturePrunesSelection() throws {
        let (project, fixtureID) = projectWithFixture()
        let session = DocumentSession(project: project)
        session.selectFixtures([fixtureID])
        XCTAssertEqual(session.selection.snapshot.fixtureIDs, [fixtureID])

        var sawSelectionChange = false
        _ = session.eventBus.subscribe { event in
            if case .selectionChanged(let snap) = event, snap.fixtureIDs.isEmpty {
                sawSelectionChange = true
            }
        }

        try session.perform(RemovePatchedFixtureCommand(fixtureID: fixtureID))
        XCTAssertTrue(session.selection.snapshot.fixtureIDs.isEmpty)
        XCTAssertTrue(sawSelectionChange)
    }

    func testUndoDoesNotRestoreSelection() throws {
        let (project, fixtureID) = projectWithFixture()
        let session = DocumentSession(project: project)
        session.selectFixtures([fixtureID])
        try session.perform(RemovePatchedFixtureCommand(fixtureID: fixtureID))
        XCTAssertTrue(session.selection.snapshot.fixtureIDs.isEmpty)
        try session.undo()
        XCTAssertEqual(session.project.fixtures.count, 1)
        // Selection intentionally not restored.
        XCTAssertTrue(session.selection.snapshot.fixtureIDs.isEmpty)
    }

    func testSelectionManagerPrune() {
        let manager = SelectionManager()
        let gone = UUID()
        manager.selectFixtures([gone])
        let project = ShowProject.empty()
        XCTAssertTrue(manager.prune(against: project))
        XCTAssertTrue(manager.snapshot.fixtureIDs.isEmpty)
    }
}
