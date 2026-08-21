import AuroraEngine
import AuroraModel
import XCTest

final class PerformanceCuePresentationTests: XCTestCase {
    private func projectWithCues() -> (ShowProject, UUID, UUID, UUID, UUID) {
        let listA = UUID(uuidString: "B1000000-0000-4000-8000-0000000000A1")!
        let listB = UUID(uuidString: "B1000000-0000-4000-8000-0000000000B1")!
        let cueA0 = UUID(uuidString: "B1000000-0000-4000-8000-0000000000C1")!
        let cueA1 = UUID(uuidString: "B1000000-0000-4000-8000-0000000000C2")!
        let cueA2 = UUID(uuidString: "B1000000-0000-4000-8000-0000000000C3")!
        let cueB0 = UUID(uuidString: "B1000000-0000-4000-8000-0000000000D1")!
        let songID = UUID(uuidString: "B1000000-0000-4000-8000-0000000000E1")!

        var project = ShowProject.empty(name: "CueResolve")
        project.cueLists = [
            CueList(id: listA, name: "Main", cues: [
                Cue(id: cueA0, number: Decimal(string: "1.0")!, name: "House"),
                Cue(id: cueA1, number: Decimal(string: "1.5")!, name: "Intro"),
                Cue(id: cueA2, number: Decimal(string: "10.1")!, name: "Chorus"),
            ]),
            CueList(id: listB, name: "Alt", cues: [
                Cue(id: cueB0, number: Decimal(string: "1.0")!, name: "Alt One"),
            ]),
        ]
        project.songs = [
            Song(
                id: songID,
                title: "Set",
                entries: [
                    SongEntry(target: .cue(listId: listA, cueId: cueA0), label: "Intro"),
                    // Non-adjacent target (skip 1.5)
                    SongEntry(target: .cue(listId: listA, cueId: cueA2), label: "Chorus"),
                    // Different list
                    SongEntry(target: .cue(listId: listB, cueId: cueB0), label: "Alt"),
                ]
            )
        ]
        return (project, listA, cueA0, cueA2, songID)
    }

    func testCurrentUsesCueNumberNotIndexPlusOne() {
        let (project, listA, cueA0, _, _) = projectWithCues()
        let playback = PlaybackSnapshot(
            listID: listA,
            cueIndex: 1,
            cueID: project.cueLists[0].cues[1].id,
            phase: .active,
            cueName: "Intro"
        )
        let (current, _) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: .empty
        )
        XCTAssertEqual(current.number, Decimal(string: "1.5"))
        XCTAssertEqual(current.name, "Intro")
        XCTAssertNotEqual(current.numberDisplay, "2") // not index+1
        XCTAssertEqual(current.cueID, project.cueLists[0].cues[1].id)
        _ = cueA0
    }

    func testSequentialNextInSameList() {
        let (project, listA, _, _, _) = projectWithCues()
        let playback = PlaybackSnapshot(
            listID: listA,
            cueIndex: 0,
            cueID: project.cueLists[0].cues[0].id,
            phase: .active,
            cueName: "House"
        )
        let (_, next) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: .empty
        )
        XCTAssertEqual(next.number, Decimal(string: "1.5"))
        XCTAssertEqual(next.name, "Intro")
    }

    func testLoadedIdleListPublishesFirstCueAsNext() {
        let (project, listA, cueA0, _, _) = projectWithCues()
        let playback = PlaybackSnapshot(
            listID: listA,
            cueIndex: -1,
            cueID: nil,
            phase: .idle,
            cueName: ""
        )
        let (current, next) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: .empty
        )
        XCTAssertNil(current.cueID)
        XCTAssertEqual(next.cueID, cueA0)
        XCTAssertEqual(next.name, "House")
        XCTAssertEqual(next.listID, listA)
    }

    func testSongNextNonAdjacentCue() {
        let (project, listA, cueA0, cueA2, songID) = projectWithCues()
        let playback = PlaybackSnapshot(
            listID: listA,
            cueIndex: 0,
            cueID: cueA0,
            phase: .active,
            cueName: "House"
        )
        let song = SongCueResolveContext(
            songID: songID,
            entryIndex: 0,
            entryCount: 3,
            currentEntryLabel: "Intro",
            nextEntryLabel: "Chorus"
        )
        let (_, next) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: song
        )
        XCTAssertEqual(next.cueID, cueA2)
        XCTAssertEqual(next.number, Decimal(string: "10.1"))
        XCTAssertEqual(next.name, "Chorus")
        XCTAssertEqual(next.sectionLabel, "Chorus")
    }

    func testSongNextDifferentList() {
        let (project, listA, _, _, songID) = projectWithCues()
        let playback = PlaybackSnapshot(
            listID: listA,
            cueIndex: 2,
            cueID: project.cueLists[0].cues[2].id,
            phase: .active,
            cueName: "Chorus"
        )
        let song = SongCueResolveContext(
            songID: songID,
            entryIndex: 1,
            entryCount: 3,
            currentEntryLabel: "Chorus",
            nextEntryLabel: "Alt"
        )
        let (_, next) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: song
        )
        XCTAssertEqual(next.listID, project.cueLists[1].id)
        XCTAssertEqual(next.name, "Alt One")
        XCTAssertEqual(next.sectionLabel, "Alt")
    }

    func testIsCurrentCueRequiresListIdentity() {
        let listA = UUID()
        let listB = UUID()
        let cue = UUID()
        // Same index, wrong list → not current
        XCTAssertFalse(
            PerformanceCuePresentation.isCurrentCue(
                inspectedCueID: cue,
                inspectedListID: listB,
                playbackCueID: nil,
                playbackListID: listA,
                playbackCueIndex: 3,
                cueIndexInList: 3
            )
        )
        // Matching list + index → current
        XCTAssertTrue(
            PerformanceCuePresentation.isCurrentCue(
                inspectedCueID: cue,
                inspectedListID: listA,
                playbackCueID: nil,
                playbackListID: listA,
                playbackCueIndex: 3,
                cueIndexInList: 3
            )
        )
        // Prefer cue ID when available
        XCTAssertTrue(
            PerformanceCuePresentation.isCurrentCue(
                inspectedCueID: cue,
                inspectedListID: listB,
                playbackCueID: cue,
                playbackListID: listA,
                playbackCueIndex: 0,
                cueIndexInList: 9
            )
        )
    }

    /// G2: stale list ID must not resolve CURRENT from an unrelated first list.
    func testStaleListIDDoesNotUseUnrelatedFirstList() {
        let (project, listA, _, _, _) = projectWithCues()
        let missingList = UUID()
        let playback = PlaybackSnapshot(
            listID: missingList,
            cueIndex: 2,
            cueID: nil,
            phase: .active,
            cueName: ""
        )
        let (current, _) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: .empty
        )
        XCTAssertEqual(current, .empty)
        XCTAssertNotEqual(current.listID, listA)
        XCTAssertNotEqual(current.name, "Chorus")
    }

    func testCueIDPreferredOverWrongIndex() {
        let (project, listA, cueA0, cueA2, _) = projectWithCues()
        // Index points at 0, but cueID is non-adjacent chorus
        let playback = PlaybackSnapshot(
            listID: listA,
            cueIndex: 0,
            cueID: cueA2,
            phase: .active,
            cueName: "wrong"
        )
        let (current, _) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: playback,
            song: .empty
        )
        XCTAssertEqual(current.cueID, cueA2)
        XCTAssertEqual(current.number, Decimal(string: "10.1"))
        XCTAssertEqual(current.name, "Chorus")
        _ = cueA0
    }
}
