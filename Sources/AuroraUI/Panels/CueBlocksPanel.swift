import AuroraDesignSystem
import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public extension Notification.Name {
    /// Requests the standard Cue Block creation workflow from the visible library panel.
    static let prismCreateCueBlock = Notification.Name("prism.createCueBlock")
    /// Requests the standard Cue Block Group creation workflow from the visible library panel.
    static let prismCreateCueBlockGroup = Notification.Name("prism.createCueBlockGroup")
}

/// Compact, LightKey-inspired Cue Blocks library: organizational Group → semantic type → block.
public struct CueBlocksPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var onProgrammerChanged: () -> Void
    public var onProjectChanged: () -> Void

    @State private var searchText = ""
    @State private var selectedBlockID: UUID?
    @State private var activeBlockIDs: [UUID] = []
    @State private var programmerValuesBeforeCueBlocks: [UUID: [String: Double]]?
    @State private var expandedGroups = Set<UUID>()
    @State private var expandedTypes = Set<String>()
    @State private var showsUnfiled = true
    @State private var showCreateGroup = false
    @State private var showCreateBlock = false
    @State private var newGroupName = ""
    @State private var newBlockName = ""
    @State private var newBlockType: CueBlockType = .color
    @State private var newBlockGroupID: UUID?
    @State private var statusText: String?
    @State private var pendingDeleteBlock: CueBlock?
    @State private var pendingDeleteGroup: CueBlockGroup?
    @State private var editingBlock: CueBlock?
    @State private var editingGroup: CueBlockGroup?
    @State private var editName = ""
    @State private var editNotes = ""
    @State private var editBlockType: CueBlockType = .general
    @State private var editBlockGroupID: UUID?
    @State private var editBlockLevels: CueLevelData = .empty
    @State private var pendingValueUpdate: CueBlock?
    @State private var renameTarget: CueBlockRenameTarget?
    @State private var renameDraft = ""
    @State private var dropTargetGroupKey: String?

    public init(
        context: WorkspacePanelContext,
        programmer: Programmer,
        onProgrammerChanged: @escaping () -> Void = {},
        onProjectChanged: @escaping () -> Void = {}
    ) {
        self.context = context
        self.programmer = programmer
        self.onProgrammerChanged = onProgrammerChanged
        self.onProjectChanged = onProjectChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AuroraColor.separator)
            if context.project.cueBlockGroups.isEmpty && context.project.cueBlocks.isEmpty {
                AuroraEmptyState(
                    title: "No Cue Blocks",
                    detail: "Select fixtures, set Programmer values, then save a reusable block.",
                    systemImage: "square.stack.3d.up"
                )
                .frame(height: 112)
            } else {
                tree
            }
            if let statusText {
                Text(statusText)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
        }
        .background(AuroraColor.surfacePanel)
        .alert("New Cue Block Group", isPresented: $showCreateGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Create") { createGroup() }
                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Groups organize Cue Blocks independently from fixture selection groups.")
        }
        .alert(renameTitle, isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename() }
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Enter a clear name that will be easy to recognize while building cues.")
        }
        .sheet(isPresented: $showCreateBlock) {
            createBlockSheet
        }
        .sheet(item: $editingBlock) { block in
            editBlockSheet(block)
        }
        .sheet(item: $editingGroup) { group in
            editGroupSheet(group)
        }
        .confirmationDialog(
            "Delete Cue Block?",
            isPresented: Binding(
                get: { pendingDeleteBlock != nil },
                set: { if !$0 { pendingDeleteBlock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Cue Block", role: .destructive) { deletePendingBlock() }
            Button("Cancel", role: .cancel) { pendingDeleteBlock = nil }
        } message: {
            Text(deleteBlockMessage)
        }
        .confirmationDialog(
            "Delete Cue Block Group?",
            isPresented: Binding(
                get: { pendingDeleteGroup != nil },
                set: { if !$0 { pendingDeleteGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) { deletePendingGroup() }
            Button("Cancel", role: .cancel) { pendingDeleteGroup = nil }
        } message: {
            Text("Contained Cue Blocks will be preserved in Unfiled.")
        }
        .confirmationDialog(
            "Replace Cue Block Values?",
            isPresented: Binding(
                get: { pendingValueUpdate != nil },
                set: { if !$0 { pendingValueUpdate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace Values") { updatePendingBlockValues() }
            Button("Cancel", role: .cancel) { pendingValueUpdate = nil }
        } message: {
            Text("The selected fixtures and current Programmer values will replace this block’s stored fixture scope and values. Its name, group, notes, and cue references will be preserved.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .prismCreateCueBlock)) { _ in
            prepareBlockCreation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prismCreateCueBlockGroup)) { _ in
            prepareGroupCreation()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(AuroraColor.accentBright)
            Text("Cue Blocks")
                .font(AuroraTypography.panelTitle)
                .foregroundStyle(AuroraColor.textSecondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 180)
            Spacer(minLength: 4)
            Button("+ Group") { prepareGroupCreation() }
                .controlSize(.small)
            Button("+ Block") { prepareBlockCreation() }
                .controlSize(.small)
                .disabled(context.session.selection.snapshot.orderedFixtureIDs.isEmpty)
            Menu {
                if let block = selectedBlock {
                    Button("Rename Cue Block…") { beginRename(block) }
                    Button("Edit Cue Block…") { beginEditing(block) }
                    Button("Duplicate Cue Block") { duplicate(block) }
                    Button("Replace Values from Programmer…") { pendingValueUpdate = block }
                        .disabled(context.session.selection.snapshot.orderedFixtureIDs.isEmpty)
                    Button("Add to Selected Cue") { addToSelectedCue(block) }
                    Divider()
                    Button("Delete Cue Block…", role: .destructive) { pendingDeleteBlock = block }
                } else {
                    Text("Select a Cue Block")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("Actions for the selected Cue Block")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AuroraColor.surfaceHeader)
    }

    private var tree: some View {
        LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(context.project.cueBlockGroups) { group in
                let blocks = filteredBlocks(groupID: group.id)
                if searchText.isEmpty || !blocks.isEmpty || group.name.localizedCaseInsensitiveContains(searchText) {
                    groupSection(group, blocks: blocks)
                }
            }
            let unfiled = filteredBlocks(groupID: nil)
            if !unfiled.isEmpty {
                unfiledSection(unfiled)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private func groupSection(_ group: CueBlockGroup, blocks: [CueBlock]) -> some View {
        let expanded = expandedGroups.contains(group.id) || !searchText.isEmpty
        return VStack(alignment: .leading, spacing: 1) {
            Button { toggleGroup(group.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AuroraColor.textTertiary)
                        .frame(width: 10)
                    Image(systemName: "folder")
                        .foregroundStyle(AuroraColor.textSecondary)
                    Text(group.name)
                        .font(AuroraTypography.secondary.weight(.semibold))
                    Spacer()
                    Text("\(blocks.count)")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .frame(height: 24)
                .padding(.horizontal, 4)
                .background(dropTargetGroupKey == group.id.uuidString ? AuroraColor.accent.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: [.text], isTargeted: dropTargetBinding(for: group.id)) { providers in
                acceptCueBlockDrop(providers, destinationGroupID: group.id)
            }
            .contextMenu {
                Button("New Cue Block") {
                    newBlockGroupID = group.id
                    prepareBlockCreation(keepingGroup: true)
                }
                Button("Rename Group…") { beginRename(group) }
                Button("Edit Group…") { beginEditing(group) }
                Button("Delete Group", role: .destructive) { pendingDeleteGroup = group }
            }
            if expanded {
                typeSections(blocks, groupID: group.id)
                    .padding(.leading, 18)
            }
        }
    }

    private func unfiledSection(_ blocks: [CueBlock]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Button { showsUnfiled.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: showsUnfiled ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AuroraColor.textTertiary)
                        .frame(width: 10)
                    Image(systemName: "tray")
                        .foregroundStyle(AuroraColor.textSecondary)
                    Text("Unfiled")
                        .font(AuroraTypography.secondary.weight(.semibold))
                    Spacer()
                    Text("\(blocks.count)")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .frame(height: 24)
                .padding(.horizontal, 4)
                .background(dropTargetGroupKey == unfiledDropKey ? AuroraColor.accent.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: [.text], isTargeted: dropTargetBinding(for: nil)) { providers in
                acceptCueBlockDrop(providers, destinationGroupID: nil)
            }
            if showsUnfiled {
                typeSections(blocks, groupID: nil)
                    .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder
    private func typeSections(_ blocks: [CueBlock], groupID: UUID?) -> some View {
        ForEach(CueBlockType.allCases, id: \.self) { type in
            let typed = blocks.filter { $0.type == type }
            if !typed.isEmpty {
                let key = typeExpansionKey(groupID: groupID, type: type)
                let expanded = expandedTypes.contains(key) || !searchText.isEmpty
                VStack(alignment: .leading, spacing: 1) {
                    Button { toggleType(groupID: groupID, type: type) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AuroraColor.textTertiary)
                                .frame(width: 10)
                            Image(systemName: type.folderSymbol)
                                .foregroundStyle(AuroraColor.textTertiary)
                            Text(sectionName(groupID: groupID, type: type))
                                .font(AuroraTypography.secondary)
                            Spacer()
                            Text("\(typed.count)")
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textTertiary)
                        }
                        .frame(height: 23)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let groupID {
                            Button("Rename Section…") {
                                beginRenameSection(groupID: groupID, type: type)
                            }
                        } else {
                            Text("Move this Cue Block into a Group to customize its section name")
                        }
                    }
                    if expanded {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(typed) { block in blockRow(block) }
                        }
                        .padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func toggleGroup(_ id: UUID) {
        if expandedGroups.contains(id) {
            expandedGroups.remove(id)
        } else {
            expandedGroups.insert(id)
        }
    }

    private func typeExpansionKey(groupID: UUID?, type: CueBlockType) -> String {
        "\(groupID?.uuidString ?? "unfiled"):\(type.rawValue)"
    }

    private func toggleType(groupID: UUID?, type: CueBlockType) {
        let key = typeExpansionKey(groupID: groupID, type: type)
        if expandedTypes.contains(key) {
            expandedTypes.remove(key)
        } else {
            expandedTypes.insert(key)
        }
    }

    private func blockRow(_ block: CueBlock) -> some View {
        Button {
            selectedBlockID = block.id
            activate(block, additive: commandModifierIsPressed)
        } label: {
            HStack(spacing: 7) {
                blockIcon(block)
                    .frame(width: 16, height: 16)
                Text(block.name)
                    .font(AuroraTypography.secondary)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(block.levels.fixtures.count)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            .padding(.horizontal, 5)
            .frame(height: 25)
            .background(activeBlockIDs.contains(block.id) ? AuroraColor.surfaceSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            selectedBlockID = block.id
            return NSItemProvider(object: "prism.cueBlock.\(block.id.uuidString)" as NSString)
        }
        .contextMenu {
            Button("Apply to Programmer") { activate(block, additive: false) }
            Button("Add to Selected Cue") { addToSelectedCue(block) }
            Button("Rename Cue Block…") { beginRename(block) }
            Button("Edit…") { beginEditing(block) }
            Button("Duplicate") { duplicate(block) }
            Button("Replace Values from Programmer…") { pendingValueUpdate = block }
                .disabled(context.session.selection.snapshot.orderedFixtureIDs.isEmpty)
            Menu("Move to Group") {
                Button("Unfiled") { move(block, to: nil) }
                ForEach(context.project.cueBlockGroups) { group in
                    Button(group.name) { move(block, to: group.id) }
                }
            }
            Divider()
            Button("Delete Cue Block", role: .destructive) { pendingDeleteBlock = block }
        }
        .help("Click to activate · Command-click to combine · drag to move between Groups")
    }

    private var unfiledDropKey: String { "unfiled" }

    private func dropTargetBinding(for groupID: UUID?) -> Binding<Bool> {
        let key = groupID?.uuidString ?? unfiledDropKey
        return Binding(
            get: { dropTargetGroupKey == key },
            set: { isTargeted in
                if isTargeted {
                    dropTargetGroupKey = key
                    if let groupID { expandedGroups.insert(groupID) }
                } else if dropTargetGroupKey == key {
                    dropTargetGroupKey = nil
                }
            }
        )
    }

    private func acceptCueBlockDrop(_ providers: [NSItemProvider], destinationGroupID: UUID?) -> Bool {
        let prefix = "prism.cueBlock."
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String,
                  payload.hasPrefix(prefix),
                  let blockID = UUID(uuidString: String(payload.dropFirst(prefix.count)))
            else { return }
            DispatchQueue.main.async {
                guard let block = context.project.cueBlock(id: blockID),
                      block.cueBlockGroupID != destinationGroupID
                else { return }
                move(block, to: destinationGroupID)
                dropTargetGroupKey = nil
            }
        }
        return true
    }

    @ViewBuilder
    private func blockIcon(_ block: CueBlock) -> some View {
        if block.type == .color, let color = representativeColor(block) {
            Circle().fill(color).overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        } else {
            Image(systemName: block.type.blockSymbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(block.type == .intensity ? AuroraColor.warning : AuroraColor.accentBright)
        }
    }

    private var createBlockSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Cue Block")
                .font(.headline)
            TextField("Name", text: $newBlockName)
            Picker("Type", selection: $newBlockType) {
                ForEach(CueBlockType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            Picker("Group", selection: $newBlockGroupID) {
                Text("Unfiled").tag(UUID?.none)
                ForEach(context.project.cueBlockGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            Text("\(context.session.selection.snapshot.orderedFixtureIDs.count) selected fixture(s) · only \(newBlockType.displayName.lowercased()) values will be recorded")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack {
                Spacer()
                Button("Cancel") { showCreateBlock = false }
                Button("Save") { createBlock() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newBlockName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 390)
    }

    private func editBlockSheet(_ block: CueBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Cue Block")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 12) {
                    TextField("Name", text: $editName)
                    LabeledContent("Type", value: block.type.displayName)
                        .fixedSize()
                }
                Picker("Group", selection: $editBlockGroupID) {
                    Text("Unfiled").tag(UUID?.none)
                    ForEach(context.project.cueBlockGroups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                TextField("Notes", text: $editNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .padding(20)

            Divider()

            HStack {
                Text("Affected Fixtures")
                    .font(.headline)
                Text("\(editBlockLevels.fixtures.count)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                Spacer()
                Text("Used by \(referenceCount(for: block.id)) cue(s)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if editBlockLevels.fixtures.isEmpty {
                AuroraEmptyState(
                    title: "No Affected Fixtures",
                    detail: "This Cue Block does not currently contain any fixture attributes.",
                    systemImage: "lightbulb.slash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(editBlockLevels.fixtures, id: \.fixtureId) { fixtureLevel in
                            cueBlockFixtureEditor(fixtureLevel)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }

            Divider()
            HStack {
                Button("Revert Changes") { editBlockLevels = block.levels }
                    .disabled(editBlockLevels == block.levels)
                Spacer()
                Button("Cancel") { editingBlock = nil }
                Button("Save") { saveBlockEdits(block) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 640)
    }

    private func cueBlockFixtureEditor(_ fixtureLevel: FixtureCueLevels) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundStyle(AuroraColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fixtureName(fixtureLevel.fixtureId))
                        .font(.subheadline.weight(.semibold))
                    Text("\(fixtureLevel.attributes.count + fixtureLevel.paletteRefs.count) attribute(s)")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                Spacer()
                Button(role: .destructive) {
                    editBlockLevels.fixtures.removeAll { $0.fixtureId == fixtureLevel.fixtureId }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this fixture from the Cue Block")
            }
            .padding(12)

            Divider()

            ForEach(fixtureLevel.attributes.keys.sorted(), id: \.self) { attribute in
                cueBlockAttributeEditor(fixtureID: fixtureLevel.fixtureId, attribute: attribute)
                Divider().padding(.leading, 12)
            }

            ForEach(fixtureLevel.paletteRefs.keys.sorted(), id: \.self) { attribute in
                cueBlockPaletteEditor(fixtureID: fixtureLevel.fixtureId, attribute: attribute)
                Divider().padding(.leading, 12)
            }
        }
        .background(AuroraColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AuroraColor.separator))
    }

    private func cueBlockAttributeEditor(fixtureID: UUID, attribute: String) -> some View {
        let value = cueBlockAttributeBinding(fixtureID: fixtureID, attribute: attribute)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(PaletteCreate.displayName(forAttribute: attribute))
                    .font(.subheadline)
                Text(attribute)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            .frame(width: 150, alignment: .leading)
            Slider(value: value, in: 0...1)
            TextField("Value", value: value, format: .percent.precision(.fractionLength(0...1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Button(role: .destructive) {
                removeCueBlockAttribute(fixtureID: fixtureID, attribute: attribute)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this attribute")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func cueBlockPaletteEditor(fixtureID: UUID, attribute: String) -> some View {
        let selection = cueBlockPaletteBinding(fixtureID: fixtureID, attribute: attribute)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(PaletteCreate.displayName(forAttribute: attribute))
                    .font(.subheadline)
                Text("Palette reference")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            .frame(width: 150, alignment: .leading)
            Picker("Palette", selection: selection) {
                ForEach(context.project.palettes) { palette in
                    Text(palette.name).tag(palette.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .destructive) {
                removeCueBlockPaletteReference(fixtureID: fixtureID, attribute: attribute)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this palette reference")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func editGroupSheet(_ group: CueBlockGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Cue Block Group")
                .font(.headline)
            TextField("Name", text: $editName)
            TextField("Notes", text: $editNotes, axis: .vertical)
                .lineLimit(2...5)
            Text("\(context.project.cueBlocks.filter { $0.cueBlockGroupID == group.id }.count) Cue Block(s)")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack {
                Spacer()
                Button("Cancel") { editingGroup = nil }
                Button("Save") { saveGroupEdits(group) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 410)
    }

    private func filteredBlocks(groupID: UUID?) -> [CueBlock] {
        context.project.cueBlocks.filter { block in
            guard block.cueBlockGroupID == groupID else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return block.name.localizedCaseInsensitiveContains(query)
                || block.type.displayName.localizedCaseInsensitiveContains(query)
                || block.levels.fixtures.contains { fixtureLevel in
                    context.project.fixtures.first(where: { $0.id == fixtureLevel.fixtureId })?.name
                        .localizedCaseInsensitiveContains(query) == true
                }
        }
    }

    private func prepareGroupCreation() {
        let source = selectedSourceFixtureGroup
        newGroupName = source?.name ?? "Group \(context.project.cueBlockGroups.count + 1)"
        showCreateGroup = true
    }

    private var selectedBlock: CueBlock? {
        selectedBlockID.flatMap { id in context.project.cueBlocks.first { $0.id == id } }
    }

    private var deleteBlockMessage: String {
        guard let block = pendingDeleteBlock else { return "" }
        let count = referenceCount(for: block.id)
        if count == 0 { return "This removes the Cue Block. This action can be undone." }
        return "This block is used by \(count) cue(s). Those cues will show a missing reference until the deletion is undone or the reference is removed."
    }

    private func referenceCount(for blockID: UUID) -> Int {
        context.project.cueLists.reduce(0) { total, list in
            total + list.cues.filter { cue in cue.cueBlockRefs.contains { $0.cueBlockID == blockID } }.count
        }
    }

    private func beginEditing(_ block: CueBlock) {
        editName = block.name
        editNotes = block.notes
        editBlockType = block.type
        editBlockGroupID = block.cueBlockGroupID
        editBlockLevels = block.levels
        editingBlock = block
    }

    private func fixtureName(_ fixtureID: UUID) -> String {
        context.project.fixtures.first(where: { $0.id == fixtureID })?.name ?? "Missing Fixture"
    }

    private func cueBlockAttributeBinding(fixtureID: UUID, attribute: String) -> Binding<Double> {
        Binding(
            get: {
                editBlockLevels.fixtures.first(where: { $0.fixtureId == fixtureID })?
                    .attributes[attribute] ?? 0
            },
            set: { newValue in
                guard let index = editBlockLevels.fixtures.firstIndex(where: { $0.fixtureId == fixtureID }) else { return }
                editBlockLevels.fixtures[index].attributes[attribute] = min(max(newValue, 0), 1)
            }
        )
    }

    private func cueBlockPaletteBinding(fixtureID: UUID, attribute: String) -> Binding<UUID> {
        Binding(
            get: {
                editBlockLevels.fixtures.first(where: { $0.fixtureId == fixtureID })?
                    .paletteRefs[attribute] ?? UUID()
            },
            set: { paletteID in
                guard let index = editBlockLevels.fixtures.firstIndex(where: { $0.fixtureId == fixtureID }) else { return }
                editBlockLevels.fixtures[index].paletteRefs[attribute] = paletteID
            }
        )
    }

    private func removeCueBlockAttribute(fixtureID: UUID, attribute: String) {
        guard let index = editBlockLevels.fixtures.firstIndex(where: { $0.fixtureId == fixtureID }) else { return }
        editBlockLevels.fixtures[index].attributes.removeValue(forKey: attribute)
        removeFixtureIfEmpty(at: index)
    }

    private func removeCueBlockPaletteReference(fixtureID: UUID, attribute: String) {
        guard let index = editBlockLevels.fixtures.firstIndex(where: { $0.fixtureId == fixtureID }) else { return }
        editBlockLevels.fixtures[index].paletteRefs.removeValue(forKey: attribute)
        removeFixtureIfEmpty(at: index)
    }

    private func removeFixtureIfEmpty(at index: Int) {
        guard editBlockLevels.fixtures.indices.contains(index) else { return }
        let fixture = editBlockLevels.fixtures[index]
        if fixture.attributes.isEmpty && fixture.paletteRefs.isEmpty {
            editBlockLevels.fixtures.remove(at: index)
        }
    }

    private var renameTitle: String {
        switch renameTarget {
        case .block: return "Rename Cue Block"
        case .group: return "Rename Cue Block Group"
        case .section: return "Rename Cue Block Section"
        case nil: return "Rename"
        }
    }

    private func beginRename(_ block: CueBlock) {
        renameDraft = block.name
        renameTarget = .block(block.id)
    }

    private func beginRename(_ group: CueBlockGroup) {
        renameDraft = group.name
        renameTarget = .group(group.id)
    }

    private func beginRenameSection(groupID: UUID, type: CueBlockType) {
        renameDraft = sectionName(groupID: groupID, type: type)
        renameTarget = .section(groupID: groupID, type: type)
    }

    private func sectionName(groupID: UUID?, type: CueBlockType) -> String {
        guard let groupID,
              let group = context.project.cueBlockGroup(id: groupID),
              let customName = group.sectionNames[type]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !customName.isEmpty
        else { return type.displayName }
        return customName
    }

    private func commitRename() {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let target = renameTarget else { return }
        switch target {
        case .block(let id):
            guard var block = context.project.cueBlock(id: id) else {
                statusText = "Cue Block could not be found"
                renameTarget = nil
                return
            }
            block.name = name
            perform(UpdateCueBlockCommand(cueBlock: block), success: "Renamed Cue Block to \(name)")
        case .group(let id):
            guard var group = context.project.cueBlockGroup(id: id) else {
                statusText = "Cue Block Group could not be found"
                renameTarget = nil
                return
            }
            group.name = name
            perform(UpdateCueBlockGroupCommand(group: group), success: "Renamed group to \(name)")
        case .section(let groupID, let type):
            guard var group = context.project.cueBlockGroup(id: groupID) else {
                statusText = "Cue Block Group could not be found"
                renameTarget = nil
                return
            }
            group.sectionNames[type] = name
            perform(
                UpdateCueBlockGroupCommand(group: group),
                success: "Renamed \(type.displayName) section to \(name)"
            )
        }
        renameTarget = nil
    }

    private func beginEditing(_ group: CueBlockGroup) {
        editName = group.name
        editNotes = group.notes
        editingGroup = group
    }

    private func saveBlockEdits(_ block: CueBlock) {
        var updated = block
        updated.name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.cueBlockGroupID = editBlockGroupID
        updated.levels = editBlockLevels
        perform(UpdateCueBlockCommand(cueBlock: updated), success: "Updated \(updated.name)")
        editingBlock = nil
    }

    private func saveGroupEdits(_ group: CueBlockGroup) {
        var updated = group
        updated.name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        perform(UpdateCueBlockGroupCommand(group: updated), success: "Updated \(updated.name)")
        editingGroup = nil
    }

    private func duplicate(_ block: CueBlock) {
        var copy = block
        copy.id = UUID()
        copy.name = uniqueCopyName(for: block.name)
        do {
            try context.session.perform(AddCueBlockCommand(cueBlock: copy))
            selectedBlockID = copy.id
            statusText = "Duplicated \(block.name)"
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func uniqueCopyName(for name: String) -> String {
        let names = Set(context.project.cueBlocks.map { $0.name.localizedLowercase })
        var candidate = "\(name) Copy"
        var suffix = 2
        while names.contains(candidate.localizedLowercase) {
            candidate = "\(name) Copy \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func updatePendingBlockValues() {
        guard let block = pendingValueUpdate else { return }
        defer { pendingValueUpdate = nil }
        let ordered = context.session.selection.snapshot.orderedFixtureIDs
        let result = CueBlockRecorder.record(.init(
            name: block.name,
            type: block.type,
            programmerValues: programmer.snapshot().values,
            selectedFixtureIDs: ordered,
            cueBlockGroupID: block.cueBlockGroupID,
            sourceGroupID: selectedSourceFixtureGroup?.id,
            capabilityMap: ProgrammerAttributePresentationResolver.capabilityMap(
                orderedFixtureIDs: ordered,
                project: context.project
            )
        ))
        guard var updated = result.cueBlock else {
            statusText = result.issues.first(where: { $0.severity == .error })?.message ?? "Unable to update Cue Block"
            return
        }
        updated.id = block.id
        updated.notes = block.notes
        perform(UpdateCueBlockCommand(cueBlock: updated), success: "Replaced values in \(block.name)")
    }

    private func perform(_ command: Command, success: String) {
        do {
            try context.session.perform(command)
            statusText = success
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func createGroup() {
        let source = selectedSourceFixtureGroup
        let group = CueBlockGroup(
            name: newGroupName.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceFixtureGroupID: source?.id
        )
        do {
            try context.session.perform(AddCueBlockGroupCommand(group: group))
            expandedGroups.insert(group.id)
            newBlockGroupID = group.id
            statusText = "Created group \(group.name)"
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func prepareBlockCreation(keepingGroup: Bool = false) {
        let source = selectedSourceFixtureGroup
        if !keepingGroup {
            newBlockGroupID = context.project.cueBlockGroups.first(where: {
                $0.sourceFixtureGroupID == source?.id
            })?.id ?? context.project.cueBlockGroups.first?.id
        }
        newBlockType = inferredType
        newBlockName = defaultBlockName(type: newBlockType)
        showCreateBlock = true
    }

    private func createBlock() {
        let ordered = context.session.selection.snapshot.orderedFixtureIDs
        let snapshot = programmer.snapshot()
        let result = CueBlockRecorder.record(.init(
            name: newBlockName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: newBlockType,
            programmerValues: snapshot.values,
            selectedFixtureIDs: ordered,
            cueBlockGroupID: newBlockGroupID,
            sourceGroupID: selectedSourceFixtureGroup?.id,
            capabilityMap: ProgrammerAttributePresentationResolver.capabilityMap(
                orderedFixtureIDs: ordered,
                project: context.project
            )
        ))
        guard let block = result.cueBlock else {
            statusText = result.issues.first(where: { $0.severity == .error })?.message ?? "Unable to create Cue Block"
            return
        }
        do {
            try context.session.perform(AddCueBlockCommand(cueBlock: block))
            selectedBlockID = block.id
            if let groupID = block.cueBlockGroupID { expandedGroups.insert(groupID) }
            expandedTypes.insert("\(block.cueBlockGroupID?.uuidString ?? "unfiled"):\(block.type.rawValue)")
            showCreateBlock = false
            let warnings = result.issues.filter { $0.severity == .warning }.count
            statusText = "Created \(block.name)" + (warnings > 0 ? " · \(warnings) warning(s)" : "")
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private var selectedSourceFixtureGroup: AuroraModel.Group? {
        guard let id = context.session.selection.snapshot.groupIDs.first else { return nil }
        return context.project.groups.first { $0.id == id }
    }

    private var inferredType: CueBlockType {
        let values = programmer.snapshot().values
        let selected = context.session.selection.snapshot.orderedFixtureIDs
        var keys: [String] = []
        for fixtureID in selected {
            if let fixtureValues = values[fixtureID] {
                keys.append(contentsOf: fixtureValues.keys)
            }
        }
        for type in [CueBlockType.color, .intensity, .position, .beam, .gobo] {
            if keys.contains(where: { CueBlockAttributeFamily.isAllowed($0, for: type) }) { return type }
        }
        return .general
    }

    private func defaultBlockName(type: CueBlockType) -> String {
        let count = context.project.cueBlocks.filter { $0.type == type }.count + 1
        return "\(type.displayName) \(count)"
    }

    private var commandModifierIsPressed: Bool {
#if canImport(AppKit)
        NSEvent.modifierFlags.contains(.command)
#else
        false
#endif
    }

    private func resolvedProgrammerBatch(for block: CueBlock) -> (values: [UUID: [String: Double]], issueCount: Int) {
        let result = CueBlockResolver.resolveBlockForRecall(cueBlock: block, project: context.project)
        var batch: [UUID: [String: Double]] = [:]
        for fixture in result.levels.fixtures where !fixture.attributes.isEmpty {
            batch[fixture.fixtureId, default: [:]].merge(fixture.attributes) { _, latest in latest }
        }
        return (batch, result.issues.count)
    }

    private func activate(_ block: CueBlock, additive: Bool) {
        if additive, activeBlockIDs.contains(block.id) {
            activeBlockIDs.removeAll { $0 == block.id }
            applyActiveCueBlocks(status: "Deactivated \(block.name)")
            return
        }

        let resolved = resolvedProgrammerBatch(for: block)
        guard !resolved.values.isEmpty else {
            statusText = "\(block.name) has no applicable values"
            return
        }

        if activeBlockIDs.isEmpty {
            programmerValuesBeforeCueBlocks = programmer.snapshot().values
        }
        if additive {
            activeBlockIDs.append(block.id)
        } else {
            activeBlockIDs = [block.id]
        }
        selectedBlockID = block.id
        applyActiveCueBlocks(
            status: additive
                ? "Activated \(block.name) with \(activeBlockIDs.count) Cue Blocks"
                : "Activated \(block.name)"
        )
    }

    private func applyActiveCueBlocks(status: String) {
        let baseline = programmerValuesBeforeCueBlocks ?? programmer.snapshot().values
        programmer.clearAll()
        programmer.setMany(baseline)

        var totals: [CueBlockType: [UUID: [String: (sum: Double, count: Int)]]] = [:]
        var colorSamples: [UUID: [AuroraEngine.RGBColor]] = [:]
        var typeOrder: [CueBlockType] = []
        var issueCount = 0
        for blockID in activeBlockIDs {
            guard let block = context.project.cueBlock(id: blockID) else { continue }
            let resolved = resolvedProgrammerBatch(for: block)
            issueCount += resolved.issueCount
            typeOrder.removeAll { $0 == block.type }
            typeOrder.append(block.type)
            for (fixtureID, attributes) in resolved.values {
                if block.type == .color, let rgb = cueBlockRGB(from: attributes) {
                    colorSamples[fixtureID, default: []].append(rgb)
                }
                for (attribute, value) in attributes {
                    let existing = totals[block.type]?[fixtureID]?[attribute] ?? (sum: 0, count: 0)
                    totals[block.type, default: [:]][fixtureID, default: [:]][attribute] = (
                        sum: existing.sum + value,
                        count: existing.count + 1
                    )
                }
            }
        }

        // Blocks of the same semantic type blend instead of competing. Types are
        // applied in most-recent activation order so distinct families still compose.
        for type in typeOrder {
            var averaged: [UUID: [String: Double]] = [:]
            for (fixtureID, attributes) in totals[type] ?? [:] {
                for (attribute, total) in attributes where total.count > 0 {
                    averaged[fixtureID, default: [:]][attribute] = total.sum / Double(total.count)
                }
            }
            if type == .color {
                for (fixtureID, samples) in colorSamples where !samples.isEmpty {
                    let count = Double(samples.count)
                    let red = samples.reduce(0.0) { $0 + $1.r } / count
                    let green = samples.reduce(0.0) { $0 + $1.g } / count
                    let blue = samples.reduce(0.0) { $0 + $1.b } / count
                    let rgb = AuroraEngine.RGBColor(r: red, g: green, b: blue)
                    let hsv = ColorMath.hsv(from: rgb)
                    averaged[fixtureID, default: [:]]["colorR"] = rgb.r
                    averaged[fixtureID, default: [:]]["colorG"] = rgb.g
                    averaged[fixtureID, default: [:]]["colorB"] = rgb.b
                    averaged[fixtureID, default: [:]][ColorAuthoringAttribute.hue] = hsv.h
                    averaged[fixtureID, default: [:]][ColorAuthoringAttribute.saturation] = hsv.s
                    averaged[fixtureID, default: [:]][ColorAuthoringAttribute.brightness] = hsv.v
                }
            }
            programmer.setMany(averaged)
        }

        if activeBlockIDs.isEmpty {
            programmerValuesBeforeCueBlocks = nil
        }
        statusText = status + (issueCount == 0 ? "" : " · \(issueCount) issue(s)")
        onProgrammerChanged()
    }

    /// Resolve either physical RGB or Color Engine authoring values into a common
    /// mixing space. RGB wins when both representations are present because it
    /// already includes the Color Engine's white-balance transform.
    private func cueBlockRGB(from attributes: [String: Double]) -> AuroraEngine.RGBColor? {
        CueBlockColorPreview.rgb(from: attributes)
    }

    private func addToSelectedCue(_ block: CueBlock) {
        let targets = context.project.targetCuesForPaletteRecord(
            selectedCueIDs: context.session.selection.snapshot.cueIDs
        )
        guard !targets.isEmpty else {
            statusText = "Select or create a cue first"
            return
        }
        do {
            try context.session.beginGroup(named: "Add Cue Block to Cue")
            for target in targets {
                try context.session.perform(AddCueBlockReferenceCommand(
                    listID: target.listID,
                    cueID: target.cue.id,
                    cueBlockID: block.id
                ))
            }
            try context.session.endGroup()
            statusText = "Added \(block.name) to \(targets.count) cue(s)"
            onProjectChanged()
        } catch {
            try? context.session.cancelGroup()
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func move(_ block: CueBlock, to groupID: UUID?) {
        do {
            try context.session.perform(MoveCueBlockToGroupCommand(
                cueBlockID: block.id,
                destinationGroupID: groupID
            ))
            statusText = "Moved \(block.name)"
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func deletePendingBlock() {
        guard let block = pendingDeleteBlock else { return }
        do {
            try context.session.perform(RemoveCueBlockCommand(cueBlockID: block.id))
            if selectedBlockID == block.id { selectedBlockID = nil }
            if activeBlockIDs.contains(block.id) {
                activeBlockIDs.removeAll { $0 == block.id }
                applyActiveCueBlocks(status: "Deleted \(block.name)")
            } else {
                statusText = "Deleted \(block.name)"
            }
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
        pendingDeleteBlock = nil
    }

    private func deletePendingGroup() {
        guard let group = pendingDeleteGroup else { return }
        do {
            try context.session.perform(RemoveCueBlockGroupCommand(groupID: group.id))
            expandedGroups.remove(group.id)
            statusText = "Deleted \(group.name) · blocks moved to Unfiled"
            onProjectChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
        pendingDeleteGroup = nil
    }

    private func representativeColor(_ block: CueBlock) -> Color? {
        let resolved = CueBlockResolver.resolveBlockForRecall(cueBlock: block, project: context.project)
        let samples = resolved.levels.fixtures.compactMap { cueBlockRGB(from: $0.attributes) }
        guard !samples.isEmpty else { return nil }
        let count = Double(samples.count)
        let red = samples.reduce(0.0) { $0 + $1.r } / count
        let green = samples.reduce(0.0) { $0 + $1.g } / count
        let blue = samples.reduce(0.0) { $0 + $1.b } / count
        return Color(red: red, green: green, blue: blue)
    }
}

/// Pure color resolution shared by cue-block rows and regression tests.
public enum CueBlockColorPreview {
    public static func rgb(from attributes: [String: Double]) -> AuroraEngine.RGBColor? {
        if let red = attributes["colorR"],
           let green = attributes["colorG"],
           let blue = attributes["colorB"] {
            return AuroraEngine.RGBColor(r: red, g: green, b: blue)
        }
        // Pixel fixtures store color per control element. Average complete RGB
        // samples so cue-block swatches represent the authored strip color.
        let suffixes = Set(attributes.keys.compactMap { key -> String? in
            guard key.hasPrefix("colorR@") else { return nil }
            return String(key.dropFirst("colorR".count))
        })
        let elementSamples = suffixes.compactMap { suffix -> AuroraEngine.RGBColor? in
            guard let red = attributes["colorR\(suffix)"],
                  let green = attributes["colorG\(suffix)"],
                  let blue = attributes["colorB\(suffix)"]
            else { return nil }
            return AuroraEngine.RGBColor(r: red, g: green, b: blue)
        }
        if !elementSamples.isEmpty {
            let count = Double(elementSamples.count)
            return AuroraEngine.RGBColor(
                r: elementSamples.reduce(0) { $0 + $1.r } / count,
                g: elementSamples.reduce(0) { $0 + $1.g } / count,
                b: elementSamples.reduce(0) { $0 + $1.b } / count
            )
        }
        guard let hue = attributes[ColorAuthoringAttribute.hue] else { return nil }
        return ColorMath.resolvedRGB(
            hue: hue,
            saturation: attributes[ColorAuthoringAttribute.saturation] ?? 1,
            brightness: attributes[ColorAuthoringAttribute.brightness] ?? 1,
            whiteBalance: attributes[ColorAuthoringAttribute.whiteBalance] ?? 0
        )
    }
}

private enum CueBlockRenameTarget: Equatable {
    case block(UUID)
    case group(UUID)
    case section(groupID: UUID, type: CueBlockType)
}

private extension CueBlockType {
    var displayName: String {
        switch self {
        case .intensity: return "Dimmer"
        case .color: return "Color"
        case .position: return "Position"
        case .beam: return "Beam"
        case .gobo: return "Gobo"
        case .general: return "General"
        }
    }

    var folderSymbol: String {
        switch self {
        case .intensity: return "sun.max"
        case .color: return "paintpalette"
        case .position: return "scope"
        case .beam: return "light.beacon.max"
        case .gobo: return "circle.hexagongrid"
        case .general: return "square.stack.3d.up"
        }
    }

    var blockSymbol: String {
        switch self {
        case .intensity: return "sun.max.fill"
        case .color: return "circle.fill"
        case .position: return "scope"
        case .beam: return "light.beacon.max.fill"
        case .gobo: return "circle.hexagongrid.fill"
        case .general: return "square.stack.3d.up.fill"
        }
    }
}
