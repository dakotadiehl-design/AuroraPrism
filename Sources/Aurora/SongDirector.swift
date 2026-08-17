import AuroraEngine
import AuroraModel
import Foundation

/// Progression mode for Song Mode (P1-3 / UI-GATE-6).
///
/// Only **manual** progression is implemented. `.automatic` is retained for Codable /
/// snapshot forward-compat but is rejected by `setProgressionMode` until completion
/// semantics are designed (cue-list follow vs song entry, loops, GO cancel rules).
enum SongProgressionMode: String, Sendable {
    case manual
    /// Not implemented — do not expose as a working UI control.
    case automatic
}

/// Immutable presentation/runtime snapshot for Mac Perform + remote (P1-3).
struct SongPerformanceSnapshot: Equatable, Sendable {
    var songID: UUID?
    var songTitle: String
    var artist: String
    var entryIndex: Int
    var entryCount: Int
    var currentEntryLabel: String
    var nextEntryLabel: String?
    var currentCueListID: UUID?
    var currentCueID: UUID?
    var annotations: [String]
    var progressionMode: SongProgressionMode
    var hasMissingTarget: Bool

    static let empty = SongPerformanceSnapshot(
        songID: nil,
        songTitle: "",
        artist: "",
        entryIndex: -1,
        entryCount: 0,
        currentEntryLabel: "",
        nextEntryLabel: nil,
        currentCueListID: nil,
        currentCueID: nil,
        annotations: [],
        progressionMode: .manual,
        hasMissingTarget: false
    )
}

/// Orchestrates song entries onto the existing cue playback engine (not a second engine).
///
/// **CR-05:** Cursor prefers `currentEntryID` identity; reconcile after document edits.
///
/// Authoritative AME/runtime section cursor is `(songID, sectionID)` — not always
/// `sections.first`. Entry set-list progression remains independent of section cursor.
@MainActor
final class SongDirector {
    private(set) var songID: UUID?
    private(set) var currentEntryID: UUID?
    private(set) var entryIndex: Int = -1
    /// Active song section for AME / show context (ordered by `SongSection.order`).
    private(set) var sectionID: UUID?
    /// Always `.manual` until automatic progression is implemented (UI-GATE-6).
    private(set) var progressionMode: SongProgressionMode = .manual

    var statusLine: String {
        guard songID != nil, entryIndex >= 0 else { return "" }
        return "Song entry \(entryIndex + 1)"
    }

    func reset() {
        songID = nil
        currentEntryID = nil
        entryIndex = -1
        sectionID = nil
        progressionMode = .manual
    }

    func load(song: Song?, project: ShowProject, engine: LightingEngine) {
        guard let song else {
            songID = nil
            currentEntryID = nil
            entryIndex = -1
            sectionID = nil
            return
        }
        songID = song.id
        sectionID = Self.firstSectionID(in: song)
        guard !song.entries.isEmpty else {
            currentEntryID = nil
            entryIndex = -1
            return
        }
        let cursor = SongCursorReconcile.withEntryIndex(0, song: song)
        applyCursor(cursor)
        applyEntry(song.entries[0], project: project, engine: engine)
    }

    /// Set active section within the current song (or locate song owning the section).
    @discardableResult
    func enterSection(sectionID: UUID, project: ShowProject) -> Bool {
        if let songID,
           let song = project.songs.first(where: { $0.id == songID }),
           song.sections.contains(where: { $0.id == sectionID }) {
            self.sectionID = sectionID
            return true
        }
        // Section may live on another song — switch song identity without reloading entries.
        guard let song = project.songs.first(where: { $0.sections.contains(where: { $0.id == sectionID }) }) else {
            return false
        }
        self.songID = song.id
        self.sectionID = sectionID
        return true
    }

    /// Select a song and place the section cursor on its first ordered section.
    @discardableResult
    func selectSong(id: UUID, project: ShowProject, engine: LightingEngine) -> Bool {
        guard let song = project.songs.first(where: { $0.id == id }) else { return false }
        load(song: song, project: project, engine: engine)
        return true
    }

    @discardableResult
    func nextSection(project: ShowProject) -> Bool {
        guard let songID,
              let song = project.songs.first(where: { $0.id == songID })
        else { return false }
        let ordered = song.sections.sorted { $0.order < $1.order }
        guard !ordered.isEmpty else { return false }
        guard let current = sectionID,
              let idx = ordered.firstIndex(where: { $0.id == current }),
              idx + 1 < ordered.count
        else {
            // No current or already last — if no current, jump to first.
            if sectionID == nil, let first = ordered.first {
                sectionID = first.id
                return true
            }
            return false
        }
        sectionID = ordered[idx + 1].id
        return true
    }

    @discardableResult
    func previousSection(project: ShowProject) -> Bool {
        guard let songID,
              let song = project.songs.first(where: { $0.id == songID })
        else { return false }
        let ordered = song.sections.sorted { $0.order < $1.order }
        guard !ordered.isEmpty else { return false }
        guard let current = sectionID,
              let idx = ordered.firstIndex(where: { $0.id == current }),
              idx > 0
        else { return false }
        sectionID = ordered[idx - 1].id
        return true
    }

