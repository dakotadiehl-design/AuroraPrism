import AuroraDesignSystem
import AuroraCore
import AuroraDiagnostics
import AuroraModel
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Optional seed for visual QA / Checkpoint B screenshot export (production path uses defaults).
public struct PatchWorkspaceSeed: Sendable {
    public var listMode: Bool
    public var quantity: Int
    public var namePrefix: String?
    public var selectedDefinitionID: UUID?
    public var selectedUniverseID: UUID?
    public var selectedFixtureIDs: Set<UUID>
    /// Precomputed ghost (exporter / tests). Prefer over ghostStartAddress when available.
    public var ghostPlan: PatchBatchPlan?
    /// When set without ghostPlan, planner builds a ghost on first appear.
    public var ghostStartAddress: UInt16?

    public init(
        listMode: Bool = false,
        quantity: Int = 1,
        namePrefix: String? = nil,
        selectedDefinitionID: UUID? = nil,
        selectedUniverseID: UUID? = nil,
        selectedFixtureIDs: Set<UUID> = [],
        ghostPlan: PatchBatchPlan? = nil,
        ghostStartAddress: UInt16? = nil
    ) {
        self.listMode = listMode
        self.quantity = quantity
        self.namePrefix = namePrefix
        self.selectedDefinitionID = selectedDefinitionID
        self.selectedUniverseID = selectedUniverseID
        self.selectedFixtureIDs = selectedFixtureIDs
        self.ghostPlan = ghostPlan
        self.ghostStartAddress = ghostStartAddress
    }
}

/// Checkpoint B — production Patch workspace.
/// Fixture blocks are the hero; DMX addresses are the coordinate system.
public struct PatchWorkspaceView: View {
    public var context: WorkspacePanelContext
    public var onChanged: () -> Void
    public var seed: PatchWorkspaceSeed?

    @State private var viewMode: ViewMode
    @State private var selectedUniverseID: UUID?
    @State private var selectedDefinitionID: UUID?
    @State private var quantity: Int
    @State private var namePrefix: String
    @State private var searchText: String = ""
    @State private var statusText: String?
    @State private var clickToPatchArmed = false
    @State private var ghostPlan: PatchBatchPlan?
    @State private var hoverAddress: UInt16?
    @State private var dragRepatchID: UUID?
    @State private var dragRepatchAddress: UInt16?
    @State private var dragRepatchIsValid = false
    @State private var didApplySeed = false
    @State private var repatchSheetFixtureID: UUID?
    @State private var repatchAddressText: String = ""
    @State private var confirmDeleteIDs: [UUID] = []
    @State private var showDeleteConfirm = false
    @State private var renameFixtureID: UUID?
    @State private var renameDraft = ""
    @State private var renameError: PrismErrorReport?
    @State private var pendingRemoveDefinitions: [FixtureDefinition] = []
    @State private var pendingRemoveIsProfile = false
    @State private var pendingRemovalIsProjectOnly = false

    private let channelsPerRow = DMXUniverseGridLayout.channelsPerRowDefault

    private enum ViewMode: String, CaseIterable {
        case grid = "Universe"
        case list = "List"
    }

    public init(
        context: WorkspacePanelContext,
        onChanged: @escaping () -> Void = {},
        seed: PatchWorkspaceSeed? = nil
    ) {
        self.context = context
        self.onChanged = onChanged
        self.seed = seed
        // Synchronous seed → @State so ImageRenderer / NSHostingView bitmaps see correct mode.
        _viewMode = State(initialValue: (seed?.listMode == true) ? .list : .grid)
        _quantity = State(initialValue: max(1, min(64, seed?.quantity ?? 1)))
        _namePrefix = State(initialValue: seed?.namePrefix ?? "Fix")
        _selectedUniverseID = State(initialValue: seed?.selectedUniverseID)
        _selectedDefinitionID = State(initialValue: seed?.selectedDefinitionID)
        _ghostPlan = State(initialValue: seed?.ghostPlan)
        if let ids = seed?.selectedFixtureIDs, !ids.isEmpty {
            context.session.selectFixtures(ids, extending: false)
        }
    }

    // MARK: - Project helpers

    private var universes: [Universe] {
        context.project.universes.sorted { $0.number < $1.number }
    }

    private var selectedUniverse: Universe? {
        if let selectedUniverseID {
            return universes.first { $0.id == selectedUniverseID }
        }
        return universes.first
    }

