import AuroraCore
import AuroraModel
import Foundation
import XCTest

@MainActor
final class CueBlockCommandTests: XCTestCase {
    func testCueBlockGroupCommandsAndDeleteUnfilesBlocks() throws {
        let group = CueBlockGroup(name: "Dance Floor")
        let block = CueBlock(name: "Blue", type: .color, cueBlockGroupID: group.id)
        let session = DocumentSession(project: ShowProject.empty(name: "Groups"))

        try session.perform(AddCueBlockGroupCommand(group: group))
        try session.perform(AddCueBlockCommand(cueBlock: block))
        XCTAssertEqual(session.project.cueBlocks[0].cueBlockGroupID, group.id)

        try session.perform(RemoveCueBlockGroupCommand(groupID: group.id))
        XCTAssertTrue(session.project.cueBlockGroups.isEmpty)
        XCTAssertNil(session.project.cueBlocks[0].cueBlockGroupID)

        try session.undo()
        XCTAssertEqual(session.project.cueBlockGroups.first?.id, group.id)
        XCTAssertEqual(session.project.cueBlocks[0].cueBlockGroupID, group.id)
    }

    func testMoveCueBlockToGroupUndo() throws {
        let first = CueBlockGroup(name: "First")
        let second = CueBlockGroup(name: "Second")
        let block = CueBlock(name: "75%", type: .intensity, cueBlockGroupID: first.id)
        var project = ShowProject.empty(name: "Move Group")
        project.cueBlockGroups = [first, second]
        project.cueBlocks = [block]
        let session = DocumentSession(project: project)

        try session.perform(MoveCueBlockToGroupCommand(cueBlockID: block.id, destinationGroupID: second.id))
        XCTAssertEqual(session.project.cueBlocks[0].cueBlockGroupID, second.id)
        try session.undo()
        XCTAssertEqual(session.project.cueBlocks[0].cueBlockGroupID, first.id)
    }

