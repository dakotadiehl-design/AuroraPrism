import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

public struct PalettesPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var onChanged: () -> Void

    @State private var statusText: String?
    @State private var palettePendingDelete: Palette?
    @State private var showDeleteConfirm = false

    public init(context: WorkspacePanelContext, programmer: Programmer, onChanged: @escaping () -> Void = {}) {
        self.context = context
        self.programmer = programmer
        self.onChanged = onChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Palettes").font(.headline)
                Spacer()
                Button("New Color from Prog") { createColorPalette() }
            }
            List(context.project.palettes) { palette in
                HStack {
                    VStack(alignment: .leading) {
                        Text(palette.name)
                        Text(palette.type.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply") { apply(palette) }
                    Button("Record Ref to Cue") { recordRef(palette) }
                    Button("Delete", role: .destructive) {
                        requestDelete(palette)
                    }
                }
            }
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !context.project.validateReferences().isEmpty {
                Text("⚠ \(context.project.validateReferences().count) broken palette ref(s)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Palette", role: .destructive) {
                if let palette = palettePendingDelete {
                    performDelete(palette)
                }
                palettePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                palettePendingDelete = nil
            }
        } message: {
            Text(deleteDialogMessage)
        }
    }

    private var deleteDialogTitle: String {
        if let p = palettePendingDelete {
            return "Delete “\(p.name)”?"
        }
        return "Delete palette?"
    }

    private var deleteDialogMessage: String {
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

    private func createColorPalette() {
        let snap = programmer.snapshot()
        var values: [String: Double] = [:]
        if let first = snap.values.values.first {
            for key in ["colorR", "colorG", "colorB", "colorW", "intensity"] {
                if let v = first[key] { values[key] = v }
            }
        }
        if values.isEmpty {
            values = ["colorR": 1, "colorG": 0.47, "colorB": 0.12]
        }
        let palette = Palette(
            name: "Palette \(context.project.palettes.count + 1)",
            type: .color,
            values: values
        )
        try? context.session.perform(AddPaletteCommand(palette: palette))
        statusText = "Created \(palette.name)"
        onChanged()
    }

    private func apply(_ palette: Palette) {
        let ids = context.session.selection.snapshot.fixtureIDs
        guard !ids.isEmpty else {
            statusText = "Select fixtures before Apply"
            return
        }
        for id in ids {
            for (attr, value) in palette.values {
                programmer.set(fixtureID: id, attribute: attr, value: value)
            }
        }
        statusText = "Applied \(palette.name) to \(ids.count) fixture(s)"
        onChanged()
    }

    /// Stores palette *references* on selected cue(s) for selected fixtures.
    /// Falls back to first cue of first list if no cue is selected (session selection).
    private func recordRef(_ palette: Palette) {
        let selectedFixtures = context.session.selection.snapshot.fixtureIDs
        guard !selectedFixtures.isEmpty else {
            statusText = "Select fixtures before Record Ref"
            return
        }

        let targets = context.project.targetCuesForPaletteRecord(
            selectedCueIDs: context.session.selection.snapshot.cueIDs
        )
        guard !targets.isEmpty else {
            statusText = "No cue available — add a cue list and cue first"
            return
        }

        var updatedNames: [String] = []
        for (listID, var cue) in targets {
            cue.recordPaletteRef(palette: palette, fixtureIDs: selectedFixtures)
            do {
                try context.session.perform(UpdateCueCommand(listID: listID, cue: cue))
                let name = cue.name.isEmpty ? "Cue \(cue.number)" : cue.name
                updatedNames.append(name)
            } catch {
                statusText = error.localizedDescription
                return
            }
        }
        let usedSelection = !context.session.selection.snapshot.cueIDs.isEmpty
        statusText = "Ref \(palette.name) → \(updatedNames.joined(separator: ", "))"
            + (usedSelection ? "" : " (fallback: first cue)")
            + " · \(selectedFixtures.count) fixture(s)"
        onChanged()
    }

    private func requestDelete(_ palette: Palette) {
        palettePendingDelete = palette
        showDeleteConfirm = true
    }

    private func performDelete(_ palette: Palette) {
        try? context.session.perform(RemovePaletteCommand(paletteID: palette.id))
        statusText = "Deleted \(palette.name)"
        onChanged()
    }
}