    private var definitions: [FixtureDefinition] {
        var list = context.project.fixtureDefinitions
        if let box = context.fixtureLibrary {
            let existing = Set(list.map(\.id))
            for d in box.definitions where !existing.contains(d.id) {
                list.append(d)
            }
        }
        return list.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var selectedDefinition: FixtureDefinition? {
        if let selectedDefinitionID {
            return definitions.first { $0.id == selectedDefinitionID }
                ?? context.project.definition(id: selectedDefinitionID)
        }
        return nil
    }

    private var footprint: UInt16 {
        guard let d = selectedDefinition else { return 1 }
        return max(d.channelCount, d.calculatedFootprint)
    }

    private var fixturesInUniverse: [PatchedFixture] {
        guard let uid = selectedUniverse?.id else { return [] }
        return context.project.fixtures
            .filter { $0.universeId == uid && $0.isPatched }
            .sorted { $0.address < $1.address }
    }

    private var unpatchedFixtures: [PatchedFixture] {
        context.project.unpatchedFixtures.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedFixtureIDs: [UUID] {
        context.session.selection.snapshot.orderedFixtureIDs
    }

    private var channelCount: Int {
        Int(selectedUniverse?.channelCount ?? 512)
    }

    private var rowCount: Int {
        Int(ceil(Double(channelCount) / Double(channelsPerRow)))
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            if viewMode == .list {
                PatchPanel(context: context)
            } else {
                HStack(spacing: 0) {
                    libraryPane
                        .frame(width: 248)
                    Divider().overlay(AuroraColor.separator)
                    VStack(spacing: 0) {
                        prepStrip
                        Divider().overlay(AuroraColor.separator)
                        universeCanvas
                    }
                }
            }
            if statusText != nil {
                statusFooter
            }
        }
        .background(AuroraColor.surfacePanel)
        .focusable()
        .onExitCommand(perform: cancelPatchOperation)
        .onKeyPress(.delete) { handleDeleteKeyPress() }
        .onKeyPress(.deleteForward) { handleDeleteKeyPress() }
        .onAppear {
            applySeedIfNeeded()
            if selectedUniverseID == nil {
                selectedUniverseID = universes.first?.id
            }
            if let d = selectedDefinition, namePrefix == "Fix" {
                namePrefix = shortPrefix(for: d)
            }
        }
        .sheet(item: $repatchSheetFixtureID) { id in
            repatchSheet(fixtureID: id)
        }
        .alert("Rename Fixture", isPresented: Binding(
            get: { renameFixtureID != nil },
            set: { if !$0 { renameFixtureID = nil } }
        )) {
            TextField("Fixture name", text: $renameDraft)
            Button("Rename") { commitFixtureRename() }
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { renameFixtureID = nil }
        } message: {
            Text("This name is used throughout Patch, Stage, Groups, Programmer, and Cue Blocks.")
        }
        .prismErrorAlert(item: $renameError)
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Fixture\(confirmDeleteIDs.count > 1 ? "s" : "")", role: .destructive) {
                performDeleteFixtures(confirmDeleteIDs)
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteIDs = []
            }
        } message: {
            Text(deleteConfirmMessage)
        }
        .confirmationDialog(
            pendingRemovalIsProjectOnly
                ? (pendingRemoveIsProfile ? "Remove Fixture Profile from Project?" : "Remove Fixture Mode from Project?")
                : (pendingRemoveIsProfile ? "Remove Imported Fixture Profile?" : "Remove Imported Fixture Mode?"),
            isPresented: Binding(
                get: { !pendingRemoveDefinitions.isEmpty },
                set: { if !$0 { resetPendingDefinitionRemoval() } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingRemoveIsProfile ? "Remove Entire Profile" : "Remove Mode", role: .destructive) {
                removePendingFixtureDefinitions()
            }
            Button("Cancel", role: .cancel) { resetPendingDefinitionRemoval() }
        } message: {
            if let definition = pendingRemoveDefinitions.first {
                if pendingRemovalIsProjectOnly && pendingRemoveIsProfile {
                    Text("Remove \(definition.manufacturer) \(definition.model) and all unused embedded modes from this project? This does not affect your User Library.")
                } else if pendingRemovalIsProjectOnly {
                    Text("Remove \(definition.manufacturer) \(definition.model) — \(definition.modeName) from this project? This does not affect your User Library.")
                } else if pendingRemoveIsProfile {
                    Text("Remove \(definition.manufacturer) \(definition.model) and all \(pendingRemoveDefinitions.count) modes from your User Library? Existing projects keep their embedded copies.")
                } else {
                    Text("Remove \(definition.manufacturer) \(definition.model) — \(definition.modeName) from your User Library? Existing projects keep their embedded copies.")
                }
            }
        }
    }

    private var deleteConfirmTitle: String {
        let n = confirmDeleteIDs.count
        return n <= 1 ? "Delete Fixture?" : "Delete \(n) Fixtures?"
    }

    private var deleteConfirmMessage: String {
        let summary = FixtureReferenceIndex.summarize(
            fixtureIDs: Set(confirmDeleteIDs),
            in: context.project
        )
        let base = "This permanently removes the fixture\(confirmDeleteIDs.count == 1 ? "" : "s") from the show."
        return base + "\n\n" + summary.confirmationDetail
    }

    private func handleDeleteKeyPress() -> KeyPress.Result {
        let action = PatchFixtureLifecycle.deleteKeyAction(
            isTextEditing: AuroraKeyboardGate.isTextEditingActive,
            selectedFixtureIDs: selectedFixtureIDs,
            project: context.project
        )
        switch action {
        case .unpatch(let ids):
            performUnpatch(ids)
            return .handled
        case .ignore:
            return .ignored
        }
    }

    private func applySeedIfNeeded() {
        guard let seed, !didApplySeed else { return }
        didApplySeed = true
        // Most fields applied in init; only deferred planner ghost remains.
        if ghostPlan == nil, let start = seed.ghostStartAddress {
            updateGhost(at: start)
        } else if let plan = ghostPlan {
            if plan.isValid {
                let last = plan.starts.last.map { $0 + plan.footprint - 1 } ?? plan.startAddress
                statusText = "Preview \(plan.starts.count)× \(plan.footprint)ch · \(plan.starts.first ?? plan.startAddress)–\(last)"
            } else {
                statusText = plan.rejectionReason ?? "Invalid placement"
            }
        }
    }

    private var statusFooter: some View {
        Text(statusText ?? "")
            .font(AuroraTypography.metadata)
            .foregroundStyle(isErrorStatus ? AuroraColor.warning : AuroraColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AuroraColor.surfaceHeader)
    }

    private var isErrorStatus: Bool {
        let s = (statusText ?? "").lowercased()
        return s.contains("overlap") || s.contains("past") || s.contains("invalid")
            || s.contains("missing") || s.contains("!") || s.contains("failed")
    }

    // MARK: - Top bar (secondary chrome)

