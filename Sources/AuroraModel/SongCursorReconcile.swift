import Foundation

/// Pure song cursor reconciliation (CR-05). Prefer entry identity over bare index.
public struct SongCursorState: Equatable, Sendable {
    public var songID: UUID?
    public var currentEntryID: UUID?
    /// Derived index for UI; -1 when no current entry.
    public var entryIndex: Int

    public init(songID: UUID? = nil, currentEntryID: UUID? = nil, entryIndex: Int = -1) {
        self.songID = songID
        self.currentEntryID = currentEntryID
        self.entryIndex = entryIndex
    }

    public static let empty = SongCursorState()
}

public enum SongCursorReconcile {
    /// Reconcile cursor against current project. Does not auto-fire entries.
    ///
    /// - If `currentEntryID` still exists: follow it (index may shift after reorder).
    /// - If entry deleted: clamp to previous index or last remaining; clear if empty.
    /// - If song deleted: reset to empty (engine look preserved by caller).
    public static func reconcile(_ state: SongCursorState, project: ShowProject) -> SongCursorState {
        guard let songID = state.songID,
              let song = project.songs.first(where: { $0.id == songID })
        else {
            return .empty
        }

        if song.entries.isEmpty {
            return SongCursorState(songID: songID, currentEntryID: nil, entryIndex: -1)
        }

        if let entryID = state.currentEntryID,
           let idx = song.entries.firstIndex(where: { $0.id == entryID }) {
            return SongCursorState(songID: songID, currentEntryID: entryID, entryIndex: idx)
        }

        // Current entry missing — documented fallback: clamp prior index.
        let fallbackIndex: Int
        if state.entryIndex < 0 {
            fallbackIndex = 0
        } else {
            fallbackIndex = min(state.entryIndex, song.entries.count - 1)
        }
        let entry = song.entries[fallbackIndex]
        return SongCursorState(songID: songID, currentEntryID: entry.id, entryIndex: fallbackIndex)
    }

    /// After load or next/previous: set identity from index.
    public static func withEntryIndex(_ index: Int, song: Song) -> SongCursorState {
        guard !song.entries.isEmpty else {
            return SongCursorState(songID: song.id, currentEntryID: nil, entryIndex: -1)
        }
        let idx = min(max(0, index), song.entries.count - 1)
        return SongCursorState(
            songID: song.id,
            currentEntryID: song.entries[idx].id,
            entryIndex: idx
        )
    }
}
