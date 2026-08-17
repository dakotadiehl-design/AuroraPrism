import AuroraCore
import AuroraEngine
import AuroraModel
import Foundation
import SwiftUI

/// Cue list editor — select ≠ fire; record/update from Programmer (UI-05).
///
/// **Ordering authority (A4):** playback follows `CueList.cues` array order.
/// `Cue.number` is display metadata only. New cues append to the array.
public struct CueListPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var playbackCueIndex: Int
    public var playbackCueListID: UUID?
    public var playbackCueID: UUID?
    public var onGo: () -> Void
    public var onStop: () -> Void
    public var onBack: () -> Void
    public var onFire: (UUID) -> Void
    public var onProjectChanged: () -> Void
    public var onInspectCue: (UUID) -> Void
    public var onSelectCue: (UUID, UUID?) -> Void
    public var documentEpoch: Int

    @State private var selectedListID: UUID?
    @State private var selectedCueID: UUID?
    @State private var statusText: String?
    @State private var cuePendingDelete: Cue?
    @State private var showDeleteCueConfirm = false
    @State private var showDeleteListConfirm = false

    public init(
        context: WorkspacePanelContext,
        programmer: Programmer = Programmer(),
        playbackCueIndex: Int = -1,
        playbackCueListID: UUID? = nil,
        playbackCueID: UUID? = nil,
        onGo: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {},
        onFire: @escaping (UUID) -> Void = { _ in },
        onProjectChanged: @escaping () -> Void = {},
        onInspectCue: @escaping (UUID) -> Void = { _ in },
        onSelectCue: @escaping (UUID, UUID?) -> Void = { _, _ in },
        documentEpoch: Int = 0
    ) {
        self.context = context
        self.programmer = programmer
        self.playbackCueIndex = playbackCueIndex
        self.playbackCueListID = playbackCueListID
        self.playbackCueID = playbackCueID
        self.onGo = onGo
        self.onStop = onStop
        self.onBack = onBack
        self.onFire = onFire
        self.onProjectChanged = onProjectChanged
        self.onInspectCue = onInspectCue
        self.onSelectCue = onSelectCue
        self.documentEpoch = documentEpoch
    }

    private var lists: [CueList] { context.project.cueLists }

    private var currentList: CueList? {
        if let selectedListID, let match = lists.first(where: { $0.id == selectedListID }) {
            return match
        }
        return lists.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            transportBar
            Divider().overlay(AuroraColor.separator)
            editorToolbar
            Divider().overlay(AuroraColor.separator)
            listPicker
            Divider().overlay(AuroraColor.separator)
            cueBody
            if let statusText {
                Text(statusText)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .background(AuroraColor.surfacePanel)
        .auroraDensity(.compact)
        .onAppear { healListSelection() }
        .onChange(of: documentEpoch) { _, _ in
            healListSelection()
            selectedCueID = nil
        }
        .onChange(of: lists.map(\.id)) { _, _ in
            healListSelection()
        }
        .confirmationDialog(
            "Delete cue?",
            isPresented: $showDeleteCueConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Cue", role: .destructive) {
                if let cue = cuePendingDelete { deleteCue(cue) }
                cuePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { cuePendingDelete = nil }
        } message: {
            Text("Removes the cue from this list. Songs may keep missing targets.")
        }
        .confirmationDialog(
            "Delete cue list?",
            isPresented: $showDeleteListConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) { deleteCurrentList() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the list and all of its cues. Song entries may become missing targets.")
        }
    }

    // MARK: - Chrome

    private var transportBar: some View {
        HStack(spacing: 8) {
            AuroraTransportButton(kind: .back, useIcon: true, action: onBack)
            AuroraTransportButton(kind: .go, useIcon: true, action: onGo)
            AuroraTransportButton(kind: .stop, useIcon: true, action: onStop)
            Spacer()
            if let playbackCueID,
               let list = currentList,
               let cue = list.cues.first(where: { $0.id == playbackCueID }) {
                Text("Playing \(cueNumberString(cue))")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            } else if playbackCueIndex >= 0 {
                Text("Playing #\(playbackCueIndex + 1)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
        }
        .padding(8)
        .background(AuroraColor.surfaceHeader)
        .auroraDensity(.standard)
    }

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            Button("+ List") { addList() }
                .controlSize(.small)
            Button("Delete List", role: .destructive) {
                showDeleteListConfirm = true
            }
            .controlSize(.small)
            .disabled(currentList == nil)

            Divider().frame(height: 16)

            Button("Record") { recordCue() }
                .controlSize(.small)
                .disabled(currentList == nil)
            Button("Update") { updateSelectedCue() }
                .controlSize(.small)
                .disabled(selectedCue == nil)
            Button("+ Empty") { addEmptyCue() }
                .controlSize(.small)
                .disabled(currentList == nil)
            Button("Fire") {
                if let cue = selectedCue { onFire(cue.id) }
            }
            .controlSize(.small)
            .disabled(selectedCue == nil)
            Button("Duplicate") { duplicateSelectedCue() }
                .controlSize(.small)
                .disabled(selectedCue == nil)
            Button("↑") { moveSelectedCue(by: -1) }
                .controlSize(.small)
                .disabled(selectedCue == nil)
            Button("↓") { moveSelectedCue(by: 1) }
                .controlSize(.small)
                .disabled(selectedCue == nil)
            Button("Delete", role: .destructive) {
                if let cue = selectedCue {
                    cuePendingDelete = cue
                    showDeleteCueConfirm = true
                }
            }
            .controlSize(.small)
            .disabled(selectedCue == nil)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var listPicker: some View {
        HStack {
            if lists.isEmpty {
                Text("No cue lists")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            } else {
                Picker("List", selection: Binding(
                    get: { selectedListID ?? currentList?.id },
                    set: { selectedListID = $0; selectedCueID = nil }
                )) {
                    ForEach(lists) { list in
                        Text(list.name).tag(Optional(list.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            Spacer()
            if let list = currentList {
                Text("\(list.cues.count) cues · order = list order")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var cueBody: some View {
        if let list = currentList {
            if list.cues.isEmpty {
                AuroraEmptyState(
                    title: "No cues",
                    detail: "Record from the programmer or add an empty cue.",
                    systemImage: "list.number"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.cues.enumerated()), id: \.element.id) { index, cue in
                            VStack(spacing: 0) {
                                AuroraCueRow(
                                    number: cueNumberString(cue),
                                    name: cue.name.isEmpty ? "Cue \(cueNumberString(cue))" : cue.name,
                                    timing: timingSummary(cue),
                                    trigger: followLabel(cue),
                                    playbackRole: playbackRole(for: index, cue: cue, list: list),
                                    isSelected: selectedCueID == cue.id,
                                    onSelect: { selectCue(cue, list: list) },
                                    onDoubleClickFire: {
                                        selectCue(cue, list: list)
                                        onFire(cue.id)
                                    }
                                )
                                if selectedCueID == cue.id {
                                    cueTimingEditor(cue, list: list)
                                }
                            }
                            .contextMenu {
                                Button("Fire Cue") {
                                    selectCue(cue, list: list)
                                    onFire(cue.id)
                                }
                                Button("Inspect") { selectCue(cue, list: list) }
                                Button("Update from Programmer") {
                                    selectCue(cue, list: list)
                                    updateSelectedCue()
                                }
                                Button("Duplicate") {
                                    selectCue(cue, list: list)
                                    duplicateSelectedCue()
                                }
                                Button("Move Up") {
                                    selectCue(cue, list: list)
                                    moveSelectedCue(by: -1)
                                }
                                Button("Move Down") {
                                    selectCue(cue, list: list)
                                    moveSelectedCue(by: 1)
                                }
                                Button("Delete", role: .destructive) {
                                    cuePendingDelete = cue
                                    showDeleteCueConfirm = true
                                }
                            }
                        }
                    }
                }
            }
        } else {
            AuroraEmptyState(
                title: "No cue list",
                detail: "Create a cue list to begin programming.",
                systemImage: "list.bullet"
            )
        }
    }

    private var selectedCue: Cue? {
        guard let list = currentList, let selectedCueID else { return nil }
        return list.cues.first(where: { $0.id == selectedCueID })
    }

    // MARK: - Selection

    private func selectCue(_ cue: Cue, list: CueList) {
        selectedCueID = cue.id
        selectedListID = list.id
        context.session.selection.selectCues([cue.id], extending: false)
        context.session.selection.selectCueLists([list.id], extending: false)
        onSelectCue(cue.id, list.id)
        onInspectCue(cue.id)
    }

    private func healListSelection() {
        if let selectedListID, lists.contains(where: { $0.id == selectedListID }) {
            return
        }
        selectedListID = lists.first?.id
        if let selectedCueID,
           currentList?.cues.contains(where: { $0.id == selectedCueID }) != true {
            self.selectedCueID = nil
        }
    }

    // MARK: - Mutations

    private func addList() {
        let list = CueList(name: "List \(context.project.cueLists.count + 1)")
        do {
            try context.session.perform(AddCueListCommand(list: list))
            selectedListID = list.id
            selectedCueID = nil
            statusText = "Created \(list.name)"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func deleteCurrentList() {
        guard let list = currentList else { return }
        do {
            try context.session.perform(RemoveCueListCommand(listID: list.id))
            selectedListID = nil
            selectedCueID = nil
            statusText = "Deleted list \(list.name)"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    /// Append empty cue to array end (playback order = append position). Number is display only.
    private func addEmptyCue() {
        guard let list = currentList else { return }
        let prefs = context.project.preferences
        let displayNumber = ProgrammerCueBridge.nextDisplayNumber(in: list)
        let cue = Cue(
            number: displayNumber,
            name: "Cue \(NSDecimalNumber(decimal: displayNumber).stringValue)",
            fadeIn: prefs.defaultFadeIn,
            fadeOut: prefs.defaultFadeOut,
            tracking: prefs.defaultTracking
        )
        do {
            try context.session.perform(AddCueCommand(listID: list.id, cue: cue))
            selectCue(cue, list: refreshedList(list.id) ?? list)
            statusText = "Added empty cue (appended)"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    /// Record new cue from Programmer capture — appends to list (A4 array order).
    private func recordCue() {
        guard let list = currentList else { return }
        let levels = programmer.captureLevels()
        guard !ProgrammerCueBridge.levelsAreEmpty(levels) else {
            statusText = "Programmer empty — set values before Record"
            return
        }
        let cue = ProgrammerCueBridge.makeRecordedCue(
            levels: levels,
            list: list,
            preferences: context.project.preferences
        )
        do {
            try context.session.perform(AddCueCommand(listID: list.id, cue: cue))
            if let updated = refreshedList(list.id) {
                selectCue(cue, list: updated)
            }
            statusText = "Recorded \(cue.name) (\(levels.fixtures.count) fixture(s))"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    /// Immediate level replace — no modal (A3). Metadata/timing preserved.
    private func updateSelectedCue() {
        guard let list = currentList, let cue = selectedCue else {
            statusText = "Select a cue to Update"
            return
        }
        let levels = programmer.captureLevels()
        guard !ProgrammerCueBridge.levelsAreEmpty(levels) else {
            statusText = "Programmer empty — nothing to Update"
            return
        }
        let next = ProgrammerCueBridge.cueByApplyingLevels(cue, levels: levels)
        do {
            try context.session.perform(UpdateCueCommand(listID: list.id, cue: next))
            statusText = "Updated \(next.name.isEmpty ? "cue" : next.name) levels"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func duplicateSelectedCue() {
        guard let list = currentList, let cue = selectedCue else { return }
        do {
            let cmd = DuplicateCueCommand(listID: list.id, sourceCueID: cue.id)
            try context.session.perform(cmd)
            if let newID = cmd.duplicatedCueID,
               let updated = refreshedList(list.id),
               let newCue = updated.cues.first(where: { $0.id == newID }) {
                selectCue(newCue, list: updated)
            }
            statusText = "Duplicated cue"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func moveSelectedCue(by delta: Int) {
        guard let list = currentList,
              let cue = selectedCue,
              let from = list.cues.firstIndex(where: { $0.id == cue.id })
        else { return }
        let to = from + delta
        guard list.cues.indices.contains(to) else { return }
        do {
            try context.session.perform(ReorderCueCommand(listID: list.id, cueID: cue.id, toIndex: to))
            statusText = "Reordered cue"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func timingSummary(_ cue: Cue) -> String {
        var parts = [String(format: "In %.1f", cue.fadeIn)]
        if cue.fadeOut > 0 { parts.append(String(format: "Out %.1f", cue.fadeOut)) }
        if cue.delay > 0 { parts.append(String(format: "Dly %.1f", cue.delay)) }
        return parts.joined(separator: " · ")
    }

    private func followLabel(_ cue: Cue) -> String {
        switch cue.follow {
        case .none: return "Manual"
        case .manual: return "Manual"
        case .afterTime:
            if let t = cue.followTime { return String(format: "Follow %.1fs", t) }
            return "Follow"
        case .afterGo: return "After GO"
        }
    }

    private func cueTimingEditor(_ cue: Cue, list: CueList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Name", text: Binding(
                    get: { cue.name },
                    set: { name in commitCue(cue, list: list) { $0.name = name } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 160)
                TextField("No.", text: Binding(
                    get: { NSDecimalNumber(decimal: cue.number).stringValue },
                    set: { raw in
                        if let d = Decimal(string: raw) {
                            commitCue(cue, list: list) { $0.number = d }
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            }
            HStack(spacing: 8) {
                timingField("Fade In", value: cue.fadeIn) { v in
                    commitCue(cue, list: list) { $0.fadeIn = v }
                }
                timingField("Fade Out", value: cue.fadeOut) { v in
                    commitCue(cue, list: list) { $0.fadeOut = v }
                }
                timingField("Delay", value: cue.delay) { v in
                    commitCue(cue, list: list) { $0.delay = v }
                }
            }
            HStack(spacing: 8) {
                Picker("Follow", selection: Binding(
                    get: { cue.follow },
                    set: { mode in commitCue(cue, list: list) { $0.follow = mode } }
                )) {
                    ForEach(FollowMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(maxWidth: 140)
                if cue.follow == .afterTime {
                    timingField("Follow t", value: cue.followTime ?? 0) { v in
                        commitCue(cue, list: list) { $0.followTime = v }
                    }
                }
                Picker("Track", selection: Binding(
                    get: { cue.tracking },
                    set: { mode in commitCue(cue, list: list) { $0.tracking = mode } }
                )) {
                    ForEach(TrackingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(maxWidth: 120)
            }
            if !cue.cueBlockRefs.isEmpty || !context.project.cueBlocks.isEmpty {
                cueBlockReferenceEditor(cue, list: list)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AuroraColor.surfaceWell)
    }

    private func cueBlockReferenceEditor(_ cue: Cue, list: CueList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Cue Blocks")
                    .font(AuroraTypography.metadata.weight(.semibold))
                    .foregroundStyle(AuroraColor.textSecondary)
                Text("later blocks override earlier blocks")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                Spacer()
                Menu {
                    ForEach(context.project.cueBlockGroups) { group in
                        let blocks = context.project.cueBlocks.filter { $0.cueBlockGroupID == group.id }
                        if !blocks.isEmpty {
                            Menu(group.name) {
                                cueBlockAddButtons(blocks, cue: cue, list: list)
                            }
                        }
                    }
                    let unfiled = context.project.cueBlocks.filter { $0.cueBlockGroupID == nil }
                    if !unfiled.isEmpty {
                        Menu("Unfiled") {
                            cueBlockAddButtons(unfiled, cue: cue, list: list)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add a Cue Block to this cue")
            }
            ForEach(Array(cue.cueBlockRefs.enumerated()), id: \.element.id) { index, reference in
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(
                        get: { reference.enabled },
                        set: { setCueBlockReference(reference, enabled: $0, cue: cue, list: list) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    if let block = context.project.cueBlock(id: reference.cueBlockID) {
                        Image(systemName: cueBlockSymbol(block.type))
                            .foregroundStyle(reference.enabled ? AuroraColor.accentBright : AuroraColor.textTertiary)
                            .frame(width: 14)
                        Text(cueBlockPath(block))
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(reference.enabled ? AuroraColor.textPrimary : AuroraColor.textTertiary)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AuroraColor.warning)
                        Text("Missing Cue Block")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.warning)
                    }
                    Spacer(minLength: 4)
                    Button("↑") { moveCueBlockReference(reference, to: index - 1, cue: cue, list: list) }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                    Button("↓") { moveCueBlockReference(reference, to: index + 1, cue: cue, list: list) }
                        .buttonStyle(.plain)
                        .disabled(index == cue.cueBlockRefs.count - 1)
                    Button {
                        removeCueBlockReference(reference, cue: cue, list: list)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .help("Remove Cue Block from cue")
                }
                .frame(height: 22)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func cueBlockAddButtons(_ blocks: [CueBlock], cue: Cue, list: CueList) -> some View {
        ForEach(CueBlockType.allCases, id: \.self) { type in
            let typed = blocks.filter { $0.type == type }
            if !typed.isEmpty {
                Menu(cueBlockTypeName(type)) {
                    ForEach(typed) { block in
                        Button(block.name) { addCueBlock(block, cue: cue, list: list) }
                            .disabled(cue.cueBlockRefs.contains { $0.cueBlockID == block.id })
                    }
                }
            }
        }
    }

    private func addCueBlock(_ block: CueBlock, cue: Cue, list: CueList) {
        do {
            try context.session.perform(AddCueBlockReferenceCommand(
                listID: list.id,
                cueID: cue.id,
                cueBlockID: block.id
            ))
            statusText = "Added \(block.name) to cue"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func cueBlockPath(_ block: CueBlock) -> String {
        let group = block.cueBlockGroupID.flatMap { context.project.cueBlockGroup(id: $0)?.name } ?? "Unfiled"
        return "\(group) / \(cueBlockTypeName(block.type)) / \(block.name)"
    }

    private func cueBlockTypeName(_ type: CueBlockType) -> String {
        switch type {
        case .intensity: return "Dimmer"
        case .color: return "Color"
        case .position: return "Position"
        case .beam: return "Beam"
        case .gobo: return "Gobo"
        case .general: return "General"
        }
    }

    private func cueBlockSymbol(_ type: CueBlockType) -> String {
        switch type {
        case .intensity: return "sun.max.fill"
        case .color: return "circle.fill"
        case .position: return "scope"
        case .beam: return "light.beacon.max.fill"
        case .gobo: return "circle.hexagongrid.fill"
        case .general: return "square.stack.3d.up.fill"
        }
    }

    private func setCueBlockReference(_ reference: CueBlockReference, enabled: Bool, cue: Cue, list: CueList) {
        do {
            try context.session.perform(SetCueBlockReferenceEnabledCommand(
                listID: list.id,
                cueID: cue.id,
                referenceID: reference.id,
                enabled: enabled
            ))
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func moveCueBlockReference(_ reference: CueBlockReference, to index: Int, cue: Cue, list: CueList) {
        do {
            try context.session.perform(MoveCueBlockReferenceCommand(
                listID: list.id,
                cueID: cue.id,
                referenceID: reference.id,
                toIndex: index
            ))
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func removeCueBlockReference(_ reference: CueBlockReference, cue: Cue, list: CueList) {
        do {
            try context.session.perform(RemoveCueBlockReferenceCommand(
                listID: list.id,
                cueID: cue.id,
                referenceID: reference.id
            ))
            statusText = "Removed Cue Block from cue"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func timingField(_ label: String, value: TimeInterval, onCommit: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
            TextField(label, value: Binding(
                get: { value },
                set: { onCommit(max(0, $0)) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 52)
        }
    }

    private func commitCue(_ cue: Cue, list: CueList, mutate: (inout Cue) -> Void) {
        var next = cue
        mutate(&next)
        do {
            try context.session.perform(UpdateCueCommand(listID: list.id, cue: next))
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func deleteCue(_ cue: Cue) {
        guard let list = currentList else { return }
        do {
            try context.session.perform(RemoveCueCommand(listID: list.id, cueID: cue.id))
            if selectedCueID == cue.id { selectedCueID = nil }
            statusText = "Deleted cue"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func refreshedList(_ id: UUID) -> CueList? {
        context.project.cueLists.first(where: { $0.id == id })
    }

    /// Display number only — does not control playback order (A4).
    // MARK: - Role / format

    /// Playback role only — selection is a separate overlay (CR-09).
    private func playbackRole(for index: Int, cue: Cue, list: CueList) -> AuroraCuePlaybackRole {
        if let playbackCueID, cue.id == playbackCueID { return .current }
        if let playbackCueListID, list.id == playbackCueListID, index == playbackCueIndex {
            return .current
        }
        if let playbackCueListID, list.id == playbackCueListID,
           playbackCueIndex >= 0, index == playbackCueIndex + 1 {
            return .next
        }
        return .normal
    }

    private func cueNumberString(_ cue: Cue) -> String {
        NSDecimalNumber(decimal: cue.number).stringValue
    }
}
