import AuroraModel
import AuroraOutput
import XCTest
@testable import Aurora

@MainActor
final class ShowControlRemoteBoundaryTests: XCTestCase {
    func testRemoteTransportUsesAuthoritativeRouterAndRevisions() {
        let fixture = makeController()
        let controller = fixture.controller
        let origin = remoteOrigin(commandID: "transport")

        XCTAssertEqual(controller.executeRemoteBack(origin: origin), .noPreviousCue)
        XCTAssertEqual(controller.stateRevision, 0)

        XCTAssertEqual(controller.executeRemoteGo(origin: origin), .executed)
        XCTAssertEqual(controller.engine.playback.snapshot().cueID, fixture.cues[0].id)
        XCTAssertEqual(controller.stateRevision, 1)
        XCTAssertEqual(controller.controlRouter.controlOriginSnapshot(), origin)

        XCTAssertFalse(controller.back())
        XCTAssertEqual(controller.engine.playback.snapshot().cueID, fixture.cues[0].id)
        XCTAssertEqual(controller.stateRevision, 1)

        XCTAssertEqual(controller.executeRemoteGo(origin: origin), .executed)
        XCTAssertEqual(controller.engine.playback.snapshot().cueID, fixture.cues[1].id)
        XCTAssertEqual(controller.stateRevision, 2)

        XCTAssertEqual(controller.executeRemoteGo(origin: origin), .noNextCue)
        XCTAssertEqual(controller.stateRevision, 2)

        XCTAssertEqual(controller.executeRemoteBack(origin: origin), .executed)
        XCTAssertEqual(controller.engine.playback.snapshot().cueID, fixture.cues[0].id)
        XCTAssertEqual(controller.stateRevision, 3)

        XCTAssertEqual(controller.executeRemoteStop(origin: origin), .executed)
        XCTAssertEqual(controller.executeRemoteStop(origin: origin), .unchanged)
        XCTAssertEqual(controller.stateRevision, 4)
    }

