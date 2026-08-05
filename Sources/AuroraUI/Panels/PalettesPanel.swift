import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

public struct PalettesPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var onChanged: () -> Void

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
                        deletePalette(palette)
                    }
                }
            }
            if !context.project.validateReferences().isEmpty {
                Text("⚠ \(context.project.validateReferences().count) broken palette ref(s)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
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
        onChanged()
    }

    private func apply(_ palette: Palette) {
        let ids = context.session.selection.snapshot.fixtureIDs
        guard !ids.isEmpty else { return }
        for id in ids {
            for (attr, value) in palette.values {
                programmer.set(fixtureID: id, attribute: attr, value: value)
            }
        }
        onChanged()
    }

    /// Stores a palette *reference* on the first cue of the first list for selected fixtures (PDF workflow).
    private func recordRef(_ palette: Palette) {
        guard let list = context.project.cueLists.first,
              var cue = list.cues.first
        else { return }
        let selected = context.session.selection.snapshot.fixtureIDs
        guard !selected.isEmpty else { return }
        var fixtures = cue.levels.fixtures
        for id in selected {
            if let idx = fixtures.firstIndex(where: { $0.fixtureId == id }) {
                fixtures[idx].paletteRefs[palette.type.rawValue] = palette.id
            } else {
                fixtures.append(FixtureCueLevels(fixtureId: id, paletteRefs: [palette.type.rawValue: palette.id]))
            }
        }
        cue.levels = CueLevelData(fixtures: fixtures)
        try? context.session.perform(UpdateCueCommand(listID: list.id, cue: cue))
        onChanged()
    }

    private func deletePalette(_ palette: Palette) {
        if context.project.isPaletteReferenced(palette.id) {
            // Soft warn via status: caller may not have NSAlert; still allow with validation flags.
        }
        try? context.session.perform(RemovePaletteCommand(paletteID: palette.id))
        onChanged()
    }
}
