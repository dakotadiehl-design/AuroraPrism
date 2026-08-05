import AuroraCore
import AuroraModel
import SwiftUI

/// Song / set-list editor (UI-06). Orchestrates via SongDirector — not a second playback engine.
///
/// **A5:** Song entry navigation is secondary to cue transport (GO). Labels make that explicit.
public struct SongPanel: View {
    public var context: WorkspacePanelContext
    public var entryIndex: Int
    public var loadedSongID: UUID?
    public var onLoadSong: (Song) -> Void
    public var onNext: () -> Void
    public var onPrevious: () -> Void
    public var onChanged: () -> Void
    public var onInspectSong: (UUID) -> Void

    @State private var selectedSongID: UUID?
    @State private var statusText: String?
    @State private var showDeleteSongConfirm = false

    public init(
        context: WorkspacePanelContext,
        entryIndex: Int = -1,
        loadedSongID: UUID? = nil,
        onLoadSong: @escaping (Song) -> Void = { _ in },
        onNext: @escaping () -> Void = {},
        onPrevious: @escaping () -> Void = {},
        onChanged: @escaping () -> Void = {},
        onInspectSong: @escaping (UUID) -> Void = { _ in }
    ) {
        self.context = context
        self.entryIndex = entryIndex
        self.loadedSongID = loadedSongID
        self.onLoadSong = onLoadSong
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onChanged = onChanged
        self.onInspectSong = onInspectSong
    }