    /// Active section label for presentation / AME, if resolvable.
    func activeSection(project: ShowProject) -> SongSection? {
        guard let songID,
              let song = project.songs.first(where: { $0.id == songID }),
              let sectionID
        else { return nil }
        return song.sections.first(where: { $0.id == sectionID })
    }

    private static func firstSectionID(in song: Song) -> UUID? {
        song.sections.sorted { $0.order < $1.order }.first?.id
    }

    /// Only `.manual` is accepted. `.automatic` is ignored (not yet implemented).
    @discardableResult
    func setProgressionMode(_ mode: SongProgressionMode) -> Bool {
        guard mode == .manual else {
            progressionMode = .manual
            return false
        }
        progressionMode = .manual
        return true
    }

    func next(project: ShowProject, engine: LightingEngine) {
        reconcile(project: project)
        guard let song = project.songs.first(where: { $0.id == songID }),
              entryIndex + 1 < song.entries.count
        else { return }
        let cursor = SongCursorReconcile.withEntryIndex(entryIndex + 1, song: song)
        applyCursor(cursor)
        applyEntry(song.entries[cursor.entryIndex], project: project, engine: engine)
    }

    func previous(project: ShowProject, engine: LightingEngine) {
        reconcile(project: project)
        guard let song = project.songs.first(where: { $0.id == songID }),
              entryIndex > 0
        else { return }
        let cursor = SongCursorReconcile.withEntryIndex(entryIndex - 1, song: song)
        applyCursor(cursor)
        applyEntry(song.entries[cursor.entryIndex], project: project, engine: engine)
    }

    /// CR-05: re-resolve entry identity after document mutations. Does not fire entries.
    func reconcile(project: ShowProject) {
        let state = SongCursorState(songID: songID, currentEntryID: currentEntryID, entryIndex: entryIndex)
        let next = SongCursorReconcile.reconcile(state, project: project)
        applyCursor(next)
    }

    func snapshot(project: ShowProject) -> SongPerformanceSnapshot {
        reconcile(project: project)
        guard let songID,
              let song = project.songs.first(where: { $0.id == songID })
        else {
            return .empty
        }

        let count = song.entries.count
        let idx = entryIndex
        var currentLabel = ""
        var nextLabel: String?
        var listID: UUID?
        var cueID: UUID?
        var missing = false

        if idx >= 0, idx < count {
            let entry = song.entries[idx]
            currentLabel = entry.label.isEmpty ? defaultLabel(entry, project: project) : entry.label
            let resolved = resolve(entry, project: project)
            listID = resolved.listID
            cueID = resolved.cueID
            missing = resolved.missing
        }
        if idx + 1 < count {
            let next = song.entries[idx + 1]
            nextLabel = next.label.isEmpty ? defaultLabel(next, project: project) : next.label
        }

        let notes = song.annotations.map(\.text)

        return SongPerformanceSnapshot(
            songID: song.id,
            songTitle: song.title,
            artist: song.artist,
            entryIndex: idx,
            entryCount: count,
            currentEntryLabel: currentLabel,
            nextEntryLabel: nextLabel,
            currentCueListID: listID,
            currentCueID: cueID,
            annotations: notes,
            progressionMode: progressionMode,
            hasMissingTarget: missing
        )
    }

    private func applyCursor(_ cursor: SongCursorState) {
        songID = cursor.songID
        currentEntryID = cursor.currentEntryID
        entryIndex = cursor.entryIndex
        // Preserve sectionID when still on the same song; clear if song dropped.
        if songID == nil {
            sectionID = nil
        }
    }

    private func defaultLabel(_ entry: SongEntry, project: ShowProject) -> String {
        switch entry.target {
        case .cueList(let id):
            return project.cueLists.first(where: { $0.id == id })?.name ?? "Cue List"
        case .cue(let listID, let cueID):
            if let list = project.cueLists.first(where: { $0.id == listID }),
               let cue = list.cues.first(where: { $0.id == cueID }) {
                return cue.name.isEmpty ? "Cue \(cue.number)" : cue.name
            }
            return "Cue"
        }
    }

    private func resolve(
        _ entry: SongEntry,
        project: ShowProject
    ) -> (listID: UUID?, cueID: UUID?, missing: Bool) {
        switch entry.target {
        case .cueList(let listID):
            let ok = project.cueLists.contains(where: { $0.id == listID })
            return (listID, nil, !ok)
        case .cue(let listID, let cueID):
            guard let list = project.cueLists.first(where: { $0.id == listID }),
                  list.cues.contains(where: { $0.id == cueID })
            else {
                return (listID, cueID, true)
            }
            return (listID, cueID, false)
        }
    }

    private func applyEntry(_ entry: SongEntry, project: ShowProject, engine: LightingEngine) {
        switch entry.target {
        case .cueList(let listID):
            if let list = project.cueLists.first(where: { $0.id == listID }) {
                engine.loadCueList(list)
            }
        case .cue(let listID, let cueID):
            if let list = project.cueLists.first(where: { $0.id == listID }) {
                engine.loadCueList(list)
                engine.fire(cueID: cueID)
            }
        }
    }
}
