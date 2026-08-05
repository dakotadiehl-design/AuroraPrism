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

    func testUpdatePresetUndoRedo() throws {
        var project = ShowProject.empty(name: "Presets")
        let preset = Preset(name: "Look A", notes: "orig")
        project.presets = [preset]
        let session = DocumentSession(project: project)

        var updated = preset
        updated.name = "Look B"
        updated.notes = "edited"
        try session.perform(UpdatePresetCommand(preset: updated))
        XCTAssertEqual(session.project.presets[0].name, "Look B")
        XCTAssertEqual(session.project.presets[0].notes, "edited")

        try session.undo()
        XCTAssertEqual(session.project.presets[0].name, "Look A")
        XCTAssertEqual(session.project.presets[0].notes, "orig")

        try session.redo()
        XCTAssertEqual(session.project.presets[0].name, "Look B")
    }

    func testAddRemovePaletteUndo() throws {
        let session = DocumentSession(project: ShowProject.empty(name: "P"))
        let palette = Palette(name: "Warm", type: .color, values: ["colorR": 1])
        try session.perform(AddPaletteCommand(palette: palette))
        XCTAssertEqual(session.project.palettes.count, 1)
        try session.perform(RemovePaletteCommand(paletteID: palette.id))
        XCTAssertTrue(session.project.palettes.isEmpty)
        try session.undo()
        XCTAssertEqual(session.project.palettes.count, 1)
        XCTAssertEqual(session.project.palettes[0].id, palette.id)
    }

    /// CR-06: undo restore original collection order.
    func testRemovePaletteRestoresIndex() throws {
        var project = ShowProject.empty(name: "P")
        let a = Palette(name: "A", type: .color, values: ["colorR": 1])
        let b = Palette(name: "B", type: .color, values: ["colorR": 0.5])
        let c = Palette(name: "C", type: .color, values: ["colorR": 0])
        project.palettes = [a, b, c]
        let session = DocumentSession(project: project)
        try session.perform(RemovePaletteCommand(paletteID: b.id))
        XCTAssertEqual(session.project.palettes.map(\.name), ["A", "C"])
        try session.undo()
        XCTAssertEqual(session.project.palettes.map(\.name), ["A", "B", "C"])
    }

    func testRemoveSongRestoresIndex() throws {
        var project = ShowProject.empty(name: "S")
        let a = Song(title: "A")
        let b = Song(title: "B")
        let c = Song(title: "C")
        project.songs = [a, b, c]
        let session = DocumentSession(project: project)
        try session.perform(RemoveSongCommand(songID: b.id))
        XCTAssertEqual(session.project.songs.map(\.title), ["A", "C"])
        try session.undo()
        XCTAssertEqual(session.project.songs.map(\.title), ["A", "B", "C"])
    }

    func testUpdateUniverseRoutingUndo() throws {
        var project = ShowProject.empty(name: "Route")
        let u = Universe(number: 1, name: "Main", protocolHint: .none)
        project.universes = [u]
        let session = DocumentSession(project: project)
        try session.perform(
            UpdateUniverseRoutingCommand(universeID: u.id, protocolHint: .local)
        )
        XCTAssertEqual(session.project.universes[0].protocolHint, .local)
        try session.undo()
        XCTAssertEqual(session.project.universes[0].protocolHint, .none)
        try session.redo()
        XCTAssertEqual(session.project.universes[0].protocolHint, .local)
    }

    func testRecordRefGroupIsOneUndo() throws {
        var project = ShowProject.empty(name: "Cues")
        let fx = UUID()
        let list = CueList(
            name: "Main",
            cues: [
                Cue(number: 1, name: "Q1"),
                Cue(number: 2, name: "Q2"),
            ]
        )
        project.cueLists = [list]
        let palette = Palette(name: "Warm", type: .color, values: ["colorR": 1])
        project.palettes = [palette]
        let session = DocumentSession(project: project)

        try session.beginGroup(named: "Record Palette Reference")
        for cue in list.cues {
            var updated = cue
            updated.recordPaletteRef(palette: palette, fixtureIDs: [fx])
            try session.perform(UpdateCueCommand(listID: list.id, cue: updated))
        }
        try session.endGroup()
        XCTAssertEqual(
            session.project.cueLists[0].cues[0].levels.fixtures.first?.paletteRefs["color"],
            palette.id
        )
        XCTAssertEqual(
            session.project.cueLists[0].cues[1].levels.fixtures.first?.paletteRefs["color"],
            palette.id
        )
        try session.undo()
        XCTAssertTrue(session.project.cueLists[0].cues[0].levels.fixtures.isEmpty
            || session.project.cueLists[0].cues[0].levels.fixtures.first?.paletteRefs.isEmpty == true)
        XCTAssertTrue(session.project.cueLists[0].cues[1].levels.fixtures.isEmpty
            || session.project.cueLists[0].cues[1].levels.fixtures.first?.paletteRefs.isEmpty == true)
    }

    func testRemoveCueListUndo() throws {
        var project = ShowProject.empty(name: "Cues")
        let list = CueList(name: "Main", cues: [Cue(number: 1, name: "Q1")])
        project.cueLists = [list]
        let session = DocumentSession(project: project)
        try session.perform(RemoveCueListCommand(listID: list.id))
        XCTAssertTrue(session.project.cueLists.isEmpty)
        try session.undo()
        XCTAssertEqual(session.project.cueLists.count, 1)
        XCTAssertEqual(session.project.cueLists[0].id, list.id)
        XCTAssertEqual(session.project.cueLists[0].cues.count, 1)
    }

    func testUpdateSongEntriesUndo() throws {
        var project = ShowProject.empty(name: "Songs")
        let listID = UUID()
        project.cueLists = [CueList(id: listID, name: "Main", cues: [Cue(number: 1, name: "Q1")])]
        let song = Song(title: "S1", entries: [
            SongEntry(target: .cueList(listID), label: "Open")
        ])
        project.songs = [song]
        let session = DocumentSession(project: project)

        var updated = song
        updated.entries.append(SongEntry(target: .cueList(listID), label: "Close"))
        updated.title = "S1b"
        try session.perform(UpdateSongCommand(song: updated))
        XCTAssertEqual(session.project.songs[0].entries.count, 2)
        XCTAssertEqual(session.project.songs[0].title, "S1b")
        try session.undo()
        XCTAssertEqual(session.project.songs[0].entries.count, 1)
        XCTAssertEqual(session.project.songs[0].title, "S1")
    }

    func testUpdateCueLevelsUndoPreservesTiming() throws {
        var project = ShowProject.empty(name: "Cues")
        let fx = UUID()
        var cue = Cue(number: 1, name: "Q1", fadeIn: 2.5, delay: 0.5)
        cue.levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 0.2])
        ])
        let list = CueList(name: "Main", cues: [cue])
        project.cueLists = [list]
        let session = DocumentSession(project: project)

        var updated = cue
        updated.levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fx, attributes: ["intensity": 1.0])
        ])
        try session.perform(UpdateCueCommand(listID: list.id, cue: updated))
        XCTAssertEqual(
            session.project.cueLists[0].cues[0].levels.fixtures[0].attributes["intensity"],
            1.0
        )
        XCTAssertEqual(session.project.cueLists[0].cues[0].fadeIn, 2.5)
        XCTAssertEqual(session.project.cueLists[0].cues[0].delay, 0.5)

        try session.undo()
        XCTAssertEqual(
            session.project.cueLists[0].cues[0].levels.fixtures[0].attributes["intensity"],
            0.2
        )
        XCTAssertEqual(session.project.cueLists[0].cues[0].fadeIn, 2.5)
    }
}
