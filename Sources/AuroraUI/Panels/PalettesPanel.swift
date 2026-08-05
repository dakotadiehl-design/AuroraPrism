import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// Visual palette / look shelf (UI-02A).
public struct PalettesPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var onChanged: () -> Void
    public var onInspectPalette: (UUID) -> Void
    public var onInspectPreset: (UUID) -> Void

    @State private var statusText: String?

    public init(
        context: WorkspacePanelContext,
        programmer: Programmer,
        onChanged: @escaping () -> Void = {},
        onInspectPalette: @escaping (UUID) -> Void = { _ in },
        onInspectPreset: @escaping (UUID) -> Void = { _ in }
    ) {
        self.context = context
        self.programmer = programmer
        self.onChanged = onChanged
        self.onInspectPalette = onInspectPalette
        self.onInspectPreset = onInspectPreset
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraSpacing.sm) {
                if context.project.palettes.isEmpty && context.project.presets.isEmpty {
                    AuroraEmptyState(
                        title: "No palettes",
                        detail: "Create color or position palettes from the programmer.",
                        systemImage: "paintpalette"
                    )
                    .frame(height: 120)
                } else {
                    colorSection
                    positionSection
                    otherSection
                    if !context.project.presets.isEmpty {
                        presetsSection
                    }
                }
                if let statusText {
                    Text(statusText)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
            }
            .padding(8)
        }
        .background(AuroraColor.surfacePanel)
    }

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
                AuroraSectionHeader("Colors")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(colorPalettes) { palette in
                            AuroraPaletteTile(
                                name: palette.name,
                                swatch: color(from: palette),
                                kind: .color,
                                action: {
                                    onInspectPalette(palette.id)
                                    apply(palette)
                                }
                            )
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
                            AuroraPaletteTile(
                                name: palette.name,
                                kind: .position,
                                positionSymbol: "scope",
                                action: {
                                    onInspectPalette(palette.id)
                                    apply(palette)
                                }
                            )
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
                            AuroraPaletteTile(
                                name: palette.name,
                                kind: palette.type == .gobo ? .gobo : .beam,
                                action: {
                                    onInspectPalette(palette.id)
                                    apply(palette)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            AuroraSectionHeader("Looks")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(context.project.presets) { preset in
                        AuroraLookTile(name: preset.name, action: {
                            onInspectPreset(preset.id)
                            applyPreset(preset)
                        })
                    }
                }
            }
        }
    }

    private func color(from palette: Palette) -> Color {
        let r = palette.values["colorR"] ?? palette.values["intensity"] ?? 0.5
        let g = palette.values["colorG"] ?? r
        let b = palette.values["colorB"] ?? r * 0.6
        return Color(red: r, green: g, blue: b)
    }

    private func apply(_ palette: Palette) {
        let ids = context.session.selection.snapshot.fixtureIDs
        guard !ids.isEmpty else {
            statusText = "Select fixtures first"
            return
        }
        for id in ids {
            for (attr, value) in palette.values {
                programmer.set(fixtureID: id, attribute: attr, value: value)
            }
        }
        statusText = "Applied \(palette.name)"
        onChanged()
    }

    private func applyPreset(_ preset: Preset) {
        let ids = context.session.selection.snapshot.fixtureIDs
        guard !ids.isEmpty else {
            statusText = "Select fixtures first"
            return
        }
        for fl in preset.levels.fixtures where ids.contains(fl.fixtureId) {
            for (attr, value) in fl.attributes {
                programmer.set(fixtureID: fl.fixtureId, attribute: attr, value: value)
            }
        }
        statusText = "Applied look \(preset.name)"
        onChanged()
    }
}