    private var selectedSong: Song? {
        if let selectedSongID {
            return context.project.songs.first(where: { $0.id == selectedSongID })
        }
        if let loadedSongID {
            return context.project.songs.first(where: { $0.id == loadedSongID })
        }
        return context.project.songs.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AuroraColor.separator)
            entryNavBar
            Divider().overlay(AuroraColor.separator)
            if context.project.songs.isEmpty {
                AuroraEmptyState(
                    title: "No songs",
                    detail: "Create a song and add cue entries for the set list.",
                    systemImage: "music.note.list"
                )
                .frame(minHeight: 120)
            } else {
                songList
                if let song = selectedSong {
                    entryEditor(song)
                }
            }
            if let statusText {
                Text(statusText)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .padding(8)
            }
        }
        .background(AuroraColor.surfacePanel)
        .confirmationDialog("Delete song?", isPresented: $showDeleteSongConfirm, titleVisibility: .visible) {
            Button("Delete Song", role: .destructive) { deleteSelectedSong() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the song. Cues in lists are not deleted.")
        }
        .onAppear {
            if selectedSongID == nil {
                selectedSongID = loadedSongID ?? context.project.songs.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Songs")
                .font(AuroraTypography.panelTitle)
                .foregroundStyle(AuroraColor.textSecondary)
            Spacer()
            Button("New Song") { addSong() }
                .controlSize(.small)
            Button("Delete", role: .destructive) {
                showDeleteSongConfirm = true
            }
            .controlSize(.small)
            .disabled(selectedSong == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AuroraColor.surfaceHeader)
    }

    /// Secondary to GO — not transport-styled (A5 / CR-14).
    private var entryNavBar: some View {
        HStack(spacing: 8) {
            Text("Song entry")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Button("◀") { onPrevious() }
                .controlSize(.small)
                .buttonStyle(.bordered)
            Button("▶") { onNext() }
                .controlSize(.small)
                .buttonStyle(.bordered)
            if entryIndex >= 0 {
                Text("\(entryIndex + 1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AuroraColor.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AuroraColor.surfacePanel)
    }

    private var songList: some View {
        List(selection: Binding(
            get: { selectedSongID },
            set: { id in
                selectedSongID = id
                if let id { onInspectSong(id) }
            }
        )) {
            ForEach(context.project.songs) { song in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(AuroraTypography.secondary)
                        Text("\(song.artist.isEmpty ? "—" : song.artist) · \(song.entries.count) entries")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                    Spacer()
                    if loadedSongID == song.id {
                        Text("LOADED")
                            .font(AuroraTypography.status)
                            .foregroundStyle(AuroraColor.accentBright)
                    }
                    Button("Load") {
                        selectedSongID = song.id
                        onInspectSong(song.id)
                        onLoadSong(song)
                        statusText = "Loaded \(song.title)"
                    }
                    .controlSize(.small)
                }
                .tag(song.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 80, maxHeight: 140)
    }

    private func entryEditor(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Entries")
                    .font(AuroraTypography.sectionHeading)
                    .foregroundStyle(AuroraColor.textSecondary)
                Spacer()
                Button("+ Selected Cue") { addEntryFromSelectedCue(song) }
                    .controlSize(.small)
                Menu("+ Cue List") {
                    if context.project.cueLists.isEmpty {
                        Text("No cue lists")
                    } else {
                        ForEach(context.project.cueLists) { list in
                            Button(list.name) { addEntryFromList(song, list: list) }
                        }
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)

            if song.entries.isEmpty {
                Text("No entries — add a cue or list reference.")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .padding(.horizontal, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(song.entries.enumerated()), id: \.element.id) { idx, entry in
                            HStack {
                                Text("\(idx + 1).")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(idx == entryIndex && loadedSongID == song.id
                                        ? AuroraColor.accentBright
                                        : AuroraColor.textTertiary)
                                    .frame(width: 28, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.label.isEmpty ? entryTargetLabel(entry) : entry.label)
                                        .font(AuroraTypography.secondary)
                                    Text(entryTargetDetail(entry))
                                        .font(AuroraTypography.metadata)
                                        .foregroundStyle(
                                            targetMissing(entry) ? AuroraColor.warning : AuroraColor.textTertiary
                                        )
                                }
                                Spacer()
                                Button("↑") { moveEntry(song, index: idx, delta: -1) }
                                    .controlSize(.mini)
                                    .disabled(idx == 0)
                                Button("↓") { moveEntry(song, index: idx, delta: 1) }
                                    .controlSize(.mini)
                                    .disabled(idx >= song.entries.count - 1)
                                Button("Remove") { removeEntry(song, entryID: entry.id) }
                                    .controlSize(.mini)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: 200)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Mutations

    private func addSong() {
        // CR-08: empty song — operator explicitly adds entries.
        let song = Song(title: "Song \(context.project.songs.count + 1)")
        do {
            try context.session.perform(AddSongCommand(song: song))
            selectedSongID = song.id
            onInspectSong(song.id)
            statusText = "Created \(song.title) (empty — add entries)"
            onChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func deleteSelectedSong() {
        guard let song = selectedSong else { return }
        do {
            try context.session.perform(RemoveSongCommand(songID: song.id))
            selectedSongID = nil
            statusText = "Deleted \(song.title)"
            onChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func addEntryFromSelectedCue(_ song: Song) {
        let cueIDs = context.session.selection.snapshot.cueIDs
        let listIDs = context.session.selection.snapshot.cueListIDs
        guard let cueID = cueIDs.first else {
            statusText = "Select a cue in the Cues panel first"
            return
        }
        var listID = listIDs.first
        if listID == nil {
            listID = context.project.cueLists.first(where: { list in
                list.cues.contains(where: { $0.id == cueID })
            })?.id
        }
        guard let listID,
              let list = context.project.cueLists.first(where: { $0.id == listID }),
              let cue = list.cues.first(where: { $0.id == cueID })
        else {
            statusText = "Could not resolve selected cue"
            return
        }
        var updated = song
        let label = cue.name.isEmpty ? "Cue \(cue.number)" : cue.name
        updated.entries.append(SongEntry(target: .cue(listId: listID, cueId: cueID), label: label))
        commitSong(updated, status: "Added entry \(label)")
    }

    /// CR-07: prefer selected cue list, else explicit menu choice (caller).
    private func addEntryFromList(_ song: Song, list: CueList) {
        var updated = song
        updated.entries.append(SongEntry(target: .cueList(list.id), label: list.name))
        commitSong(updated, status: "Added list entry \(list.name)")
    }

    private func removeEntry(_ song: Song, entryID: UUID) {
        var updated = song
        updated.entries.removeAll { $0.id == entryID }
        commitSong(updated, status: "Removed entry (cue kept in list)")
    }

    private func moveEntry(_ song: Song, index: Int, delta: Int) {
        let target = index + delta
        guard song.entries.indices.contains(index), song.entries.indices.contains(target) else { return }
        var updated = song
        updated.entries.swapAt(index, target)
        commitSong(updated, status: "Reordered entries")
    }

    private func commitSong(_ song: Song, status: String) {
        do {
            try context.session.perform(UpdateSongCommand(song: song))
            statusText = status
            onChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    // MARK: - Labels

    private func entryTargetLabel(_ entry: SongEntry) -> String {
        switch entry.target {
        case .cueList(let id):
            return context.project.cueLists.first(where: { $0.id == id })?.name ?? "Missing list"
        case .cue(let listID, let cueID):
            if let list = context.project.cueLists.first(where: { $0.id == listID }),
               let cue = list.cues.first(where: { $0.id == cueID }) {
                return cue.name.isEmpty ? "Cue \(cue.number)" : cue.name
            }
            return "Missing cue"
        }
    }

    private func entryTargetDetail(_ entry: SongEntry) -> String {
        switch entry.target {
        case .cueList:
            return targetMissing(entry) ? "Missing cue list" : "Cue list"
        case .cue:
            return targetMissing(entry) ? "Missing cue" : "Cue"
        }
    }

    private func targetMissing(_ entry: SongEntry) -> Bool {
        switch entry.target {
        case .cueList(let id):
            return !context.project.cueLists.contains(where: { $0.id == id })
        case .cue(let listID, let cueID):
            guard let list = context.project.cueLists.first(where: { $0.id == listID }) else { return true }
            return !list.cues.contains(where: { $0.id == cueID })
        }
    }
}