    private func makeProjectWithCueAndBlock() -> (ShowProject, UUID, UUID, CueBlock) {
        var project = ShowProject.empty(name: "CB")
        let block = CueBlock(
            name: "Blue",
            type: .color,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: UUID(), attributes: ["colorB": 1])
            ])
        )
        project.cueBlocks = [block]
        let listID = UUID()
        let cueID = UUID()
        project.cueLists = [
            CueList(id: listID, name: "Main", cues: [Cue(id: cueID, number: 1, name: "Q1")])
        ]
        return (project, listID, cueID, block)
    }

    func testAddUpdateRemoveCueBlockUndoRedo() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "X"))
        let block = CueBlock(name: "Dim 75", type: .intensity, levels: CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: UUID(), attributes: ["intensity": 0.75])
        ]))
        try session.perform(AddCueBlockCommand(cueBlock: block))
        XCTAssertEqual(session.project.cueBlocks.count, 1)

        var updated = block
        updated.name = "Dim 50"
        updated.levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: UUID(), attributes: ["intensity": 0.5])
        ])
        try session.perform(UpdateCueBlockCommand(cueBlock: updated))
        XCTAssertEqual(session.project.cueBlocks[0].name, "Dim 50")

        try session.undo()
        XCTAssertEqual(session.project.cueBlocks[0].name, "Dim 75")
        try session.redo()
        XCTAssertEqual(session.project.cueBlocks[0].name, "Dim 50")

        try session.perform(RemoveCueBlockCommand(cueBlockID: block.id))
        XCTAssertTrue(session.project.cueBlocks.isEmpty)
        try session.undo()
        XCTAssertEqual(session.project.cueBlocks.count, 1)
        XCTAssertEqual(session.project.cueBlocks[0].id, block.id)
    }

    func testRemoveRestoresOriginalIndex() throws {
        var project = ShowProject.empty(name: "Idx")
        let a = CueBlock(name: "A", type: .color)
        let b = CueBlock(name: "B", type: .color)
        let c = CueBlock(name: "C", type: .color)
        project.cueBlocks = [a, b, c]
        let session = DocumentSession(project: project)
        try session.perform(RemoveCueBlockCommand(cueBlockID: b.id))
        XCTAssertEqual(session.project.cueBlocks.map(\.name), ["A", "C"])
        try session.undo()
        XCTAssertEqual(session.project.cueBlocks.map(\.name), ["A", "B", "C"])
    }

    func testAddCueBlockRejectsDuplicateID() throws {
        let (project, _, _, block) = makeProjectWithCueAndBlock()
        let session = DocumentSession(project: project)
        XCTAssertThrowsError(try session.perform(AddCueBlockCommand(cueBlock: block)))
    }

    func testReferenceCommandsUndoRedoStableIdentity() throws {
        let (project, listID, cueID, block) = makeProjectWithCueAndBlock()
        let session = DocumentSession(project: project)
        let ref = CueBlockReference(cueBlockID: block.id, enabled: true)
        let add = AddCueBlockReferenceCommand(listID: listID, cueID: cueID, reference: ref)
        try session.perform(add)
        XCTAssertEqual(session.project.cueLists[0].cues[0].cueBlockRefs.first?.id, ref.id)

        try session.undo()
        XCTAssertTrue(session.project.cueLists[0].cues[0].cueBlockRefs.isEmpty)
        try session.redo()
        XCTAssertEqual(session.project.cueLists[0].cues[0].cueBlockRefs.first?.id, ref.id)

        try session.perform(SetCueBlockReferenceEnabledCommand(
            listID: listID, cueID: cueID, referenceID: ref.id, enabled: false
        ))
        XCTAssertEqual(session.project.cueLists[0].cues[0].cueBlockRefs[0].enabled, false)
        try session.undo()
        XCTAssertEqual(session.project.cueLists[0].cues[0].cueBlockRefs[0].enabled, true)
    }

    func testDuplicateReferenceRejected() throws {
        let (project, listID, cueID, block) = makeProjectWithCueAndBlock()
        let session = DocumentSession(project: project)
        try session.perform(AddCueBlockReferenceCommand(listID: listID, cueID: cueID, cueBlockID: block.id))
        XCTAssertThrowsError(
            try session.perform(AddCueBlockReferenceCommand(listID: listID, cueID: cueID, cueBlockID: block.id))
        )
    }

    func testMoveReferenceClampsAndUndoes() throws {
        var project = ShowProject.empty(name: "Move")
        let b1 = CueBlock(name: "1", type: .color)
        let b2 = CueBlock(name: "2", type: .color)
        let b3 = CueBlock(name: "3", type: .color)
        project.cueBlocks = [b1, b2, b3]
        let listID = UUID()
        let cueID = UUID()
        let r1 = CueBlockReference(cueBlockID: b1.id)
        let r2 = CueBlockReference(cueBlockID: b2.id)
        let r3 = CueBlockReference(cueBlockID: b3.id)
        project.cueLists = [
            CueList(id: listID, name: "M", cues: [
                Cue(id: cueID, number: 1, cueBlockRefs: [r1, r2, r3])
            ])
        ]
        let session = DocumentSession(project: project)
        try session.perform(MoveCueBlockReferenceCommand(
            listID: listID, cueID: cueID, referenceID: r1.id, toIndex: 2
        ))
        XCTAssertEqual(
            session.project.cueLists[0].cues[0].cueBlockRefs.map(\.id),
            [r2.id, r3.id, r1.id]
        )
        try session.undo()
        XCTAssertEqual(
            session.project.cueLists[0].cues[0].cueBlockRefs.map(\.id),
            [r1.id, r2.id, r3.id]
        )
    }

    func testDuplicateCueRemapsReferenceIDsStableAcrossRedo() throws {
        var project = ShowProject.empty(name: "Dup")
        let block = CueBlock(name: "B", type: .intensity, levels: CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: UUID(), attributes: ["intensity": 0.5])
        ]))
        project.cueBlocks = [block]
        let listID = UUID()
        let sourceID = UUID()
        let ref = CueBlockReference(cueBlockID: block.id, enabled: true)
        project.cueLists = [
            CueList(id: listID, name: "M", cues: [
                Cue(id: sourceID, number: 1, name: "Source", cueBlockRefs: [ref])
            ])
        ]
        let session = DocumentSession(project: project)
        let cmd = DuplicateCueCommand(listID: listID, sourceCueID: sourceID)
        try session.perform(cmd)
        let firstDupID = cmd.duplicatedCueID
        let firstRefID = session.project.cueLists[0].cues[1].cueBlockRefs.first?.id
        XCTAssertNotNil(firstDupID)
        XCTAssertNotEqual(firstRefID, ref.id)
        XCTAssertEqual(session.project.cueLists[0].cues[1].cueBlockRefs.first?.cueBlockID, block.id)

        try session.undo()
        XCTAssertEqual(session.project.cueLists[0].cues.count, 1)
        try session.redo()
        XCTAssertEqual(session.project.cueLists[0].cues[1].id, firstDupID)
        XCTAssertEqual(session.project.cueLists[0].cues[1].cueBlockRefs.first?.id, firstRefID)
    }

    func testAddReferenceRejectsMissingBlock() throws {
        let (project, listID, cueID, _) = makeProjectWithCueAndBlock()
        let session = DocumentSession(project: project)
        XCTAssertThrowsError(
            try session.perform(AddCueBlockReferenceCommand(
                listID: listID, cueID: cueID, cueBlockID: UUID()
            ))
        )
    }

    func testRemoveBlockLeavesCueReferences() throws {
        let (project, listID, cueID, block) = makeProjectWithCueAndBlock()
        let session = DocumentSession(project: project)
        try session.perform(AddCueBlockReferenceCommand(listID: listID, cueID: cueID, cueBlockID: block.id))
        try session.perform(RemoveCueBlockCommand(cueBlockID: block.id))
        XCTAssertTrue(session.project.cueBlocks.isEmpty)
        XCTAssertEqual(session.project.cueLists[0].cues[0].cueBlockRefs.first?.cueBlockID, block.id)
    }
}
