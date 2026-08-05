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
@MainActor
final class SongDirector {
    private(set) var songID: UUID?
    private(set) var entryIndex: Int = -1
    /// Always `.manual` until automatic progression is implemented (UI-GATE-6).
    private(set) var progressionMode: SongProgressionMode = .manual

    var statusLine: String {
        guard songID != nil, entryIndex >= 0 else { return "" }
        return "Song entry \(entryIndex + 1)"
    }

    func reset() {
        songID = nil
        entryIndex = -1
        progressionMode = .manual
    }

    func load(song: Song?, project: ShowProject, engine: LightingEngine) {
        songID = song?.id
        entryIndex = -1
        guard let song, !song.entries.isEmpty else { return }
        entryIndex = 0
        applyEntry(song.entries[0], project: project, engine: engine)
    }

    /// Only `.manual` is accepted. `.automatic` is ignored (not yet implemented).
    @discardableResult
    func setProgressionMode(_ mode: SongProgressionMode) -> Bool {
        guard mode == .manual else {
            // Keep truthful: do not flip a control that does nothing.
            progressionMode = .manual
            return false
        }
        progressionMode = .manual
        return true
    }

    func next(project: ShowProject, engine: LightingEngine) {
        guard let song = project.songs.first(where: { $0.id == songID }),
              entryIndex + 1 < song.entries.count
        else { return }
        entryIndex += 1
        applyEntry(song.entries[entryIndex], project: project, engine: engine)
    }

    func previous(project: ShowProject, engine: LightingEngine) {
        guard let song = project.songs.first(where: { $0.id == songID }),
              entryIndex > 0
        else { return }
        entryIndex -= 1
        applyEntry(song.entries[entryIndex], project: project, engine: engine)
    }

    func snapshot(project: ShowProject) -> SongPerformanceSnapshot {
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
