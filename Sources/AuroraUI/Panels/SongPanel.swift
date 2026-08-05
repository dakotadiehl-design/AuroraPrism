import AuroraCore
import AuroraModel
import SwiftUI

public struct SongPanel: View {
    public var context: WorkspacePanelContext
    public var entryIndex: Int
    public var onLoadSong: (Song) -> Void
    public var onNext: () -> Void
    public var onPrevious: () -> Void
    public var onChanged: () -> Void

    @State private var selectedSongID: UUID?

    public init(
        context: WorkspacePanelContext,
        entryIndex: Int = -1,
        onLoadSong: @escaping (Song) -> Void = { _ in },
        onNext: @escaping () -> Void = {},
        onPrevious: @escaping () -> Void = {},
        onChanged: @escaping () -> Void = {}
    ) {
        self.context = context
        self.entryIndex = entryIndex
        self.onLoadSong = onLoadSong
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onChanged = onChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Songs").font(.headline)
                Spacer()
                Button("New Song") { addSong() }
            }
            HStack {
                Button("Previous Entry") { onPrevious() }
                Button("Next Entry") { onNext() }
                if entryIndex >= 0 {
                    Text("Entry \(entryIndex + 1)")
                        .font(.caption.monospaced())
                }
            }
            List(context.project.songs) { song in
                VStack(alignment: .leading) {
                    HStack {
                        Text(song.title).font(.body.weight(.semibold))
                        Spacer()
                        Button("Load") { onLoadSong(song) }
                        Button("Delete", role: .destructive) {
                            try? context.session.perform(RemoveSongCommand(songID: song.id))
                            onChanged()
                        }
                    }
                    Text("\(song.artist) · \(song.entries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(song.entries.enumerated()), id: \.element.id) { idx, entry in
                        Text("\(idx + 1). \(entry.label.isEmpty ? entryTargetLabel(entry) : entry.label)")
                            .font(.caption2)
                            .foregroundStyle(idx == entryIndex ? Color.accentColor : .secondary)
                    }
                }
            }
        }
        .padding(8)
    }

    private func entryTargetLabel(_ entry: SongEntry) -> String {
        switch entry.target {
        case .cueList(let id): return "List \(id.uuidString.prefix(8))"
        case .cue(_, let cueID): return "Cue \(cueID.uuidString.prefix(8))"
        }
    }

    private func addSong() {
        var song = Song(title: "Song \(context.project.songs.count + 1)")
        if let list = context.project.cueLists.first {
            song.entries = [
                SongEntry(target: .cueList(list.id), label: list.name)
            ]
        }
        try? context.session.perform(AddSongCommand(song: song))
        onChanged()
    }
}