    func testRemoteGrandMasterValidatesAndCommitsOnlyChanges() {
        let controller = makeController().controller
        let origin = remoteOrigin(commandID: "grand-master")

        XCTAssertEqual(controller.executeRemoteGrandMaster(value: .nan, origin: origin), .invalidValue)
        XCTAssertEqual(controller.executeRemoteGrandMaster(value: 1.1, origin: origin), .invalidValue)
        XCTAssertEqual(controller.engine.globalShowControl.masterIntensity, 1)
        XCTAssertEqual(controller.stateRevision, 0)

        XCTAssertEqual(controller.executeRemoteGrandMaster(value: 0.4, origin: origin), .executed)
        XCTAssertEqual(controller.engine.globalShowControl.masterIntensity, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(controller.stateRevision, 1)
        XCTAssertEqual(controller.controlRouter.controlOriginSnapshot(), origin)

        XCTAssertEqual(controller.executeRemoteGrandMaster(value: 0.4, origin: origin), .unchanged)
        XCTAssertEqual(controller.stateRevision, 1)
    }

    func testLocalAndRemoteBlackoutShareExplicitStatePath() {
        let controller = makeController().controller
        let origin = remoteOrigin(commandID: "blackout")

        XCTAssertEqual(controller.executeRemoteBlackout(enabled: true, origin: origin), .executed)
        XCTAssertTrue(controller.engine.globalShowControl.blackout)
        XCTAssertEqual(controller.stateRevision, 1)
        XCTAssertEqual(controller.executeRemoteBlackout(enabled: true, origin: origin), .unchanged)
        XCTAssertEqual(controller.stateRevision, 1)

        XCTAssertTrue(controller.toggleBlackout())
        XCTAssertFalse(controller.engine.globalShowControl.blackout)
        XCTAssertEqual(controller.stateRevision, 2)
        XCTAssertEqual(controller.controlRouter.controlOriginSnapshot(), .localUI)
    }

    func testRemoteSongSelectionUsesHostActionPathAndRejectsUnknownTarget() {
        let fixture = makeController()
        let controller = fixture.controller
        let origin = remoteOrigin(commandID: "select-song")

        XCTAssertEqual(
            controller.executeRemoteSongSelection(id: UUID(), origin: origin),
            .invalidTarget
        )
        XCTAssertEqual(controller.stateRevision, 0)

        XCTAssertEqual(
            controller.executeRemoteSongSelection(id: fixture.song.id, origin: origin),
            .executed
        )
        XCTAssertEqual(controller.songDirector.songID, fixture.song.id)
        XCTAssertEqual(controller.stateRevision, 1)
        XCTAssertEqual(controller.controlRouter.controlOriginSnapshot(), origin)

        XCTAssertEqual(controller.executeRemoteGo(origin: origin), .executed)
        let selectedCueID = controller.engine.playback.snapshot().cueID
        XCTAssertEqual(
            controller.executeRemoteSongSelection(id: fixture.song.id, origin: origin),
            .unchanged
        )
        XCTAssertEqual(controller.engine.playback.snapshot().cueID, selectedCueID)
        XCTAssertEqual(controller.stateRevision, 2)
    }

    func testLocalSongAndSectionNavigationCommitAdvertisedState() {
        let cues = [Cue(number: 1, name: "One")]
        let list = CueList(name: "Main", cues: cues)
        let sections = [
            SongSection(name: "Verse", order: 0),
            SongSection(name: "Chorus", order: 1),
        ]
        let song = Song(
            title: "Navigation Song",
            entries: [SongEntry(target: .cueList(list.id))],
            sections: sections
        )
        var project = ShowProject.empty()
        project.cueLists = [list]
        project.songs = [song]

        let controller = ShowControlController(output: OutputManager())
        controller.reloadFromProject(project, orderedSelection: [])
        controller.loadSong(song, project: project)
        XCTAssertEqual(controller.stateRevision, 1)
        XCTAssertEqual(controller.racpStateSnapshot().song.songID, song.id)

        controller.sectionNext(project: project)
        XCTAssertEqual(controller.stateRevision, 2)
        XCTAssertEqual(controller.songDirector.sectionID, sections[1].id)

        controller.resetSong()
        XCTAssertEqual(controller.stateRevision, 3)
        XCTAssertNil(controller.racpStateSnapshot().song.songID)
    }

    func testGenericControlSurfaceActionsReconcileAdvertisedState() {
        let fixture = makeController()
        let controller = fixture.controller

        controller.perform(
            action: .go,
            project: fixture.project,
            orderedSelection: []
        )
        XCTAssertEqual(controller.stateRevision, 1)
        XCTAssertEqual(controller.engine.playback.snapshot().cueID, fixture.cues[0].id)

        controller.perform(
            action: .masterIntensity,
            project: fixture.project,
            orderedSelection: [],
            midiValue: 32
        )
        XCTAssertEqual(controller.stateRevision, 2)
        XCTAssertEqual(
            controller.racpStateSnapshot().grandMaster,
            Double(32) / 127,
            accuracy: 0.000_001
        )
    }

    private func makeController() -> (
        controller: ShowControlController,
        cues: [Cue],
        song: Song,
        project: ShowProject
    ) {
        let cues = [
            Cue(number: 1, name: "One"),
            Cue(number: 2, name: "Two"),
        ]
        let list = CueList(name: "Main", cues: cues)
        let song = Song(
            title: "Boundary Song",
            entries: [SongEntry(target: .cueList(list.id))]
        )
        var project = ShowProject.empty()
        project.cueLists = [list]
        project.songs = [song]

        let controller = ShowControlController(output: OutputManager())
        controller.reloadFromProject(project, orderedSelection: [])
        return (controller, cues, song, project)
    }

    private func remoteOrigin(commandID: String) -> ControlActionOrigin {
        ControlActionOrigin(
            sourceType: .remote,
            nodeID: "remote-node",
            sessionID: "session",
            commandID: commandID
        )
    }
}
