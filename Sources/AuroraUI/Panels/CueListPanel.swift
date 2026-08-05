import AuroraCore
import AuroraModel
import SwiftUI

/// Cue list editor and transport controls.
public struct CueListPanel: View {
    public var context: WorkspacePanelContext
    public var playbackCueIndex: Int
    public var onGo: () -> Void
    public var onStop: () -> Void
    public var onBack: () -> Void
    public var onFire: (UUID) -> Void
    public var onProjectChanged: () -> Void

    @State private var selectedListID: UUID?
    @State private var selectedCueID: UUID?
    @State private var errorText: String?
    @State private var editName: String = ""
    @State private var editFadeIn: String = "0"
    @State private var editDelay: String = "0"

    public init(
        context: WorkspacePanelContext,
        playbackCueIndex: Int = -1,
        onGo: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {},
        onFire: @escaping (UUID) -> Void = { _ in },
        onProjectChanged: @escaping () -> Void = {}
    ) {
        self.context = context
        self.playbackCueIndex = playbackCueIndex
        self.onGo = onGo
        self.onStop = onStop
        self.onBack = onBack
        self.onFire = onFire
        self.onProjectChanged = onProjectChanged
    }

    private var lists: [CueList] { context.project.cueLists }

    private var currentList: CueList? {
        if let selectedListID {
            return lists.first { $0.id == selectedListID }
        }
        return lists.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            transportBar
            Divider()
            listHeader
            Divider()
            if let list = currentList {
                cueTable(list)
                Divider()
                cueEditor(list)
            } else {
                PlaceholderPanel(
                    title: "Cue List",
                    detail: "Add a cue list to start programming cues."
                )
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(6)
            }
        }
        .onAppear {
            if selectedListID == nil {
                selectedListID = lists.first?.id
            }
        }
    }

    private var transportBar: some View {
        HStack(spacing: 8) {
            Button("Go") { onGo() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Stop") { onStop() }
            Button("Back") { onBack() }
            Spacer()
            if playbackCueIndex >= 0 {
                Text("Playing #\(playbackCueIndex + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }

    private var listHeader: some View {
        HStack {
            if lists.isEmpty {
                Text("No lists")
                    .foregroundStyle(.secondary)
            } else {
                Picker("List", selection: Binding(
                    get: { currentList?.id ?? lists[0].id },
                    set: { selectedListID = $0 }
                )) {
                    ForEach(lists) { list in
                        Text(list.name).tag(list.id)
                    }
                }
                .labelsHidden()
            }
            Spacer()
            Button("Add List") { addList() }
            Button("+ Cue") { addCue() }
                .disabled(currentList == nil)
            Button("Delete Cue", role: .destructive) { deleteCue() }
                .disabled(selectedCueID == nil)
        }
        .padding(8)
    }

    private func cueTable(_ list: CueList) -> some View {
        List(list.cues, id: \.id, selection: $selectedCueID) { cue in
            HStack {
                Text(cue.number.description)
                    .font(.body.monospaced())
                    .frame(width: 48, alignment: .leading)
                Text(cue.name.isEmpty ? "—" : cue.name)
                Spacer()
                Text(String(format: "F %.1f", cue.fadeIn))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let idx = list.cues.firstIndex(where: { $0.id == cue.id }), idx == playbackCueIndex {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedCueID = cue.id
                loadEditor(cue)
            }
            .onChange(of: selectedCueID) { _, newID in
                if let newID, let cue = list.cues.first(where: { $0.id == newID }) {
                    loadEditor(cue)
                }
            }
        }
    }

    private func cueEditor(_ list: CueList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected cue")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Name", text: $editName)
            HStack {
                Text("Fade in")
                TextField("0", text: $editFadeIn)
                    .frame(width: 60)
                Text("Delay")
                TextField("0", text: $editDelay)
                    .frame(width: 60)
            }
            HStack {
                Button("Apply") { applyEdits(list) }
                Button("Fire") {
                    if let selectedCueID { onFire(selectedCueID) }
                }
                .disabled(selectedCueID == nil)
            }
        }
        .padding(8)
    }

    private func loadEditor(_ cue: Cue) {
        editName = cue.name
        editFadeIn = String(cue.fadeIn)
        editDelay = String(cue.delay)
    }

    private func addList() {
        errorText = nil
        let list = CueList(name: "List \(lists.count + 1)")
        do {
            try context.session.perform(AddCueListCommand(list: list))
            selectedListID = list.id
            onProjectChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func addCue() {
        errorText = nil
        guard let list = currentList else { return }
        let nextNum = (list.cues.count + 1)
        let cue = Cue(
            number: Decimal(nextNum),
            name: "Cue \(nextNum)",
            fadeIn: context.project.preferences.defaultFadeIn,
            fadeOut: context.project.preferences.defaultFadeOut,
            tracking: context.project.preferences.defaultTracking
        )
        do {
            try context.session.perform(AddCueCommand(listID: list.id, cue: cue))
            selectedCueID = cue.id
            loadEditor(cue)
            onProjectChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteCue() {
        errorText = nil
        guard let list = currentList, let selectedCueID else { return }
        do {
            try context.session.perform(RemoveCueCommand(listID: list.id, cueID: selectedCueID))
            self.selectedCueID = nil
            onProjectChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func applyEdits(_ list: CueList) {
        errorText = nil
        guard let selectedCueID,
              var cue = list.cues.first(where: { $0.id == selectedCueID })
        else { return }
        cue.name = editName
        cue.fadeIn = Double(editFadeIn) ?? cue.fadeIn
        cue.delay = Double(editDelay) ?? cue.delay
        do {
            try context.session.perform(UpdateCueCommand(listID: list.id, cue: cue))
            onProjectChanged()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
