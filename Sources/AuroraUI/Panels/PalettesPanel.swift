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
                    Button("Delete", role: .destructive) {
                        try? context.session.perform(RemovePaletteCommand(paletteID: palette.id))
                        onChanged()
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
}
