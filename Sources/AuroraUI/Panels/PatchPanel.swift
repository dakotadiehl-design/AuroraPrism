import AuroraCore
import AuroraDiagnostics
import AuroraModel
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Professional patch table (UI-09): search, presentation sort, conflict detail, bulk repatch.
public struct PatchPanel: View {
    public var context: WorkspacePanelContext
    @State private var selectedUniverseID: UUID?
    @State private var errorText: String?
    @State private var errorReport: PrismErrorReport?
    @State private var searchText: String = ""
    @State private var sortKey: PatchSortKey = .address
    @State private var sortAscending: Bool = true
    @State private var repatchFixtureID: UUID?
    @State private var repatchAddress: String = ""
    @State private var bulkOffsetText: String = "0"
    @State private var showBulkSheet: Bool = false
    @State private var showBulkCreate: Bool = false
    @State private var bulkCreateCount: Int = 4
    @State private var bulkCreatePrefix: String = "Unit"
    @State private var bulkCreateDefID: UUID?
    @State private var showImportCSV: Bool = false
    @State private var importCSVText: String = ""
    @State private var renumberStart: Int = 1
    @State private var confirmDeleteIDs: [UUID] = []
    @State private var showDeleteConfirm = false

    public init(context: WorkspacePanelContext) {
        self.context = context
    }

    private enum PatchSortKey: String, CaseIterable, Identifiable {
        case address = "Address"
        case name = "Name"
        case end = "End"
        var id: String { rawValue }
    }

    private var universes: [Universe] { context.project.universes }

    private var selectedUniverse: Universe? {
        if let selectedUniverseID {
            return universes.first { $0.id == selectedUniverseID }
        }
        return universes.first
    }

