import AuroraModel
import XCTest

final class SongCursorReconcileTests: XCTestCase {
    private func song(entries: [SongEntry]) -> Song {
        Song(id: UUID(uuidString: "C1000000-0000-4000-8000-000000000001")!, title: "S", entries: entries)
    }

    private func entry(_ label: String, idSuffix: String) -> SongEntry {
        SongEntry(
            id: UUID(uuidString: "C1000000-0000-4000-8000-0000000001\(idSuffix)")!,
            target: .cueList(UUID()),
            label: label
        )
    }

    func testReorderPreservesEntryIdentity() {
        let e0 = entry("Intro", idSuffix: "01")
        let e1 = entry("Verse", idSuffix: "02")
        let e2 = entry("Chorus", idSuffix: "03")
        var s = song(entries: [e0, e1, e2])
        var project = ShowProject.empty(name: "P")
        project.songs = [s]

        var state = SongCursorReconcile.withEntryIndex(1, song: s) // Verse
        XCTAssertEqual(state.currentEntryID, e1.id)

        // Reorder: Verse moves to index 0
        s.entries = [e1, e0, e2]
        project.songs = [s]
        state = SongCursorReconcile.reconcile(state, project: project)
        XCTAssertEqual(state.currentEntryID, e1.id)
        XCTAssertEqual(state.entryIndex, 0)
    }

    func testRemoveEntryBeforeCurrentPreservesIdentity() {
        let e0 = entry("Intro", idSuffix: "01")
        let e1 = entry("Verse", idSuffix: "02")
        let e2 = entry("Chorus", idSuffix: "03")
        var s = song(entries: [e0, e1, e2])
        var project = ShowProject.empty(name: "P")
        project.songs = [s]
        var state = SongCursorReconcile.withEntryIndex(2, song: s)

        s.entries = [e0, e2] // remove Verse
        project.songs = [s]
        state = SongCursorReconcile.reconcile(state, project: project)
        XCTAssertEqual(state.currentEntryID, e2.id)
        XCTAssertEqual(state.entryIndex, 1)
    }

    func testRemoveCurrentFallsBackToClampedIndex() {
        let e0 = entry("Intro", idSuffix: "01")
        let e1 = entry("Verse", idSuffix: "02")
        let e2 = entry("Chorus", idSuffix: "03")
        var s = song(entries: [e0, e1, e2])
        var project = ShowProject.empty(name: "P")
        project.songs = [s]
        var state = SongCursorReconcile.withEntryIndex(1, song: s)

        s.entries = [e0, e2]
        project.songs = [s]
        state = SongCursorReconcile.reconcile(state, project: project)
        XCTAssertEqual(state.entryIndex, 1)
        XCTAssertEqual(state.currentEntryID, e2.id)
    }

    func testDeleteSongResets() {
        let e0 = entry("Intro", idSuffix: "01")
        let s = song(entries: [e0])
        var project = ShowProject.empty(name: "P")
        project.songs = [s]
        var state = SongCursorReconcile.withEntryIndex(0, song: s)
        project.songs = []
        state = SongCursorReconcile.reconcile(state, project: project)
        XCTAssertEqual(state, .empty)
    }

    func testEmptyEntries() {
        let s = song(entries: [])
        var project = ShowProject.empty(name: "P")
        project.songs = [s]
        let state = SongCursorReconcile.reconcile(
            SongCursorState(songID: s.id, currentEntryID: UUID(), entryIndex: 0),
            project: project
        )
        XCTAssertEqual(state.songID, s.id)
        XCTAssertNil(state.currentEntryID)
        XCTAssertEqual(state.entryIndex, -1)
    }
}
