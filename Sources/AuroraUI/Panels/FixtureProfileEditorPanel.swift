import AuroraCore
import AuroraEngine
import AuroraFixtureLib
import AuroraModel
import SwiftUI
import UniformTypeIdentifiers

/// Operator Fixture Profile Editor (P0-B Pass-1).
/// Create / edit / validate definitions and save to the show (or user library folder).
public struct FixtureProfileEditorPanel: View {
    public var context: WorkspacePanelContext
    public var onChanged: () -> Void

    @State private var selectedID: UUID?
    @State private var draft: FixtureDefinition?
    @State private var status: String?
    @State private var validationErrors: [String] = []
    @State private var channelDrafts: [ChannelRow] = []
    @State private var showNewSheet = false
    @State private var newManufacturer = "User"
    @State private var newModel = "Custom"
    @State private var newMode = "Mode 1"
    @State private var newChannelCount: Int = 4
    @State private var newCategory = "generic"
    @State private var cellCount: Int = 0
    @State private var cellChannelsPerCell: Int = 3

    public init(context: WorkspacePanelContext, onChanged: @escaping () -> Void = {}) {
        self.context = context
        self.onChanged = onChanged
    }

    private var definitions: [FixtureDefinition] {
        context.project.fixtureDefinitions.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 180, idealWidth: 220)
            editorColumn
                .frame(minWidth: 320)
        }
        .background(AuroraColor.surfacePanel)
        .onAppear {
            if selectedID == nil {
                selectedID = definitions.first?.id
                loadDraft()
            }
        }
        .sheet(isPresented: $showNewSheet) {
            newProfileSheet
        }
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Profiles")
                    .font(AuroraTypography.sectionHeading)
                Spacer()
                Button {
                    showNewSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .controlSize(.small)
            }
            .padding(8)
            Divider()
            List(definitions, selection: $selectedID) { def in
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.displayName)
                        .font(.callout)
                    Text("\(def.calculatedFootprint) ch · \(def.category.isEmpty ? "generic" : def.category)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tag(def.id)
            }
            .onChange(of: selectedID) { _, _ in
                loadDraft()
            }
        }
    }

    private var editorColumn: some View {
        Group {
            if let def = draft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        identityFields(def: Binding(
                            get: { draft ?? def },
                            set: { draft = $0 }
                        ))
                        channelTable
                        cellBlockSection
                        validationSection
                        actionRow(def: def)
                        if let status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                }
            } else {
                AuroraEmptyState(
                    title: "No profile selected",
                    detail: "Create a new fixture profile or select one from the show library.",
                    systemImage: "lightbulb"
                )
            }
        }
    }

    private func identityFields(def: Binding<FixtureDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IDENTITY")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack {
                labeledField("Manufacturer", text: Binding(
                    get: { def.wrappedValue.manufacturer },
                    set: { def.wrappedValue.manufacturer = $0; draft = def.wrappedValue }
                ))
                labeledField("Model", text: Binding(
                    get: { def.wrappedValue.model },
                    set: { def.wrappedValue.model = $0; draft = def.wrappedValue }
                ))
            }
            HStack {
                labeledField("Mode", text: Binding(
                    get: { def.wrappedValue.modeName },
                    set: { def.wrappedValue.modeName = $0; draft = def.wrappedValue }
                ))
                labeledField("Category", text: Binding(
                    get: { def.wrappedValue.category },
                    set: { def.wrappedValue.category = $0; draft = def.wrappedValue }
                ))
            }
            HStack {
                Toggle("Pan/Tilt", isOn: Binding(
                    get: { def.wrappedValue.hasPanTilt },
                    set: { def.wrappedValue.hasPanTilt = $0; draft = def.wrappedValue }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                Picker("Color", selection: Binding(
                    get: { def.wrappedValue.colorModel },
                    set: { def.wrappedValue.colorModel = $0; draft = def.wrappedValue }
                )) {
                    ForEach(ColorModel.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .frame(maxWidth: 160)
            }
        }
    }

    private var channelTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CHANNELS")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                Spacer()
                Button("+ Channel") { addChannel() }
                    .controlSize(.small)
            }
            ForEach($channelDrafts) { $row in
                HStack(spacing: 6) {
                    TextField("Off", value: $row.offset, format: .number)
                        .frame(width: 40)
                    TextField("Name", text: $row.name)
                        .frame(minWidth: 60)
                    TextField("Attr", text: $row.attribute)
                        .frame(minWidth: 70)
                    Picker("", selection: $row.resolution) {
                        ForEach(ChannelResolution.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .frame(width: 90)
                    Picker("", selection: $row.semanticKind) {
                        Text("sem").tag(ChannelSemanticKind.semantic)
                        Text("gen").tag(ChannelSemanticKind.generic)
                    }
                    .frame(width: 60)
                    Button(role: .destructive) {
                        channelDrafts.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    .controlSize(.mini)
                }
                .font(.caption.monospaced())
            }
            Button("Apply channel table → draft") {
                applyChannelsToDraft()
            }
            .controlSize(.small)
        }
    }

    private var cellBlockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MULTI-CELL BLOCK")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack {
                Stepper("Cells: \(cellCount)", value: $cellCount, in: 0...512)
                Stepper("Ch/cell: \(cellChannelsPerCell)", value: $cellChannelsPerCell, in: 1...16)
                Button("Apply cells") { applyCellBlock() }
                    .controlSize(.small)
            }
            Text("Cell attrs default to colorR/G/B (or intensity for 1ch). Footprint auto-updates.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var validationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("VALIDATION")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                Button("Validate") { runValidation() }
                    .controlSize(.small)
            }
            if validationErrors.isEmpty {
                Text("No errors (run Validate after edits).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(validationErrors, id: \.self) { err in
                    Text("• \(err)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func actionRow(def: FixtureDefinition) -> some View {
        HStack {
            Button("Save to Show") { saveToShow() }
                .buttonStyle(AuroraButtonStyle(kind: .primary))
                .controlSize(.small)
            Button("Save User Library…") { saveToUserLibrary() }
                .controlSize(.small)
            Button("Test intensity (safe)") { testIntensitySafe() }
                .controlSize(.small)
                .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
            Spacer()
            Text("Footprint \(draft?.calculatedFootprint ?? 0) ch")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var newProfileSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Fixture Profile")
                .font(.headline)
            TextField("Manufacturer", text: $newManufacturer)
            TextField("Model", text: $newModel)
            TextField("Mode", text: $newMode)
            TextField("Category", text: $newCategory)
            Stepper("Channels: \(newChannelCount)", value: $newChannelCount, in: 1...512)
            HStack {
                Button("Cancel") { showNewSheet = false }
                Spacer()
                Button("Create") {
                    createNew()
                    showNewSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func loadDraft() {
        guard let id = selectedID,
              let def = context.project.fixtureDefinitions.first(where: { $0.id == id })
        else {
            draft = nil
            channelDrafts = []
            return
        }
        draft = def
        channelDrafts = def.channels.map { ChannelRow(from: $0) }
        cellCount = Int(def.cellBlock?.cellCount ?? 0)
        cellChannelsPerCell = Int(def.cellBlock?.channelsPerCell ?? 3)
        validationErrors = []
        status = nil
    }

    private func addChannel() {
        let next = (channelDrafts.map(\.offset).max() ?? 0) + 1
        channelDrafts.append(ChannelRow(
            offset: next,
            name: "Ch\(next)",
            attribute: "generic\(next)",
            resolution: .eightBit,
            semanticKind: .generic
        ))
    }

    private func applyChannelsToDraft() {
        guard var def = draft else { return }
        def.channels = channelDrafts.map { $0.toChannelDef() }
        def.channelCount = def.calculatedFootprint
        draft = def
        runValidation()
    }

    private func applyCellBlock() {
        guard var def = draft else { return }
        if cellCount <= 0 {
            def.cellBlock = nil
        } else {
            var ch: [ChannelDef] = []
            if cellChannelsPerCell >= 3 {
                ch = [
                    ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                    ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                    ChannelDef(offset: 3, name: "B", attribute: "colorB"),
                ]
                for i in 4...cellChannelsPerCell {
                    ch.append(ChannelDef(offset: UInt16(i), name: "C\(i)", attribute: "generic\(i)", semanticKind: .generic))
                }
            } else {
                ch = [ChannelDef(offset: 1, name: "Int", attribute: "intensity")]
            }
            def.cellBlock = FixtureCellBlock(channels: Array(ch.prefix(cellChannelsPerCell)), cellCount: UInt16(cellCount))
        }
        def.channelCount = def.calculatedFootprint
        draft = def
        runValidation()
    }

    private func runValidation() {
        applyChannelsToDraft()
        guard let def = draft else { return }
        var errors: [String] = []
        do {
            try FixtureDefinitionValidation.validate(def)
        } catch {
            errors.append(error.localizedDescription)
        }
        // Extra overlap/gap checks
        var seen = Set<UInt16>()
        for ch in def.channels {
            if seen.contains(ch.offset) {
                errors.append("Duplicate offset \(ch.offset)")
            }
            seen.insert(ch.offset)
            if ch.attribute.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append("Empty attribute at offset \(ch.offset)")
            }
        }
        if let block = def.cellBlock {
            if block.cellCount == 0 {
                errors.append("Cell block has zero cells")
            }
            if block.channels.isEmpty {
                errors.append("Cell block has no channel template")
            }
        }
        validationErrors = errors
        status = errors.isEmpty ? "Validation OK · footprint \(def.calculatedFootprint)" : "\(errors.count) issue(s)"
    }

    private func saveToShow() {
        applyChannelsToDraft()
        guard let def = draft else { return }
        runValidation()
        guard validationErrors.isEmpty else {
            status = "Fix validation errors before save"
            return
        }
        do {
            try context.session.perform(EmbedFixtureDefinitionCommand(definition: def))
            selectedID = def.id
            status = "Saved \(def.displayName) to show"
            onChanged()
        } catch {
            status = error.localizedDescription
        }
    }

    private func saveToUserLibrary() {
        applyChannelsToDraft()
        guard let def = draft else { return }
        runValidation()
        guard validationErrors.isEmpty else {
            status = "Fix validation errors before save"
            return
        }
        do {
            let url = try UserFixtureLibrary.save(definition: def)
            // Also embed in show so it is immediately usable.
            try context.session.perform(EmbedFixtureDefinitionCommand(definition: def))
            status = "Saved to user library: \(url.lastPathComponent)"
            onChanged()
        } catch {
            status = error.localizedDescription
        }
    }

    private func testIntensitySafe() {
        // Safe test: set intensity 0.3 on selected fixtures that use this profile — host routes via programmer.
        status = "Select fixtures using this profile and set Intensity in Programmer (safe test via engine)."
    }

    private func createNew() {
        var channels: [ChannelDef] = []
        for i in 1...newChannelCount {
            let attr: String
            switch i {
            case 1: attr = newChannelCount >= 3 ? "colorR" : "intensity"
            case 2: attr = "colorG"
            case 3: attr = "colorB"
            case 4: attr = newChannelCount >= 4 ? "intensity" : "generic4"
            default: attr = "generic\(i)"
            }
            channels.append(ChannelDef(
                offset: UInt16(i),
                name: "Ch\(i)",
                attribute: attr,
                semanticKind: attr.hasPrefix("generic") ? .generic : .semantic
            ))
        }
        let def = FixtureDefinition(
            manufacturer: newManufacturer,
            model: newModel,
            modeName: newMode,
            channels: channels,
            colorModel: newChannelCount >= 3 ? .rgb : .singleColor,
            category: newCategory
        )
        do {
            try context.session.perform(EmbedFixtureDefinitionCommand(definition: def))
            selectedID = def.id
            loadDraft()
            status = "Created \(def.displayName)"
            onChanged()
        } catch {
            status = error.localizedDescription
        }
    }

    private struct ChannelRow: Identifiable, Equatable {
        var id: UUID
        var offset: UInt16
        var name: String
        var attribute: String
        var resolution: ChannelResolution
        var semanticKind: ChannelSemanticKind

        init(
            id: UUID = UUID(),
            offset: UInt16,
            name: String,
            attribute: String,
            resolution: ChannelResolution = .eightBit,
            semanticKind: ChannelSemanticKind = .semantic
        ) {
            self.id = id
            self.offset = offset
            self.name = name
            self.attribute = attribute
            self.resolution = resolution
            self.semanticKind = semanticKind
        }

        init(from ch: ChannelDef) {
            self.id = ch.id
            self.offset = ch.offset
            self.name = ch.name
            self.attribute = ch.attribute
            self.resolution = ch.resolution
            self.semanticKind = ch.semanticKind
        }

        func toChannelDef() -> ChannelDef {
            ChannelDef(
                id: id,
                offset: offset,
                name: name,
                attribute: attribute,
                resolution: resolution,
                semanticKind: semanticKind
            )
        }
    }
}

// MARK: - User library store

public enum UserFixtureLibrary {
    public static var sharedDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Aurora/UserFixtureLibrary", isDirectory: true)
    }

    public static func save(definition: FixtureDefinition) throws -> URL {
        let dir = sharedDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = "\(definition.manufacturer)-\(definition.model)-\(definition.modeName)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let url = dir.appendingPathComponent("\(safeName)-\(definition.id.uuidString.prefix(8)).json")
        let data = try JSONEncoder().encode(definition)
        try data.write(to: url, options: .atomic)
        return url
    }

    public static func loadAll() throws -> [FixtureDefinition] {
        let dir = sharedDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FixtureDefinition.self, from: data)
        }
    }
}
