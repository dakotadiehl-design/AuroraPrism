import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// Visual palette / look shelf with create, apply, delete, and Record Ref (UI-04).
public struct PalettesPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var focusedPaletteID: UUID?
    public var focusedPresetID: UUID?
    public var onChanged: () -> Void
    public var onProjectChanged: () -> Void
    public var onInspectPalette: (UUID) -> Void
    public var onInspectPreset: (UUID) -> Void
    public var onClearInspector: () -> Void

    @State private var statusText: String?
    @State private var palettePendingDelete: Palette?
    @State private var presetPendingDelete: Preset?
    @State private var showDeletePaletteConfirm = false
    @State private var showDeletePresetConfirm = false

    public init(
        context: WorkspacePanelContext,
        programmer: Programmer,
        focusedPaletteID: UUID? = nil,
        focusedPresetID: UUID? = nil,
        onChanged: @escaping () -> Void = {},
        onProjectChanged: @escaping () -> Void = {},
        onInspectPalette: @escaping (UUID) -> Void = { _ in },
        onInspectPreset: @escaping (UUID) -> Void = { _ in },
        onClearInspector: @escaping () -> Void = {}
    ) {
        self.context = context
        self.programmer = programmer
        self.focusedPaletteID = focusedPaletteID
        self.focusedPresetID = focusedPresetID
        self.onChanged = onChanged
        self.onProjectChanged = onProjectChanged
        self.onInspectPalette = onInspectPalette
        self.onInspectPreset = onInspectPreset
        self.onClearInspector = onClearInspector
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider().overlay(AuroraColor.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: AuroraSpacing.sm) {
                    if context.project.palettes.isEmpty && context.project.presets.isEmpty {
                        AuroraEmptyState(
                            title: "No palettes",
                            detail: "Create color, position, intensity, or looks from the programmer.",
                            systemImage: "paintpalette"
                        )
                        .frame(height: 100)
                    } else {
                        colorSection
                        positionSection
                        otherSection
                        presetsSection
                    }
                    if !context.project.validateReferences().isEmpty {
                        Text("⚠ \(context.project.validateReferences().count) broken palette ref(s)")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.warning)
                    }
                    if let statusText {
                        Text(statusText)
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
            }
        }
        .background(AuroraColor.surfacePanel)
        .confirmationDialog(
            deletePaletteTitle,
            isPresented: $showDeletePaletteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Palette", role: .destructive) {
                if let palette = palettePendingDelete {
                    performDeletePalette(palette)
                }
                palettePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                palettePendingDelete = nil
            }
        } message: {
            Text(deletePaletteMessage)
        }
        .confirmationDialog(
            deletePresetTitle,
            isPresented: $showDeletePresetConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Look", role: .destructive) {
                if let preset = presetPendingDelete {
                    performDeletePreset(preset)
                }
                presetPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                presetPendingDelete = nil
            }
        } message: {
            Text("This removes the look from the show. It does not delete cues.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Palettes")
                .font(AuroraTypography.panelTitle)
                .foregroundStyle(AuroraColor.textSecondary)
            Spacer()
            Button("+ Color") { createPalette(kind: .color) }
                .controlSize(.small)
            Button("+ Pos") { createPalette(kind: .position) }
                .controlSize(.small)
            Button("+ Int") { createPalette(kind: .intensity) }
                .controlSize(.small)
            Button("+ Look") { createLook() }
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AuroraColor.surfaceHeader)
    }

    // MARK: - Sections

    private var colorPalettes: [Palette] {
        context.project.palettes.filter { $0.type == .color || $0.type == .intensity }
    }
    private var positionPalettes: [Palette] {
        context.project.palettes.filter { $0.type == .position }
    }
    private var otherPalettes: [Palette] {
        context.project.palettes.filter { $0.type == .beam || $0.type == .gobo || $0.type == .general }
    }

    private var colorSection: some View {
        Group {
            if !colorPalettes.isEmpty {
                AuroraSectionHeader("Colors / Intensity")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(colorPalettes) { palette in
                            paletteTile(palette, kind: palette.type == .intensity ? .beam : .color)
                        }
                    }
                }
            }
        }
    }

    private var positionSection: some View {
        Group {
            if !positionPalettes.isEmpty {
                AuroraSectionHeader("Position")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(positionPalettes) { palette in
                            paletteTile(palette, kind: .position, positionSymbol: "scope")
                        }
                    }
                }
            }
        }
    }

    private var otherSection: some View {
        Group {
            if !otherPalettes.isEmpty {
                AuroraSectionHeader("Beam / Other")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(otherPalettes) { palette in
                            paletteTile(palette, kind: palette.type == .gobo ? .gobo : .beam)
                        }
                    }
                }
            }
        }
    }

    private var presetsSection: some View {
        Group {
            if !context.project.presets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    AuroraSectionHeader("Looks")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(context.project.presets) { preset in
                                AuroraLookTile(
                                    name: preset.name,
                                    isSelected: focusedPresetID == preset.id,
                                    action: {
                                        onInspectPreset(preset.id)
                                        applyPreset(preset)
                                    }
                                )
                                .contextMenu {
                                    Button("Inspect") { onInspectPreset(preset.id) }
                                    Button("Delete Look", role: .destructive) {
                                        requestDeletePreset(preset)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func paletteTile(
        _ palette: Palette,
        kind: AuroraPaletteKind,
        positionSymbol: String? = nil
    ) -> some View {
        AuroraPaletteTile(
            name: palette.name,
            swatch: color(from: palette),
            kind: kind,
            isSelected: focusedPaletteID == palette.id,
            positionSymbol: positionSymbol,
            action: {
                onInspectPalette(palette.id)
                apply(palette)
            }
        )
        .contextMenu {
            Button("Inspect") { onInspectPalette(palette.id) }
            Button("Record Ref to Cue") { recordRef(palette) }
            Button("Delete Palette", role: .destructive) {
                requestDeletePalette(palette)
            }
        }
    }

    // MARK: - Create (A2)

    private func capabilityMap(for ids: [UUID]) -> [UUID: Set<String>] {
        ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: ids,
            project: context.project
        )
    }

    private func createPalette(kind: PaletteCreateKind) {
        let snap = programmer.snapshot()
        let ordered = context.session.selection.snapshot.orderedFixtureIDs
        let scope = ordered.isEmpty ? Array(snap.values.keys) : ordered
        let outcome = PaletteCreate.fromProgrammer(
            kind: kind,
            programmerValues: snap.values,
            selectedFixtureIDs: ordered,
            existingPaletteCount: context.project.palettes.filter { $0.type == kind.paletteType }.count,
            capabilityMap: capabilityMap(for: scope)
        )
        statusText = PaletteCreate.statusMessage(for: outcome)
        guard case .created(let palette, _) = outcome else { return }
        do {
            try context.session.perform(AddPaletteCommand(palette: palette))
            onInspectPalette(palette.id)
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func createLook() {
        let levels = programmer.captureLevels()
        guard !levels.fixtures.isEmpty else {
            statusText = "Programmer empty — set values before creating a look"
            return
        }
        let preset = Preset(
            name: "Look \(context.project.presets.count + 1)",
            levels: levels
        )
        do {
            try context.session.perform(AddPresetCommand(preset: preset))
            statusText = "Created \(preset.name)"
            onInspectPreset(preset.id)
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    // MARK: - Apply

    private func apply(_ palette: Palette) {
        let ids = Array(context.session.selection.snapshot.fixtureIDs)
        guard !ids.isEmpty else {
            statusText = "Select fixtures first"
            return
        }
        guard !palette.values.isEmpty else {
            statusText = "Palette \(palette.name) has no values — apply aborted"
            return
        }
        // CR-01: only write attributes each fixture supports.
        let caps = capabilityMap(for: ids)
        var batch: [UUID: [String: Double]] = [:]
        var skipped = 0
        for id in ids {
            let filtered = PaletteCreate.filterValues(palette.values, supported: caps[id] ?? [])
            if filtered.isEmpty {
                skipped += 1
            } else {
                batch[id] = filtered
            }
        }
        guard !batch.isEmpty else {
            statusText = "No capable fixtures for \(palette.name)"
            return
        }
        programmer.setMany(batch)
        var msg = "Applied \(palette.name) to \(batch.count) capable fixture(s)"
        if skipped > 0 {
            msg += " · skipped \(skipped) unsupported"
        }
        statusText = msg
        onChanged()
    }

    private func applyPreset(_ preset: Preset) {
        let selection = context.session.selection.snapshot.fixtureIDs
        guard !selection.isEmpty else {
            statusText = "Select fixtures first"
            return
        }
        let resolved = PaletteResolver.resolve(levels: preset.levels, project: context.project)
        // P1: same capability filter as palette Apply.
        let caps = capabilityMap(for: Array(selection))
        var batch: [UUID: [String: Double]] = [:]
        var skipped = 0
        for fx in resolved.levels.fixtures {
            guard selection.contains(fx.fixtureId), !fx.attributes.isEmpty else { continue }
            let filtered = PaletteCreate.filterValues(fx.attributes, supported: caps[fx.fixtureId] ?? [])
            if filtered.isEmpty {
                skipped += 1
            } else {
                batch[fx.fixtureId] = filtered
            }
        }
        if batch.isEmpty {
            if preset.levels.fixtures.isEmpty {
                statusText = "Look \(preset.name) is empty — create from programmer"
            } else {
                statusText = "Look \(preset.name) applied nothing (no capable attrs)"
            }
            if !resolved.issues.isEmpty {
                statusText = (statusText ?? "") + " · \(resolved.issues.count) resolution issue(s)"
            }
            return
        }
        programmer.setMany(batch)
        var msg = "Applied \(preset.name) to \(batch.count) capable fixture(s)"
        if skipped > 0 {
            msg += " · skipped \(skipped) unsupported"
        }
        if !resolved.issues.isEmpty {
            msg += " · \(resolved.issues.count) resolution issue(s)"
        }
        statusText = msg
        onChanged()
    }

    // MARK: - Record Ref (A1 — existing path only)

    private func recordRef(_ palette: Palette) {
        let selectedFixtures = context.session.selection.snapshot.fixtureIDs
        guard !selectedFixtures.isEmpty else {
            statusText = "Select fixtures before Record Ref"
            return
        }

        // CR-02: only fixtures that support palette attribute keys.
        let caps = capabilityMap(for: Array(selectedFixtures))
        let compatible = PaletteCreate.compatibleFixtureIDs(
            selection: selectedFixtures,
            values: palette.values,
            capabilityMap: caps
        )
        let skippedUnsupported = selectedFixtures.count - compatible.count
        guard !compatible.isEmpty else {
            statusText = "No capable fixtures for Record Ref"
            return
        }

        let targets = context.project.targetCuesForPaletteRecord(
            selectedCueIDs: context.session.selection.snapshot.cueIDs
        )
        guard !targets.isEmpty else {
            statusText = "No cue available — add a cue list and cue first (UI-05)"
            return
        }

        // CR-04: multi-cue Record Ref is one undo group.
        do {
            try context.session.beginGroup(named: "Record Palette Reference")
            var updatedNames: [String] = []
            for (listID, var cue) in targets {
                cue.recordPaletteRef(palette: palette, fixtureIDs: compatible)
                try context.session.perform(UpdateCueCommand(listID: listID, cue: cue))
                let name = cue.name.isEmpty ? "Cue \(cue.number)" : cue.name
                updatedNames.append(name)
            }
            try context.session.endGroup()
            let usedSelection = !context.session.selection.snapshot.cueIDs.isEmpty
            var msg = "Ref \(palette.name) → \(updatedNames.joined(separator: ", "))"
                + (usedSelection ? "" : " (fallback: first cue)")
                + " · \(compatible.count) fixture(s)"
            if skippedUnsupported > 0 {
                msg += " · skipped \(skippedUnsupported) unsupported"
            }
            statusText = msg
            onProjectChanged()
        } catch {
            try? context.session.cancelGroup()
            statusText = error.localizedDescription
        }
    }

    // MARK: - Delete

    private var deletePaletteTitle: String {
        if let p = palettePendingDelete {
            return "Delete “\(p.name)”?"
        }
        return "Delete palette?"
    }

    private var deletePaletteMessage: String {
        guard let p = palettePendingDelete else { return "" }
        let count = context.project.paletteReferenceCount(p.id)
        if count == 0 {
            return "This palette is not referenced by any cue or preset."
        }
        let sites = context.project.paletteReferenceCueSummaries(p.id)
        let preview = sites.prefix(5).joined(separator: "\n")
        let more = sites.count > 5 ? "\n…and \(sites.count - 5) more" : ""
        return "Referenced in \(count) fixture slot(s). Cues/presets will keep broken refs until fixed:\n\(preview)\(more)"
    }

    private var deletePresetTitle: String {
        if let p = presetPendingDelete {
            return "Delete “\(p.name)”?"
        }
        return "Delete look?"
    }

    private func requestDeletePalette(_ palette: Palette) {
        palettePendingDelete = palette
        showDeletePaletteConfirm = true
    }

    private func requestDeletePreset(_ preset: Preset) {
        presetPendingDelete = preset
        showDeletePresetConfirm = true
    }

    private func performDeletePalette(_ palette: Palette) {
        do {
            try context.session.perform(RemovePaletteCommand(paletteID: palette.id))
            if focusedPaletteID == palette.id {
                onClearInspector()
            }
            statusText = "Deleted \(palette.name)"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func performDeletePreset(_ preset: Preset) {
        do {
            try context.session.perform(RemovePresetCommand(presetID: preset.id))
            if focusedPresetID == preset.id {
                onClearInspector()
            }
            statusText = "Deleted \(preset.name)"
            onProjectChanged()
        } catch {
            statusText = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func color(from palette: Palette) -> Color {
        if palette.type == .intensity {
            let v = palette.values["intensity"] ?? 0.5
            return Color(white: v)
        }
        let r = palette.values["colorR"] ?? 0.5
        let g = palette.values["colorG"] ?? r
        let b = palette.values["colorB"] ?? r * 0.6
        return Color(red: r, green: g, blue: b)
    }
}
