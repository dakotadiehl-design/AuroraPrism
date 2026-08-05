import AuroraEngine
import AuroraModel
import Foundation

/// Orchestrates song entries onto the existing cue playback engine (not a second engine).
@MainActor
final class SongDirector {
    private(set) var songID: UUID?
    private(set) var entryIndex: Int = -1

    var statusLine: String {
        guard songID != nil, entryIndex >= 0 else { return "" }
        return "Song entry \(entryIndex + 1)"
    }

    func load(song: Song?, project: ShowProject, engine: LightingEngine) {
        songID = song?.id
        entryIndex = -1
        guard let song, !song.entries.isEmpty else { return }
        entryIndex = 0
        applyEntry(song.entries[0], project: project, engine: engine)
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