    /// Presentation-only ordered fixtures — never mutates `ShowProject.fixtures`.
    private var displayedFixtures: [PatchedFixture] {
        guard let uid = selectedUniverse?.id else { return [] }
        var list = context.project.fixtures.filter { $0.universeId == uid }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { fx in
                fx.name.lowercased().contains(q)
                    || String(fx.address).contains(q)
                    || (context.project.definition(id: fx.definitionId)?.displayName.lowercased().contains(q) ?? false)
            }
        }
        list.sort { a, b in
            let ascending = sortAscending
            switch sortKey {
            case .address:
                return ascending ? a.address < b.address : a.address > b.address
            case .name:
                return ascending
                    ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
            case .end:
                let aEnd = a.endAddress(channelCount: context.project.channelCount(for: a))
                let bEnd = b.endAddress(channelCount: context.project.channelCount(for: b))
                return ascending ? aEnd < bEnd : aEnd > bEnd
            }
        }
        return list
    }

    private var overlaps: [PatchOverlap] {
        context.project.overlappingPatchRanges()
    }

    private var conflictsInSelectedUniverse: [PatchOverlap] {
        guard let uid = selectedUniverse?.id else { return [] }
        return overlaps.filter { $0.universeId == uid }
    }

    /// PATCH-01: presentation-only per-row validation issues.
    private func issues(for fixture: PatchedFixture) -> [String] {
        var list: [String] = []
        if context.project.universe(id: fixture.universeId) == nil {
            list.append("universe missing")
        }
        if context.project.definition(id: fixture.definitionId) == nil {
            list.append("missing definition")
        }
        if !fixture.isPatched {
            list.append("unpatched")
            return list
        }
        let count = context.project.channelCount(for: fixture)
        let end = fixture.endAddress(channelCount: count)
        let capacity = context.project.universe(id: fixture.universeId)?.channelCount ?? 512
        if end > capacity {
            list.append("footprint past \(capacity)")
        }
        if conflictIDs.contains(fixture.id) {
            list.append("overlap")
        }
        return list
    }

    private var invalidFixturesInView: [(PatchedFixture, [String])] {
        displayedFixtures.compactMap { fx in
            let iss = issues(for: fx)
            return iss.isEmpty ? nil : (fx, iss)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !conflictsInSelectedUniverse.isEmpty {
                conflictBanner
            }
            if !invalidFixturesInView.isEmpty {
                validationBanner
            }
            if displayedFixtures.isEmpty {
                PlaceholderPanel(
                    title: "Patch",
                    detail: emptyDetail
                )
            } else {
                Table(displayedFixtures, selection: fixtureSelection) {
                    TableColumn("Addr") { fixture in
                        let bad = !issues(for: fixture).isEmpty
                        Text(fixture.isPatched ? "\(fixture.address)" : "—")
                            .font(.body.monospaced())
                            .foregroundStyle(bad ? Color.orange : Color.primary)
                    }
                    .width(50)
                    TableColumn("End") { fixture in
                        if fixture.isPatched {
                            let end = fixture.endAddress(channelCount: context.project.channelCount(for: fixture))
                            let bad = end > (context.project.universe(id: fixture.universeId)?.channelCount ?? 512)
                            Text("\(end)")
                                .font(.body.monospaced())
                                .foregroundStyle(bad ? Color.orange : Color.primary)
                        } else {
                            Text("—")
                                .font(.body.monospaced())
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .width(50)
                    TableColumn("Name") { fixture in
                        Text(fixture.name)
                    }
                    TableColumn("Personality") { fixture in
                        let missing = context.project.definition(id: fixture.definitionId) == nil
                        Text(context.project.definition(id: fixture.definitionId)?.displayName ?? "— missing")
                            .foregroundStyle(missing ? Color.orange : Color.secondary)
                    }
                    TableColumn("Ch") { fixture in
                        Text("\(context.project.channelCount(for: fixture))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(40)
                    TableColumn("Issues") { fixture in
                        let iss = issues(for: fixture)
                        Text(iss.isEmpty ? "OK" : iss.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(iss.isEmpty ? Color.secondary : Color.orange)
                            .lineLimit(2)
                    }
                    .width(140)
                }
                .contextMenu {
                    Button("Inspect") {
                        // Selection already drives Inspector.
                    }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                    Button("Repatch…") {
                        if let id = context.session.selection.snapshot.fixtureIDs.first,
                           let fixture = context.project.fixtures.first(where: { $0.id == id }) {
                            repatchAddress = fixture.isPatched ? String(fixture.address) : ""
                            repatchFixtureID = id
                        }
                    }
                    .disabled(context.session.selection.snapshot.fixtureIDs.count != 1)
                    Button("Unpatch") { unpatchSelected() }
                        .disabled(!PatchFixtureLifecycle.canUnpatchFixtures(
                            selectedFixtureIDs: Array(context.session.selection.snapshot.fixtureIDs),
                            project: context.project
                        ))
                    Divider()
                    Button("Bulk offset…") {
                        bulkOffsetText = "0"
                        showBulkSheet = true
                    }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                    Button("Clone") { cloneSelected() }
                    Divider()
                    Button("Delete Fixture…", role: .destructive) { requestDeleteSelected() }
                        .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                }
            }
            routeFooter
        }
        .onAppear {
            if selectedUniverseID == nil {
                selectedUniverseID = universes.first?.id
            }
        }
        .confirmationDialog(
            confirmDeleteIDs.count <= 1 ? "Delete Fixture?" : "Delete \(confirmDeleteIDs.count) Fixtures?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Fixture\(confirmDeleteIDs.count > 1 ? "s" : "")", role: .destructive) {
                removeSelected(ids: confirmDeleteIDs)
            }
            Button("Cancel", role: .cancel) { confirmDeleteIDs = [] }
        } message: {
            Text(
                FixtureReferenceIndex.summarize(
                    fixtureIDs: Set(confirmDeleteIDs),
                    in: context.project
                ).confirmationDetail
            )
        }
        .sheet(item: $repatchFixtureID) { id in
            VStack(alignment: .leading, spacing: 12) {
                Text("Repatch Fixture").font(.headline)
                TextField("DMX address", text: $repatchAddress)
                HStack {
                    Button("Cancel") { repatchFixtureID = nil }
                    Button("Apply") { applyRepatch(id) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 280)
        }
        .sheet(isPresented: $showBulkSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bulk address offset").font(.headline)
                Text("Applies an address offset to all selected fixtures atomically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Offset (e.g. 16 or -8)", text: $bulkOffsetText)
                HStack {
                    Button("Cancel") { showBulkSheet = false }
                    Button("Apply") { applyBulkOffset() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 320)
        }
        .sheet(isPresented: $showBulkCreate) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bulk create fixtures").font(.headline)
                if !context.project.fixtureDefinitions.isEmpty {
                    Picker("Profile", selection: Binding(
                        get: { bulkCreateDefID ?? context.project.fixtureDefinitions[0].id },
                        set: { bulkCreateDefID = $0 }
                    )) {
                        ForEach(context.project.fixtureDefinitions) { d in
                            Text(d.displayName).tag(Optional(d.id))
                        }
                    }
                }
                TextField("Name prefix", text: $bulkCreatePrefix)
                Stepper("Count: \(bulkCreateCount)", value: $bulkCreateCount, in: 1...64)
                HStack {
                    Button("Cancel") { showBulkCreate = false }
                    Button("Create") { applyBulkCreate() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 360)
        }
        .sheet(isPresented: $showImportCSV) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import patch CSV").font(.headline)
                Text("Paste CSV with Universe,Address,Name[,Manufacturer,Model] (or full Report CSV).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $importCSVText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 160)
                    .border(Color.secondary.opacity(0.3))
                HStack {
                    Button("Cancel") { showImportCSV = false }
                    Button("Import") { applyImportCSV() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 480, height: 320)
        }
        .prismErrorAlert(item: $errorReport)
    }

    private func reportPatchFailure(_ error: Error, operation: String) {
        errorReport = PrismErrorReporting.report(
            error: error,
            context: .command(operation: operation, category: .uiPatch)
        )
    }

    private var emptyDetail: String {
        if universes.isEmpty {
            return "Add a universe, then patch fixtures from the Fixture Browser."
        }
        if !searchText.isEmpty {
            return "No fixtures match “\(searchText)” in this universe."
        }
        return "No fixtures in this universe. Patch from the Fixture Browser."
    }

    private var conflictIDs: Set<UUID> {
        var ids = Set<UUID>()
        for o in conflictsInSelectedUniverse {
            ids.insert(o.first)
            ids.insert(o.second)
        }
        return ids
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack {
                if universes.isEmpty {
                    Text("No universes")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Universe", selection: Binding(
                        get: { selectedUniverse?.id ?? universes[0].id },
                        set: { selectedUniverseID = $0 }
                    )) {
                        ForEach(universes) { universe in
                            Text("\(universe.number): \(universe.name)").tag(universe.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                Picker("Sort", selection: $sortKey) {
                    ForEach(PatchSortKey.allCases) { key in
                        Text(key.rawValue).tag(key)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
                Button {
                    sortAscending.toggle()
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
                .help("Toggle sort direction (presentation only)")
                Spacer()
                Button("Add Universe") { addUniverse() }
                Button("Clone") { cloneSelected() }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                Button("Unpatch") { unpatchSelected() }
                    .disabled(!PatchFixtureLifecycle.canUnpatchFixtures(
                        selectedFixtureIDs: Array(context.session.selection.snapshot.fixtureIDs),
                        project: context.project
                    ))
                Button("Delete…") { requestDeleteSelected() }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                Button("Bulk…") {
                    bulkOffsetText = "0"
                    showBulkSheet = true
                }
                .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                Button("Renumber") { renumberSelected() }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                    .help("Rename selected fixtures Fix 1, Fix 2, …")
                Button("+ Bulk Create") {
                    bulkCreateDefID = context.project.fixtureDefinitions.first?.id
                    showBulkCreate = true
                }
                .disabled(context.project.fixtureDefinitions.isEmpty || selectedUniverse == nil)
                Button("Import CSV…") { showImportCSV = true }
                Button("CSV") {
                    let csv = PatchReport.csv(project: context.project)
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(csv, forType: .string)
                    #endif
                    errorText = "Patch CSV copied (\(context.project.fixtures.count) fixtures)"
                }
                .help("Copy patch sheet as CSV")
                Button("Report") {
                    let report = PatchReport.humanReadable(project: context.project)
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    #endif
                    errorText = "Patch report copied to clipboard (\(context.project.fixtures.count) fixtures)"
                }
                .help("Copy human-readable patch report")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    private var conflictBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Patch conflicts (\(conflictsInSelectedUniverse.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(conflictsInSelectedUniverse.prefix(6).enumerated()), id: \.offset) { _, o in
                let a = context.project.fixtures.first { $0.id == o.first }
                let b = context.project.fixtures.first { $0.id == o.second }
                let aName = a.map { "\($0.name) @\($0.address)" } ?? o.first.uuidString.prefix(8).description
                let bName = b.map { "\($0.name) @\($0.address)" } ?? o.second.uuidString.prefix(8).description
                Text("• \(aName) overlaps \(bName)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if conflictsInSelectedUniverse.count > 6 {
                Text("…and \(conflictsInSelectedUniverse.count - 6) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.orange.opacity(0.08))
    }

    private var validationBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Patch validation (\(invalidFixturesInView.count) fixture(s))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(invalidFixturesInView.prefix(8).enumerated()), id: \.offset) { _, pair in
                Text("• \(pair.0.name) @\(pair.0.address): \(pair.1.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if invalidFixturesInView.count > 8 {
                Text("…and \(invalidFixturesInView.count - 8) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.orange.opacity(0.06))
    }

    private var routeFooter: some View {
        HStack {
            if let u = selectedUniverse {
                Text("Route: \(u.protocolHint.rawValue) · U\(u.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(displayedFixtures.count) shown")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    private var fixtureSelection: Binding<Set<PatchedFixture.ID>> {
        Binding(
            get: { context.session.selection.snapshot.fixtureIDs },
            set: { context.session.selectFixtures($0) }
        )
    }

    private func addUniverse() {
        errorText = nil
        let number = (universes.map(\.number).max() ?? 0) + 1
        do {
            try context.session.perform(AddUniverseCommand(universe: Universe(number: number)))
            selectedUniverseID = context.project.universes.last?.id
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func unpatchSelected() {
        errorText = nil
        let ids = Array(context.session.selection.snapshot.fixtureIDs)
        guard PatchFixtureLifecycle.canUnpatchFixtures(selectedFixtureIDs: ids, project: context.project)
        else { return }
        do {
            try context.session.perform(UnpatchFixtureCommand(fixtureIDs: ids))
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func requestDeleteSelected() {
        let ids = Array(context.session.selection.snapshot.fixtureIDs)
        guard !ids.isEmpty else { return }
        confirmDeleteIDs = ids
        showDeleteConfirm = true
    }

    private func removeSelected(ids: [UUID]? = nil) {
        errorText = nil
        let target = ids ?? Array(context.session.selection.snapshot.fixtureIDs)
        guard !target.isEmpty else { return }
        do {
            try context.session.perform(RemovePatchedFixtureCommand(fixtureIDs: target))
            context.session.selectFixtures([], extending: false)
            confirmDeleteIDs = []
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func cloneSelected() {
        errorText = nil
        guard let id = context.session.selection.snapshot.fixtureIDs.first else { return }
        do {
            try context.session.perform(ClonePatchedFixtureCommand(sourceFixtureID: id))
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func applyRepatch(_ id: UUID) {
        errorText = nil
        guard let address = UInt16(repatchAddress),
              let universeID = selectedUniverse?.id
        else {
            errorText = "Invalid address"
            return
        }
        do {
            // Prefer atomic bulk path even for single fixture (same preflight).
            try context.session.perform(
                BulkRepatchCommand(changes: [
                    PatchAddressChange(fixtureID: id, universeID: universeID, address: address)
                ], name: "Repatch")
            )
            repatchFixtureID = nil
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func applyBulkOffset() {
        errorText = nil
        guard let offset = Int(bulkOffsetText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorText = "Invalid offset"
            return
        }
        let ids = context.session.selection.snapshot.fixtureIDs
        var changes: [PatchAddressChange] = []
        for id in ids {
            guard let fx = context.project.fixtures.first(where: { $0.id == id }) else { continue }
            let next = Int(fx.address) + offset
            guard next >= 1, next <= 512 else {
                errorText = "Offset would place \(fx.name) outside 1…512"
                return
            }
            changes.append(PatchAddressChange(
                fixtureID: id,
                universeID: fx.universeId,
                address: UInt16(next)
            ))
        }
        guard !changes.isEmpty else {
            showBulkSheet = false
            return
        }
        do {
            try context.session.perform(BulkRepatchCommand(changes: changes, name: "Bulk Offset"))
            showBulkSheet = false
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func renumberSelected() {
        errorText = nil
        let ids = displayedFixtures
            .filter { context.session.selection.snapshot.fixtureIDs.contains($0.id) }
            .map(\.id)
        let ordered = ids.isEmpty
            ? Array(context.session.selection.snapshot.fixtureIDs)
            : ids
        guard !ordered.isEmpty else { return }
        do {
            try context.session.perform(RenumberFixturesCommand(
                fixtureIDs: ordered,
                startNumber: renumberStart,
                namePrefix: "Fix"
            ))
            errorText = "Renumbered \(ordered.count) fixture(s)"
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func applyBulkCreate() {
        errorText = nil
        guard let defID = bulkCreateDefID ?? context.project.fixtureDefinitions.first?.id,
              let universeID = selectedUniverse?.id,
              let def = context.project.definition(id: defID)
        else {
            errorText = "Select universe and profile"
            return
        }
        let start = context.project.nextFreeAddress(in: universeID, channelCount: def.calculatedFootprint) ?? 1
        do {
            let cmd = BulkCreateFixturesCommand(
                definitionID: defID,
                universeID: universeID,
                count: bulkCreateCount,
                startAddress: start,
                namePrefix: bulkCreatePrefix.isEmpty ? "Unit" : bulkCreatePrefix
            )
            try context.session.perform(cmd)
            showBulkCreate = false
            errorText = "Created \(cmd.createdFixtureIDs.count) fixture(s) from \(start)"
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }

    private func applyImportCSV() {
        errorText = nil
        do {
            try context.session.perform(ImportPatchCSVCommand(csv: importCSVText))
            showImportCSV = false
            importCSVText = ""
            errorText = "CSV import complete"
        } catch {
            reportPatchFailure(error, operation: "edit patch")
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
