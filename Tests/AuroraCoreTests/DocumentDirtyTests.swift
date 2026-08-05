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
}