    private var topBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            Text(routeLabel)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)

            Spacer()

            Menu("Tools") {
                Button("Add Universe") { addUniverse() }
                Divider()
                Button("Copy Patch Report") { copyReport(csv: false) }
                Button("Copy CSV") { copyReport(csv: true) }
                Divider()
                Text("Renumber / bulk / import live in List view")
                    .font(.caption)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AuroraColor.surfaceHeader)
    }

    private var routeLabel: String {
        guard let u = selectedUniverse else { return "" }
        return "\(u.protocolHint.rawValue) · \(fixturesInUniverse.count) patched · \(channelCount) ch"
    }

    // MARK: - Library cards

    private var libraryPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FIXTURE LIBRARY")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

            AuroraSearchField(text: $searchText, placeholder: "Search…")
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedManufacturers, id: \.0) { mfr, defs in
                        Text(mfr.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AuroraColor.textTertiary)
                            .tracking(0.8)
                            .padding(.horizontal, 10)
                            .padding(.top, 4)

                        ForEach(defs) { def in
                            profileCard(def)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { clearLibrarySelection() }
                .padding(.bottom, 12)
            }

            if !unpatchedFixtures.isEmpty {
                Divider().overlay(AuroraColor.separator)
                unpatchedTray
            }
        }
        .background(AuroraColor.surfacePanel)
    }

    /// Discoverable unpatched fixtures (identity preserved; ready for repatch).
    private var unpatchedTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNPATCHED (\(unpatchedFixtures.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AuroraColor.warning)
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(unpatchedFixtures) { fx in
                        unpatchedRow(fx)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 140)
        }
    }

    private func unpatchedRow(_ fx: PatchedFixture) -> some View {
        let selected = context.session.selection.snapshot.fixtureIDs.contains(fx.id)
        let def = context.project.definition(id: fx.definitionId)
        return Button {
            let extend = NSEvent.modifierFlags.contains(.command)
                || NSEvent.modifierFlags.contains(.shift)
            context.session.selectFixtures(Set([fx.id]), extending: extend)
            onChanged()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraColor.warning)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fx.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AuroraColor.textPrimary)
                        .lineLimit(1)
                    Text(def?.model ?? "—")
                        .font(.system(size: 10))
                        .foregroundStyle(AuroraColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? AuroraColor.surfaceSelected : AuroraColor.surfaceRaised.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .contextMenu { fixtureContextMenu(primaryIDs: [fx.id]) }
        .onDrag {
            context.session.selectFixtures(Set([fx.id]), extending: false)
            return NSItemProvider(object: "aurora.fixture.\(fx.id.uuidString)" as NSString)
        }
        .help("Unpatched — drag to universe or use Repatch…")
    }

    private var groupedManufacturers: [(String, [FixtureProfileFamily])] {
        let families = Dictionary(grouping: definitions) { definition in
            normalizedFixtureFamilyKey(definition)
        }.values.compactMap { modes -> FixtureProfileFamily? in
            guard let first = modes.first else { return nil }
            let sortedModes = modes.sorted {
                let comparison = $0.modeName.localizedStandardCompare($1.modeName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty && !sortedModes.contains(where: {
                $0.manufacturer.localizedCaseInsensitiveContains(query)
                    || $0.model.localizedCaseInsensitiveContains(query)
                    || $0.modeName.localizedCaseInsensitiveContains(query)
            }) { return nil }
            return FixtureProfileFamily(
                id: normalizedFixtureFamilyKey(first),
                manufacturer: first.manufacturer.isEmpty ? "Generic" : first.manufacturer,
                model: first.model,
                modes: sortedModes
            )
        }
        let grouped = Dictionary(grouping: families, by: \.manufacturer)
        return grouped.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { manufacturer in
            let orderedFamilies = (grouped[manufacturer] ?? []).sorted {
                let comparison = $0.model.localizedStandardCompare($1.model)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return $0.id < $1.id
            }
            return (manufacturer, orderedFamilies)
        }
    }

    private func profileCard(_ family: FixtureProfileFamily) -> some View {
        let def = family.modes.first(where: { $0.id == selectedDefinitionID }) ?? family.modes[0]
        let selected = selectedDefinitionID == def.id
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                if selectedDefinitionID == def.id {
                    clearLibrarySelection()
                } else {
                    selectDefinition(def)
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? AuroraColor.accent.opacity(0.25) : AuroraColor.surfaceWell)
                            .frame(width: 36, height: 36)
                        Image(systemName: iconName(for: def))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selected ? AuroraColor.accentBright : AuroraColor.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.model)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AuroraColor.textPrimary)
                            .lineLimit(1)
                        Text(family.manufacturer)
                            .font(.system(size: 11))
                            .foregroundStyle(AuroraColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Text("Mode")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                Picker("Mode", selection: Binding(
                    get: { def.id },
                    set: { id in
                        if let mode = family.modes.first(where: { $0.id == id }) {
                            selectDefinition(mode)
                        }
                    }
                )) {
                    ForEach(family.modes) { mode in
                        let footprint = max(mode.channelCount, mode.calculatedFootprint)
                        Text("\(mode.modeName) (\(footprint) ch)").tag(mode.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? AuroraColor.surfaceSelected : AuroraColor.surfaceRaised.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? AuroraColor.accent.opacity(0.85) : AuroraColor.separatorStrong, lineWidth: selected ? 1.5 : 0.5))
        .contextMenu {
            if isImportedDefinition(def) {
                Button("Remove Imported Mode…", role: .destructive) {
                    pendingRemoveDefinitions = [def]
                    pendingRemoveIsProfile = false
                    pendingRemovalIsProjectOnly = false
                }
            }
            let importedModes = family.modes.filter(isImportedDefinition)
            if !importedModes.isEmpty {
                Divider()
                Button(
                    importedModes.count == family.modes.count
                        ? "Remove Entire Fixture Profile…"
                        : "Remove All Imported Modes…",
                    role: .destructive
                ) {
                    pendingRemoveDefinitions = importedModes
                    pendingRemoveIsProfile = true
                    pendingRemovalIsProjectOnly = false
                }
            }
            let projectOnlyModes = family.modes.filter(isProjectOnlyDefinition)
            if isProjectOnlyDefinition(def) {
                Divider()
                Button("Remove Mode from Project…", role: .destructive) {
                    pendingRemoveDefinitions = [def]
                    pendingRemoveIsProfile = false
                    pendingRemovalIsProjectOnly = true
                }
                .disabled(isDefinitionInUse(def.id))
            }
            if !projectOnlyModes.isEmpty {
                Button("Remove Entire Profile from Project…", role: .destructive) {
                    pendingRemoveDefinitions = projectOnlyModes
                    pendingRemoveIsProfile = true
                    pendingRemovalIsProjectOnly = true
                }
                .disabled(projectOnlyModes.contains { isDefinitionInUse($0.id) })
            }
            if importedModes.isEmpty && projectOnlyModes.isEmpty {
                Text("Built-in mode")
            }
        }
        .onDrag {
            selectDefinition(def)
            return NSItemProvider(object: "aurora.def.\(def.id.uuidString)" as NSString)
        }
    }

    private func normalizedFixtureFamilyKey(_ definition: FixtureDefinition) -> String {
        [definition.manufacturer, definition.model]
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .lowercased()
            }
            .joined(separator: "\u{1f}")
    }

    private func selectDefinition(_ definition: FixtureDefinition) {
        selectedDefinitionID = definition.id
        namePrefix = shortPrefix(for: definition)
        ghostPlan = nil
        _ = try? ensureDefinitionEmbedded(definition)
        if clickToPatchArmed {
            statusText = "PATCH armed — click a free DMX address"
        }
    }

    private func clearLibrarySelection() {
        selectedDefinitionID = nil
        ghostPlan = nil
        clickToPatchArmed = false
        statusText = nil
    }

    private func isImportedDefinition(_ definition: FixtureDefinition) -> Bool {
        context.fixtureLibrary?.userDefinitionIDs.contains(definition.id) == true
    }

    private func isProjectOnlyDefinition(_ definition: FixtureDefinition) -> Bool {
        context.project.fixtureDefinitions.contains(where: { $0.id == definition.id })
            && context.fixtureLibrary?.builtInDefinitionIDs.contains(definition.id) != true
            && context.fixtureLibrary?.userDefinitionIDs.contains(definition.id) != true
    }

    private func isDefinitionInUse(_ definitionID: UUID) -> Bool {
        context.project.fixtures.contains { $0.definitionId == definitionID }
    }

    private func resetPendingDefinitionRemoval() {
        pendingRemoveDefinitions = []
        pendingRemoveIsProfile = false
        pendingRemovalIsProjectOnly = false
    }

    private func removePendingFixtureDefinitions() {
        let definitionsToRemove = pendingRemoveDefinitions
        guard let first = definitionsToRemove.first else { return }
        let removingProfile = pendingRemoveIsProfile
        let removingFromProject = pendingRemovalIsProjectOnly
        defer { resetPendingDefinitionRemoval() }
        do {
            if removingFromProject {
                try context.session.beginGroup(named: removingProfile ? "Remove Fixture Profile from Project" : "Remove Fixture Mode from Project")
                for definition in definitionsToRemove {
                    try context.session.perform(RemoveFixtureDefinitionCommand(definitionID: definition.id))
                }
                try context.session.endGroup()
            } else {
                try context.fixtureLibrary?.removeUserDefinitions(Set(definitionsToRemove.map(\.id)))
            }
            let removedIDs = Set(definitionsToRemove.map(\.id))
            if let selectedDefinitionID,
               removedIDs.contains(selectedDefinitionID),
               !context.project.fixtureDefinitions.contains(where: { $0.id == selectedDefinitionID }) {
                self.selectedDefinitionID = definitions.first(where: { !removedIDs.contains($0.id) })?.id
            }
            statusText = (removingProfile
                ? "Removed \(first.model) fixture profile"
                : "Removed \(first.model) — \(first.modeName)")
                + (removingFromProject ? " from project" : " from User Library")
            onChanged()
        } catch {
            if removingFromProject { try? context.session.cancelGroup() }
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func iconName(for def: FixtureDefinition) -> String {
        let c = def.category.lowercased()
        if c.contains("head") || c.contains("spot") || c.contains("mover") { return "rotate.3d" }
        if c.contains("bar") || c.contains("pixel") { return "rectangle.split.3x1" }
        if c.contains("strobe") { return "bolt.fill" }
        if c.contains("fog") || c.contains("haze") { return "cloud.fill" }
        if c.contains("wash") || c.contains("par") { return "light.max" }
        return "lightbulb.fill"
    }

    private func shortPrefix(for def: FixtureDefinition) -> String {
        let base = def.model.replacingOccurrences(of: " ", with: "")
        return String(base.prefix(6))
    }

    // MARK: - Prep strip

    private var prepStrip: some View {
        HStack(spacing: 14) {
            if let def = selectedDefinition {
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Mode \(def.modeName) · Footprint \(footprint) ch")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .frame(minWidth: 160, alignment: .leading)
            } else {
                Text("Select a fixture profile")
                    .foregroundStyle(AuroraColor.textTertiary)
            }

            Divider().frame(height: 22)

            HStack(spacing: 6) {
                Text("Qty")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                Stepper(value: $quantity, in: 1...64) {
                    Text("\(quantity)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 28)
                }
            }

            HStack(spacing: 6) {
                Text("Prefix")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                TextField("Name", text: $namePrefix)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AuroraColor.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(AuroraColor.surfaceWell)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(AuroraColor.separatorStrong, lineWidth: 1)
                    )
            }

            Spacer(minLength: 8)

            Button {
                armClickToPatch()
            } label: {
                Text(clickToPatchArmed ? "Click Address…" : "PATCH")
                    .font(.system(size: 12, weight: .bold))
                    .frame(minWidth: 100)
            }
            .buttonStyle(AuroraButtonStyle(kind: .primary))
            .tint(clickToPatchArmed ? AuroraColor.warning : AuroraColor.accent)
            .controlSize(.regular)
            .disabled(selectedDefinition == nil || selectedUniverse == nil)

            Button("NEXT FREE") { patchNextFree() }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(AuroraButtonStyle(kind: .secondary))
                .controlSize(.regular)
                .disabled(selectedDefinition == nil || selectedUniverse == nil)

            if clickToPatchArmed {
                Button("Cancel") {
                    cancelPatchOperation()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AuroraColor.surfaceHeader)
    }

    // MARK: - Universe canvas (fills available space)

    private var universeCanvas: some View {
        VStack(spacing: 0) {
            universeTabs
            Divider().overlay(AuroraColor.separator)
            GeometryReader { geo in
                let metrics = layoutMetrics(in: geo.size)
                ScrollView([.vertical]) {
                    ZStack(alignment: .topLeading) {
                    // 1. Quiet DMX coordinate system (underlying grid)
                    coordinateBackground(metrics: metrics)
                    coordinateLabels(metrics: metrics)

                    // 2. Free-space hit targets (under fixture blocks)
                    freeSpaceHitLayer(metrics: metrics)

                    // 3. Fixture blocks — dominant objects
                    ForEach(fixturesInUniverse) { fx in
                        fixtureBlockViews(fx: fx, metrics: metrics)
                    }

                    // The real fixture remains at its committed address until drop. This
                    // purple ghost previews the proposed repatch destination while dragging.
                    if let fixtureID = dragRepatchID,
                       let address = dragRepatchAddress,
                       let fixture = fixturesInUniverse.first(where: { $0.id == fixtureID }) {
                        ghostBlockViews(
                            start: address,
                            footprint: context.project.channelCount(for: fixture),
                            label: fixture.name,
                            valid: dragRepatchIsValid,
                            metrics: metrics,
                            tint: AuroraColor.accentBright
                        )
                    }

                    // 4. Ghost batch (valid green / invalid red)
                    if let plan = ghostPlan {
                        ForEach(Array(ghostStarts(for: plan).enumerated()), id: \.offset) { i, start in
                            ghostBlockViews(
                                start: start,
                                footprint: max(plan.footprint, 1),
                                label: "\(plan.namePrefix) \(plan.nameStartNumber + i)",
                                valid: plan.isValid,
                                metrics: metrics
                            )
                        }
                    }
                    }
                    .frame(
                        width: metrics.totalWidth,
                        height: metrics.totalHeight,
                        alignment: .topLeading
                    )
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AuroraColor.surfaceWell)
                .onDrop(of: [.text], isTargeted: nil) { providers, location in
                    handleDefinitionDrop(providers, at: location, metrics: metrics)
                }
            }
        }
    }

    private var universeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(universes) { universe in
                    let isSelected = selectedUniverse?.id == universe.id
                    Button {
                        selectUniverse(universe.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Universe \(universe.number)")
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            Text(universe.name.isEmpty ? universe.protocolHint.rawValue : universe.name)
                                .font(.system(size: 9))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.72) : AuroraColor.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 112, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? Color.white : AuroraColor.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? AuroraColor.accent : Color.clear)
                    )
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Rectangle()
                                .fill(Color.white.opacity(0.75))
                                .frame(height: 2)
                                .padding(.horizontal, 8)
                        }
                    }
                    .accessibilityLabel("Universe \(universe.number)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                Button(action: addUniverse) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AuroraColor.textSecondary)
                .help("Add Universe")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(AuroraColor.surfaceHeader)
    }

    private func selectUniverse(_ id: UUID) {
        selectedUniverseID = id
        ghostPlan = nil
        hoverAddress = nil
        statusText = nil
    }

    private struct UniverseMetrics {
        var cellW: CGFloat
        var cellH: CGFloat
        var cols: Int
        var rows: Int
        var totalWidth: CGFloat { CGFloat(cols) * cellW }
        var totalHeight: CGFloat { CGFloat(rows) * cellH }
    }

    /// Stretch the universe across the full canvas — not a tiny floating spreadsheet.
    private func layoutMetrics(in size: CGSize) -> UniverseMetrics {
        let cols = channelsPerRow
        let rows = max(rowCount, 1)
        let usableW = max(size.width - 24, 400)
        let usableH = max(size.height - 24, 320)
        let cellW = floor(usableW / CGFloat(cols))
        // Prefer filling vertical space so 16 rows use the full hero region.
        let fillH = floor(usableH / CGFloat(rows))
        let cellH = max(36, min(68, max(fillH, cellW * 1.15)))
        return UniverseMetrics(cellW: cellW, cellH: cellH, cols: cols, rows: rows)
    }

    /// Every DMX address is a visible cell. Each tenth address is emphasized as a
    /// scanning landmark without competing with fixture blocks.
    private func coordinateBackground(metrics: UniverseMetrics) -> some View {
        Canvas { ctx, _ in
            let cols = metrics.cols
            let rows = metrics.rows
            let cw = metrics.cellW
            let ch = metrics.cellH
            let totalW = CGFloat(cols) * cw

            for row in 0..<rows {
                let y = CGFloat(row) * ch
                if row % 2 == 0 {
                    ctx.fill(
                        Path(CGRect(x: 0, y: y, width: totalW, height: ch)),
                        with: .color(Color.white.opacity(0.025))
                    )
                }
                for col in 0..<cols {
                    let address = row * cols + col + 1
                    guard address <= channelCount else { continue }
                    let rect = CGRect(x: CGFloat(col) * cw, y: y, width: cw, height: ch)
                    let tenth = address % 10 == 0
                    ctx.stroke(
                        Path(rect),
                        with: .color(Color.white.opacity(tenth ? 0.14 : 0.045)),
                        lineWidth: tenth ? 1.5 : 0.75
                    )
                }
            }
        }
        .frame(width: metrics.totalWidth, height: metrics.totalHeight)
        .allowsHitTesting(false)
    }

    /// Label all 512 addresses so an operator can patch without estimating a cell.
    private func coordinateLabels(metrics: UniverseMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...max(channelCount, 1), id: \.self) { addr in
                let zeroBased = addr - 1
                let row = zeroBased / metrics.cols
                let col = zeroBased % metrics.cols
                if addr <= channelCount {
                    Text(String(format: "%03d", addr))
                        .font(.system(size: 8, weight: addr % 10 == 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(addr % 10 == 0 ? 0.46 : 0.24))
                        .position(
                            x: CGFloat(col) * metrics.cellW + metrics.cellW * 0.5,
                            y: CGFloat(row) * metrics.cellH + metrics.cellH * 0.5
                        )
                }
            }
        }
        .frame(width: metrics.totalWidth, height: metrics.totalHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Full-canvas gesture for free addresses and PATCH-click placement.
    private func freeSpaceHitLayer(metrics: UniverseMetrics) -> some View {
        Color.clear
            .frame(width: metrics.totalWidth, height: metrics.totalHeight)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let addr = address(at: value.location, metrics: metrics) else { return }
                        handleAddressClick(addr)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard let addr = address(at: location, metrics: metrics) else { return }
                    hoverAddress = addr
                    if fixtureAt(addr) == nil, clickToPatchArmed || selectedDefinition != nil {
                        updateGhost(at: addr)
                    }
                case .ended:
                    hoverAddress = nil
                }
            }
    }

    private func address(at point: CGPoint, metrics: UniverseMetrics) -> UInt16? {
        let col = Int(point.x / metrics.cellW)
        let row = Int(point.y / metrics.cellH)
        guard col >= 0, col < metrics.cols, row >= 0, row < metrics.rows else { return nil }
        let addr = row * metrics.cols + col + 1
        guard addr >= 1, addr <= channelCount else { return nil }
        return UInt16(addr)
    }

    // MARK: - Fixture blocks (dominant)

    @ViewBuilder
    private func fixtureBlockViews(fx: PatchedFixture, metrics: UniverseMetrics) -> some View {
        let fp = context.project.channelCount(for: fx)
        let segs = DMXUniverseGridLayout.segments(
            start: fx.address,
            footprint: fp,
            channelsPerRow: metrics.cols
        )
        let selected = context.session.selection.snapshot.fixtureIDs.contains(fx.id)
        let def = context.project.definition(id: fx.definitionId)
        let conflict = !context.project.canPlace(fixture: fx, ignoringFixtureID: fx.id)

        ForEach(Array(segs.enumerated()), id: \.offset) { idx, seg in
            let x = CGFloat(seg.colStart) * metrics.cellW + 2
            let y = CGFloat(seg.row) * metrics.cellH + 3
            let w = CGFloat(seg.colEnd - seg.colStart + 1) * metrics.cellW - 4
            let h = metrics.cellH - 6

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                blockFill(selected: selected, conflict: conflict),
                                blockFill(selected: selected, conflict: conflict).opacity(0.82)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        blockStroke(selected: selected, conflict: conflict),
                        lineWidth: selected ? 2.25 : 1
                    )
                if idx == 0 {
                    blockLabel(
                        name: fx.name,
                        model: def?.model ?? "",
                        width: w
                    )
                    .padding(.horizontal, max(4, min(8, w * 0.08)))
                    .padding(.vertical, 2)
                } else if w > 28 {
                    Text("…")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: max(w, 8), height: h)
            .clipped()
            .position(x: x + max(w, 8) / 2, y: y + h / 2)
            .shadow(
                color: selected
                    ? AuroraColor.accent.opacity(0.45)
                    : Color.black.opacity(0.35),
                radius: selected ? 8 : 3,
                y: 1
            )
            .help("\(fx.name) · \(def?.displayName ?? "?") · \(fx.address)–\(fx.endAddress(channelCount: fp))")
            .highPriorityGesture(
                TapGesture().onEnded {
                    let extend = NSEvent.modifierFlags.contains(.command)
                        || NSEvent.modifierFlags.contains(.shift)
                    context.session.selectFixtures(Set([fx.id]), extending: extend)
                    ghostPlan = nil
                    onChanged()
                }
            )
            .contextMenu { fixtureContextMenu(primaryIDs: [fx.id]) }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        dragRepatchID = fx.id
                        let candidate = repatchAddress(
                            from: fx.address,
                            translation: value.translation,
                            metrics: metrics
                        )
                        dragRepatchAddress = candidate
                        hoverAddress = candidate
                        var proposed = fx
                        proposed.address = candidate
                        dragRepatchIsValid = context.project.canPlace(
                            fixture: proposed,
                            ignoringFixtureID: fx.id
                        )
                    }
                    .onEnded { value in
                        let newAddress = repatchAddress(
                            from: fx.address,
                            translation: value.translation,
                            metrics: metrics
                        )
                        var proposed = fx
                        proposed.address = newAddress
                        let canCommit = context.project.canPlace(
                            fixture: proposed,
                            ignoringFixtureID: fx.id
                        )
                        dragRepatchID = nil
                        dragRepatchAddress = nil
                        dragRepatchIsValid = false
                        hoverAddress = nil
                        if newAddress != fx.address, canCommit {
                            repatch(fx: fx, to: newAddress)
                        } else if newAddress != fx.address {
                            statusText = "That DMX range is unavailable"
                        }
                    }
            )
        }
    }

    private func repatchAddress(
        from originalAddress: UInt16,
        translation: CGSize,
        metrics: UniverseMetrics
    ) -> UInt16 {
        let colDelta = Int((translation.width / metrics.cellW).rounded())
        let rowDelta = Int((translation.height / metrics.cellH).rounded())
        let address = max(
            1,
            min(channelCount, Int(originalAddress) + colDelta + rowDelta * metrics.cols)
        )
        return UInt16(address)
    }

    // MARK: - Context menu + lifecycle

    @ViewBuilder
    private func fixtureContextMenu(primaryIDs: [UUID]) -> some View {
        let ids = resolveMenuIDs(primaryIDs)
        let actions = PatchFixtureLifecycle.contextMenuActions(
            selectedFixtureIDs: ids,
            project: context.project
        )
        if actions.contains(.inspect) {
            Button("Inspect") { inspectFixtures(ids) }
        }
        if ids.count == 1, let id = ids.first {
            Button("Rename Fixture…") { beginFixtureRename(id) }
        }
        if actions.contains(.repatch), let id = ids.first {
            Button("Repatch…") { beginRepatch(id) }
        }
        if actions.contains(.unpatch) {
            Button("Unpatch") { performUnpatch(ids) }
        }
        if actions.contains(.deleteFixture) {
            Divider()
            Button("Delete Fixture…", role: .destructive) {
                requestDeleteFixtures(ids)
            }
        }
    }

    private func resolveMenuIDs(_ primaryIDs: [UUID]) -> [UUID] {
        let selected = Set(selectedFixtureIDs)
        if primaryIDs.contains(where: { selected.contains($0) }), selected.count > 1 {
            return selectedFixtureIDs
        }
        return primaryIDs
    }

    private func beginFixtureRename(_ fixtureID: UUID) {
        guard let fixture = context.project.fixtures.first(where: { $0.id == fixtureID }) else { return }
        renameDraft = fixture.name
        renameFixtureID = fixtureID
    }

    private func commitFixtureRename() {
        guard let fixtureID = renameFixtureID else { return }
        do {
            try context.session.perform(RenameFixtureCommand(
                fixtureID: fixtureID,
                newName: renameDraft
            ))
            statusText = "Renamed fixture"
            renameFixtureID = nil
            onChanged()
        } catch {
            renameFixtureID = nil
            let report = PrismErrorReporting.report(
                error: error,
                context: .command(operation: "rename fixture", category: .uiPatch)
            )
            DispatchQueue.main.async { renameError = report }
        }
    }

    private func inspectFixtures(_ ids: [UUID]) {
        context.session.selectFixtures(Set(ids), extending: false)
        onChanged()
    }

    private func beginRepatch(_ id: UUID) {
        guard let fx = context.project.fixtures.first(where: { $0.id == id }) else { return }
        context.session.selectFixtures(Set([id]), extending: false)
        repatchAddressText = fx.isPatched ? String(fx.address) : ""
        repatchSheetFixtureID = id
    }

    private func performUnpatch(_ ids: [UUID]) {
        let patched = ids.filter { id in
            context.project.fixtures.first(where: { $0.id == id })?.isPatched == true
        }
        guard !patched.isEmpty else { return }
        do {
            try context.session.perform(UnpatchFixtureCommand(fixtureIDs: patched))
            statusText = patched.count == 1
                ? "Unpatched (fixture preserved)"
                : "Unpatched \(patched.count) fixtures (identities preserved)"
            ghostPlan = nil
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func requestDeleteFixtures(_ ids: [UUID]) {
        let existing = ids.filter { id in
            context.project.fixtures.contains(where: { $0.id == id })
        }
        guard !existing.isEmpty else { return }
        confirmDeleteIDs = existing
        showDeleteConfirm = true
    }

    private func performDeleteFixtures(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        do {
            try context.session.perform(RemovePatchedFixtureCommand(fixtureIDs: ids))
            context.session.selectFixtures([], extending: false)
            statusText = ids.count == 1
                ? "Deleted fixture"
                : "Deleted \(ids.count) fixtures"
            confirmDeleteIDs = []
            ghostPlan = nil
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func repatchSheet(fixtureID: UUID) -> some View {
        let fx = context.project.fixtures.first(where: { $0.id == fixtureID })
        return VStack(alignment: .leading, spacing: 14) {
            Text("Repatch \(fx?.name ?? "Fixture")")
                .font(.headline)
            Text("Assign a DMX start address in the selected universe.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Text("Address")
                TextField("1–512", text: $repatchAddressText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            HStack {
                Spacer()
                Button("Cancel") { repatchSheetFixtureID = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Repatch") {
                    applyRepatchSheet(fixtureID: fixtureID)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(UInt16(repatchAddressText) == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func applyRepatchSheet(fixtureID: UUID) {
        guard let addr = UInt16(repatchAddressText), addr >= 1,
              let uni = selectedUniverse else { return }
        do {
            try context.session.perform(
                RepatchFixtureCommand(fixtureID: fixtureID, universeID: uni.id, address: addr)
            )
            statusText = "Repatched at \(addr)"
            repatchSheetFixtureID = nil
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func blockFill(selected: Bool, conflict: Bool) -> Color {
        if conflict { return AuroraColor.critical.opacity(0.42) }
        if selected { return AuroraColor.accent.opacity(0.62) }
        // Saturated violet block — reads as an object, not a cell tint
        return Color(red: 0.32, green: 0.24, blue: 0.58).opacity(0.92)
    }

    private func blockStroke(selected: Bool, conflict: Bool) -> Color {
        if conflict { return AuroraColor.critical }
        if selected { return AuroraColor.accentBright }
        return Color.white.opacity(0.22)
    }

    @ViewBuilder
    private func blockLabel(name: String, model: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: width > 64 ? 12 : 10, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if width > 80 {
                Text(model)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ghost

    /// Valid plans use planner starts; invalid plans still show the attempted span for red ghosts.
    private func ghostStarts(for plan: PatchBatchPlan) -> [UInt16] {
        if !plan.starts.isEmpty { return plan.starts }
        let fp = max(Int(plan.footprint), 1)
        let qty = max(plan.quantity, 1)
        var out: [UInt16] = []
        var cursor = Int(plan.startAddress)
        for _ in 0..<qty {
            guard cursor >= 1, cursor <= channelCount else { break }
            out.append(UInt16(cursor))
            cursor += fp
        }
        return out
    }

    @ViewBuilder
    private func ghostBlockViews(
        start: UInt16,
        footprint: UInt16,
        label: String,
        valid: Bool,
        metrics: UniverseMetrics,
        tint: Color? = nil
    ) -> some View {
        let validColor = tint ?? Color.green
        let segs = DMXUniverseGridLayout.segments(
            start: start,
            footprint: footprint,
            channelsPerRow: metrics.cols
        )
        ForEach(Array(segs.enumerated()), id: \.offset) { idx, seg in
            let x = CGFloat(seg.colStart) * metrics.cellW + 2
            let y = CGFloat(seg.row) * metrics.cellH + 3
            let w = CGFloat(seg.colEnd - seg.colStart + 1) * metrics.cellW - 4
            let h = metrics.cellH - 6
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((valid ? validColor : Color.red).opacity(valid ? 0.24 : 0.32))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        valid ? validColor.opacity(0.98) : Color.red.opacity(0.98),
                        style: StrokeStyle(lineWidth: 2.25, dash: [5, 3])
                    )
                if idx == 0 {
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(valid ? validColor.opacity(0.98) : Color.white)
                        .shadow(color: valid ? .clear : Color.red.opacity(0.8), radius: 2)
                        .padding(.horizontal, 8)
                }
            }
            .frame(width: max(w, 8), height: h)
            .position(x: x + max(w, 8) / 2, y: y + h / 2)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Interactions

    private func handleAddressClick(_ addr: UInt16) {
        // Workflow 1: PATCH-armed click places at address
        if clickToPatchArmed {
            commitPlan(at: addr)
            return
        }
        if let fx = fixtureAt(addr) {
            let extend = NSEvent.modifierFlags.contains(.command)
                || NSEvent.modifierFlags.contains(.shift)
            context.session.selectFixtures(Set([fx.id]), extending: extend)
            ghostPlan = nil
            onChanged()
            return
        }
        // A selected profile plus a free address is an explicit patch operation.
        // Hover supplies the preview; one click commits it.
        if selectedDefinition != nil {
            commitPlan(at: addr)
        }
    }

    private func fixtureAt(_ addr: UInt16) -> PatchedFixture? {
        fixturesInUniverse.first { fx in
            let end = fx.endAddress(channelCount: context.project.channelCount(for: fx))
            return addr >= fx.address && addr <= end
        }
    }

    private func armClickToPatch() {
        guard selectedDefinition != nil, selectedUniverse != nil else { return }
        clickToPatchArmed = true
        statusText = "PATCH armed — click starting DMX address for \(quantity)× \(footprint)ch"
    }

    private func cancelPatchOperation() {
        guard clickToPatchArmed || ghostPlan != nil else { return }
        clickToPatchArmed = false
        ghostPlan = nil
        hoverAddress = nil
        selectedDefinitionID = nil
        statusText = nil
    }

    private func updateGhost(at addr: UInt16) {
        guard let def = selectedDefinition, let uni = selectedUniverse else {
            ghostPlan = nil
            return
        }
        // Ensure profile exists for planner (idempotent with stable definition ID).
        _ = try? ensureDefinitionEmbedded(def)
        let plan = PatchBatchPlanner.plan(
            project: context.project,
            definitionID: def.id,
            universeID: uni.id,
            startAddress: addr,
            quantity: quantity,
            namePrefix: namePrefix.isEmpty ? "Fix" : namePrefix
        )
        ghostPlan = plan
        if plan.isValid {
            let last = plan.starts.last.map { $0 + plan.footprint - 1 } ?? addr
            statusText = "Preview \(plan.starts.count)× \(plan.footprint)ch · \(plan.starts.first ?? addr)–\(last)"
        } else {
            statusText = plan.rejectionReason ?? "Invalid placement"
        }
    }

    private func commitPlan(at addr: UInt16) {
        guard let def = selectedDefinition, let uni = selectedUniverse else { return }
        let plan = PatchBatchPlanner.plan(
            project: context.project,
            definitionID: def.id,
            universeID: uni.id,
            startAddress: addr,
            quantity: quantity,
            namePrefix: namePrefix.isEmpty ? "Fix" : namePrefix
        )
        commit(plan, embedding: def)
    }

    private func patchNextFree() {
        guard let def = selectedDefinition, let uni = selectedUniverse else { return }
        let plan = PatchBatchPlanner.planNextFree(
            project: context.project,
            definitionID: def.id,
            universeID: uni.id,
            quantity: quantity,
            namePrefix: namePrefix.isEmpty ? "Fix" : namePrefix
        )
        if plan.isValid {
            ghostPlan = plan
        }
        commit(plan, embedding: def)
    }

    private func commit(_ plan: PatchBatchPlan, embedding def: FixtureDefinition? = nil) {
        guard plan.isValid else {
            statusText = plan.rejectionReason ?? "Invalid"
            ghostPlan = plan
            return
        }
        do {
            // Embed once with a **stable** definition ID before fixtures reference it.
            if let def {
                try ensureDefinitionEmbedded(def)
            }
            let cmd = BatchPatchCommand(plan: plan)
            try context.session.perform(cmd)
            statusText = "Patched \(plan.starts.count) fixture(s) at \(plan.startAddress)"
            // Library selection is intentionally one-shot: a fresh selection is
            // required before another fixture can be patched.
            selectedDefinitionID = nil
            context.session.clearSelection()
            clickToPatchArmed = false
            ghostPlan = nil
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func repatch(fx: PatchedFixture, to address: UInt16) {
        guard let uni = selectedUniverse else { return }
        do {
            try context.session.perform(BulkRepatchCommand(changes: [
                PatchAddressChange(fixtureID: fx.id, universeID: uni.id, address: address)
            ], name: "Repatch"))
            statusText = "Repatched \(fx.name) → \(address)"
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    /// Embed a library personality into the project **once**, keeping the same definition UUID
    /// fixtures will reference. Never mint a new definition ID (that would orphan fixtures and
    /// spam the library list with look-alike Dimmer cards).
    @discardableResult
    private func ensureDefinitionEmbedded(_ def: FixtureDefinition) throws -> FixtureDefinition {
        if let existing = context.project.definition(id: def.id) {
            return existing
        }
        // Preserve def.id so BatchPatchCommand / fixtures resolve the embedded profile.
        // FixtureLibraryBox may regenerate child channel IDs; never mint a new definition UUID.
        var embed = context.fixtureLibrary?.makeEmbeddableCopy(def) ?? def
        embed.id = def.id
        try context.session.perform(EmbedFixtureDefinitionCommand(definition: embed))
        return embed
    }

    /// Workflow 3: drag profile card → drop on universe address (or next free if miss).
    /// Also accepts unpatched fixtures (`aurora.fixture.<uuid>`) for repatch-in-place.
    private func handleDefinitionDrop(
        _ providers: [NSItemProvider],
        at location: CGPoint,
        metrics: UniverseMetrics
    ) -> Bool {
        guard let uni = selectedUniverse else { return false }
        // Account for canvas padding.
        let local = CGPoint(x: location.x - 12, y: location.y - 12)
        let dropAddr = address(at: local, metrics: metrics)
        for p in providers {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String else { return }
                DispatchQueue.main.async {
                    if s.hasPrefix("aurora.fixture."),
                       let fid = UUID(uuidString: String(s.dropFirst("aurora.fixture.".count))) {
                        repatchDroppedFixture(fid, to: dropAddr, universeID: uni.id)
                        return
                    }
                    guard s.hasPrefix("aurora.def."),
                          let id = UUID(uuidString: String(s.dropFirst("aurora.def.".count)))
                    else { return }
                    selectedDefinitionID = id
                    if let def = definitions.first(where: { $0.id == id })
                        ?? context.project.definition(id: id)
                        ?? context.fixtureLibrary?.definitions.first(where: { $0.id == id }) {
                        namePrefix = shortPrefix(for: def)
                        let plan: PatchBatchPlan
                        if let dropAddr {
                            plan = PatchBatchPlanner.plan(
                                project: context.project,
                                definitionID: id,
                                universeID: uni.id,
                                startAddress: dropAddr,
                                quantity: quantity,
                                namePrefix: namePrefix
                            )
                        } else {
                            plan = PatchBatchPlanner.planNextFree(
                                project: context.project,
                                definitionID: id,
                                universeID: uni.id,
                                quantity: quantity,
                                namePrefix: namePrefix
                            )
                        }
                        commit(plan, embedding: def)
                    }
                }
            }
        }
        return true
    }

    private func repatchDroppedFixture(_ fixtureID: UUID, to dropAddr: UInt16?, universeID: UUID) {
        guard let fx = context.project.fixtures.first(where: { $0.id == fixtureID }) else { return }
        let fp = context.project.channelCount(for: fx)
        let address: UInt16
        if let dropAddr {
            address = dropAddr
        } else if let next = context.project.nextFreeAddress(in: universeID, channelCount: fp) {
            address = next
        } else {
            statusText = "No free address for \(fx.name)"
            return
        }
        do {
            try context.session.perform(
                RepatchFixtureCommand(fixtureID: fixtureID, universeID: universeID, address: address)
            )
            context.session.selectFixtures(Set([fixtureID]), extending: false)
            statusText = "Repatched \(fx.name) → \(address)"
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func addUniverse() {
        let number = (universes.map(\.number).max() ?? 0) + 1
        do {
            try context.session.perform(AddUniverseCommand(universe: Universe(number: number)))
            selectedUniverseID = context.project.universes.last?.id
            onChanged()
        } catch {
            statusText = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func copyReport(csv: Bool) {
        #if os(macOS)
        let text = csv
            ? PatchReport.csv(project: context.project)
            : PatchReport.humanReadable(project: context.project)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = csv ? "CSV copied" : "Patch report copied"
        #endif
    }
}

private struct FixtureProfileFamily: Identifiable {
    let id: String
    let manufacturer: String
    let model: String
    let modes: [FixtureDefinition]
}
