import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class DocumentDirtyTests: XCTestCase {
    /// Non-coalescing commands so undo stack matches discrete edits.
    private func addList(_ session: DocumentSession, name: String) throws {
        try session.perform(AddCueListCommand(list: CueList(name: name)))
    }

    func testEditSaveClean() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        XCTAssertFalse(session.isDirty)
        try addList(session, name: "A")
        XCTAssertTrue(session.isDirty)
        session.markSaved()
        XCTAssertFalse(session.isDirty)
    }

    func testEditSaveEditDirty() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A")
        session.markSaved()
        try addList(session, name: "B")
        XCTAssertTrue(session.isDirty)
    }

    func testUndoBackToSavedIsClean() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A")
        session.markSaved()
        try addList(session, name: "B")
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.project.cueLists.count, 2)
        try session.undo()
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.project.cueLists.count, 1)
        XCTAssertEqual(session.project.cueLists[0].name, "A")
    }

    func testRedoAwayFromSavedIsDirty() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A")
        session.markSaved()
        try addList(session, name: "B")
        try session.undo()
        XCTAssertFalse(session.isDirty)
        try session.redo()
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.project.cueLists.count, 2)
    }

    /// P0-1: undo then branch until the same *depth* as the saved path must stay dirty.
    func testBranchAfterUndoDoesNotFalseClean() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A") // depth 1
        try addList(session, name: "B") // depth 2
        try addList(session, name: "C") // depth 3
        session.markSaved()
        XCTAssertFalse(session.isDirty)

        try session.undo() // back to B
        try session.undo() // back to A
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.project.cueLists.map(\.name), ["A"])

        // Branch edits: same stack depth as saved path (3) but different content.
        try addList(session, name: "X") // depth 2 on branch
        try addList(session, name: "Y") // depth 3 on branch
        XCTAssertEqual(session.project.cueLists.count, 3)
        XCTAssertTrue(session.isDirty, "Branch that reuses undo depth must not report clean")
        XCTAssertNotEqual(session.documentGeneration, session.savedGeneration)
    }

    /// P0-1: redo restores the original state ID so save-point stays reachable.
    func testUndoRedoRestoresSavedClean() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A")
        try addList(session, name: "B")
        session.markSaved()
        let savedID = session.documentGeneration

        try session.undo()
        XCTAssertTrue(session.isDirty)
        try session.redo()
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.documentGeneration, savedID)
    }

    /// P0-1: edit then undo back to save is clean.
    func testSaveEditUndoIsClean() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A")
        session.markSaved()
        try addList(session, name: "B")
        try session.undo()
        XCTAssertFalse(session.isDirty)
    }

    /// P0-1: save → edit → undo → branch edit stays dirty.
    func testSaveEditUndoBranchIsDirty() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        try addList(session, name: "A")
        session.markSaved()
        try addList(session, name: "B")
        try session.undo()
        XCTAssertFalse(session.isDirty)
        try addList(session, name: "Branch")
        XCTAssertTrue(session.isDirty)
    }

    /// PRE-UI-5: first mutation inside an open command group marks dirty immediately.
    func testGroupMutationIsDirtyBeforeEndGroup() throws {
        let session = DocumentSession(project: .empty(name: "T"))
        session.markSaved()
        XCTAssertFalse(session.isDirty)
        try session.beginGroup(named: "Batch")
        try addList(session, name: "Inside")
        XCTAssertTrue(session.isDirty, "Open group with mutations must report dirty before endGroup")
        try session.endGroup()
        XCTAssertTrue(session.isDirty)
        session.markSaved()
        XCTAssertFalse(session.isDirty)
    }

    /// P0-1: coalescible renames must not merge across a save-point.
    func testCoalesceDoesNotCrossSaveBoundary() throws {
        let session = DocumentSession(project: .empty(name: "Original"))
        try session.perform(RenameProjectCommand(newName: "BeforeSave"))
        session.markSaved()
        XCTAssertFalse(session.isDirty)

        try session.perform(RenameProjectCommand(newName: "AfterSave"))
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.project.metadata.name, "AfterSave")

        // One undo should return exactly to the saved name (not pre-rename baseline).
        try session.undo()
        XCTAssertEqual(session.project.metadata.name, "BeforeSave")
        XCTAssertFalse(session.isDirty)
        XCTAssertTrue(session.canUndo, "Pre-save rename should remain a separate undo step")
    }

    /// Coalescing still works when not crossing a save-point.
    func testCoalesceStillMergesBeforeSave() throws {
        let session = DocumentSession(project: .empty(name: "A"))
        try session.perform(RenameProjectCommand(newName: "B"))
        try session.perform(RenameProjectCommand(newName: "C"))
        XCTAssertEqual(session.project.metadata.name, "C")
        // Single undo step for coalesced renames.
        try session.undo()
        XCTAssertEqual(session.project.metadata.name, "A")
        XCTAssertFalse(session.canUndo)
    }
}
