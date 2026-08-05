import SwiftUI

/// UI-01C gallery — render-pack visual identity lock.
/// `#Preview("Aurora Component Gallery")` for human review. No AppModel.
public struct AuroraComponentGallery: View {
    @State private var mode: AuroraWorkspaceChromeMode = .build
    @State private var workspaceTab = "Patch"
    @State private var search = ""
    @State private var dimmer: Double = 0.68
    @State private var intensity: Double = 1.0
    @State private var pan: Double = 0.55
    @State private var tilt: Double = 0.45
    @State private var hue: Double = 0.92
    @State private var sat: Double = 0.75
    @State private var selectedFixture = "Spot 3"
    @State private var settingsNav = "MIDI"
    @State private var gm: Double = 1.0
    @State private var stage: Double = 1.0
    @State private var audience: Double = 0.3
    @State private var fx: Double = 1.0

    private let workspaceTabs = ["Patch", "Groups", "Palettes", "Cues", "Sequences", "Effects"]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraSpacing.xxl) {
                header
                tokenBoard
                buildWorkspace
                detailedProgrammer
                paletteShelf
                cueListBoard
                performCockpit
                midiSettings
            }
            .padding(AuroraSpacing.xl)
        }
        .background(AuroraColor.surfaceBase)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .foregroundStyle(AuroraColor.accentBright)
                    .rotationEffect(.degrees(45))
                Text("AURORA")
                    .font(AuroraTypography.wordmark)
                    .tracking(1.5)
                Text("UI-01C Visual Identity")
                    .font(AuroraTypography.windowTitle)
                    .foregroundStyle(AuroraColor.textSecondary)
            }
            Text("Render-pack target — lock design language before UI-02. Visual intent, not pixel-perfect.")
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textTertiary)
        }
    }

    // MARK: Tokens

    private var tokenBoard: some View {
        section("Token board") {
            HStack(spacing: 0) {
                surfaceSwatch("Base", AuroraColor.surfaceBase)
                surfaceSwatch("Workspace", AuroraColor.surfaceWorkspace)
                surfaceSwatch("Panel", AuroraColor.surfacePanel)
                surfaceSwatch("Raised", AuroraColor.surfaceRaised)
                surfaceSwatch("Selected", AuroraColor.surfaceSelected)
                surfaceSwatch("Accent", AuroraColor.accent)
                surfaceSwatch("GO", AuroraColor.goGreen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            AuroraAttributeStateLegend()
        }
    }

    private func surfaceSwatch(_ name: String, _ color: Color) -> some View {
        VStack {
            Spacer()
            Text(name.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(AuroraColor.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(color)
    }

    // MARK: 1 — Build Mode mini-workspace

    private var buildWorkspace: some View {
        section("1 · Build Mode — main workspace (north star)") {
            VStack(spacing: 0) {
                AuroraAppToolbar(
                    projectTitle: "Summer Night Show.aurora",
                    healthSummary: "Art-Net · Output OK",
                    mode: $mode
                )

                // Main rows
                HStack(alignment: .top, spacing: 1) {
                    fixtureBrowser
                        .frame(width: 168)
                    centerColumn
                    inspectorColumn
                        .frame(width: 168)
                }
                .frame(minHeight: 420)

                // Lower: palettes + cues
                HStack(alignment: .top, spacing: 1) {
                    palettePanel
                        .frame(width: 200)
                    cuePanel
                    cueDetailPanel
                        .frame(width: 200)
                }
                .frame(height: 180)

                AuroraStatusBar(
                    items: [
                        .init(label: "sACN", level: .healthy),
                        .init(label: "Art-Net", level: .healthy),
                        .init(label: "Output 3/3", level: .healthy),
                    ],
                    trailing: "FPS 40 · Frame 25ms"
                )
            }
            .background(AuroraColor.surfaceWorkspace)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AuroraColor.separatorStrong, lineWidth: 0.5)
            )
        }
    }

    private var fixtureBrowser: some View {
        VStack(spacing: 0) {
            AuroraPanelHeader(title: "Fixture Browser")
            AuroraSearchField(text: $search, placeholder: "Search fixtures…")
                .padding(6)
            VStack(alignment: .leading, spacing: 0) {
                treeRow("All Fixtures", count: "128", depth: 0, selected: false, disclosure: true)
                treeRow("Stage", count: "82", depth: 1, selected: false, disclosure: true)
                treeRow("Front Wash", count: "16", depth: 2, selected: false, disclosure: false)
                treeRow("Back Wash", count: "16", depth: 2, selected: false, disclosure: false)
                treeRow("Specials", count: "16", depth: 1, selected: false, disclosure: true)
                treeRow("Spot 1", count: "001", depth: 2, selected: false, disclosure: false)
                treeRow("Spot 2", count: "002", depth: 2, selected: false, disclosure: false)
                treeRow("Spot 3", count: "003", depth: 2, selected: true, disclosure: false)
                treeRow("Spot 4", count: "004", depth: 2, selected: true, disclosure: false)
                treeRow("Unpatched", count: "0", depth: 0, selected: false, disclosure: false)
            }
            Spacer(minLength: 0)
        }
        .background(AuroraColor.surfacePanel)
    }

    private func treeRow(_ name: String, count: String, depth: Int, selected: Bool, disclosure: Bool) -> some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(depth) * 10)
            if disclosure {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AuroraColor.textTertiary)
            } else {
                Color.clear.frame(width: 8)
            }
            Text(name)
                .font(AuroraTypography.secondary)
                .foregroundStyle(selected ? AuroraColor.textPrimary : AuroraColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(count)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(selected ? AuroraColor.surfaceSelected : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(AuroraColor.accent).frame(width: 2)
            }
        }
    }

    private var centerColumn: some View {
        VStack(spacing: 0) {
            AuroraWorkspaceTabs(tabs: workspaceTabs, selection: $workspaceTab)
            programmerCore
                .frame(maxHeight: .infinity)
        }
        .background(AuroraColor.surfacePanel)
    }

    private var programmerCore: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Programmer")
                    .font(AuroraTypography.panelTitle)
                    .foregroundStyle(AuroraColor.textSecondary)
                Spacer()
                Text("Fixtures: 4 Selected")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.accentBright)
                AuroraButton("Clear", kind: .quiet, action: {})
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(AuroraColor.surfaceHeader)

            HStack(alignment: .top, spacing: 12) {
                AuroraFader(value: $dimmer, label: "Dimmer", showsOwnedChrome: true)
                AuroraFader(value: $intensity, label: "Intensity", showsOwnedChrome: true)
                AuroraPositionPad(pan: $pan, tilt: $tilt)
                AuroraColorWheel(hue: $hue, saturation: $sat, size: 110)
                AuroraBeamWell(zoom: 0.38)
                AuroraGoboMatrix(selected: 2)
            }
            .padding(10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(["Spot 1", "Spot 2", "Spot 3", "Spot 4", "Spot 5", "Wash 1"], id: \.self) { name in
                        AuroraFixtureChip(name: name, isSelected: name == selectedFixture || name == "Spot 4") {
                            selectedFixture = name
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var inspectorColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuroraPanelHeader(title: "Inspector") {
                Text("4 Selected")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    chipTab("Fixture", true)
                    chipTab("Cue", false)
                    chipTab("Effect", false)
                }
                inspectorField("Fixture Type", "VL3500 Spot")
                inspectorField("Mode", "Standard 16ch")
                inspectorField("DMX Address", "1")
                inspectorField("Universe", "1")
                AuroraSectionHeader("Capabilities")
                ForEach(["Pan / Tilt", "Color", "Gobos", "Prism", "Frost", "Zoom", "Dimmer"], id: \.self) { cap in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AuroraColor.stateTracking)
                        Text(cap)
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textSecondary)
                    }
                }
            }
            .padding(8)
            Spacer(minLength: 0)
        }
        .background(AuroraColor.surfacePanel)
    }

    private func chipTab(_ title: String, _ on: Bool) -> some View {
        Text(title)
            .font(AuroraTypography.metadata)
            .foregroundStyle(on ? AuroraColor.textPrimary : AuroraColor.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(on ? AuroraColor.accentMuted : AuroraColor.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func inspectorField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(value)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(AuroraColor.surfaceWell)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private var palettePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Palettes")
            VStack(alignment: .leading, spacing: 6) {
                Text("Colors")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 3) {
                    AuroraPaletteSwatch(color: .red)
                    AuroraPaletteSwatch(color: .orange)
                    AuroraPaletteSwatch(color: .yellow)
                    AuroraPaletteSwatch(color: .green)
                    AuroraPaletteSwatch(color: .cyan)
                    AuroraPaletteSwatch(color: .blue)
                    AuroraPaletteSwatch(color: .purple)
                    AuroraPaletteSwatch(color: .pink)
                }
                Text("Beams")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 2) {
                    AuroraBeamPaletteIcon(name: "N", systemImage: "circle")
                    AuroraBeamPaletteIcon(name: "M", systemImage: "circle.circle")
                    AuroraBeamPaletteIcon(name: "W", systemImage: "circle.dotted")
                    AuroraBeamPaletteIcon(name: "O", systemImage: "oval")
                }
                Text("Looks")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 4) {
                    AuroraLookTile(name: "Warm", colors: [.orange, .red.opacity(0.6)])
                    AuroraLookTile(name: "Cool", colors: [.blue, .cyan])
                }
            }
            .padding(6)
            Spacer(minLength: 0)
        }
        .background(AuroraColor.surfacePanel)
    }

    private var cuePanel: some View {
        VStack(spacing: 0) {
            AuroraPanelHeader(title: "Cue List: Opening")
            AuroraTableHeader(columns: [
                .init(id: "n", title: "Cue", width: 40),
                .init(id: "name", title: "Name"),
                .init(id: "trig", title: "Trigger", width: 64),
                .init(id: "t", title: "Fade", width: 48),
            ])
            AuroraCueRow(number: "1", name: "House Down", timing: "3.0s", role: .normal)
            AuroraCueRow(number: "2", name: "Intro Look", timing: "2.0s", trigger: "Timecode", role: .normal)
            AuroraCueRow(number: "3", name: "Verse 1", timing: "1.0s", role: .current)
            AuroraCueRow(number: "4", name: "Chorus 1", timing: "1.5s", role: .next)
            AuroraCueRow(number: "5", name: "Move 1", timing: "1.0s", role: .normal)
            AuroraCueRow(number: "6", name: "Verse 2", timing: "1.0s", role: .warning)
            Spacer(minLength: 0)
        }
        .background(AuroraColor.surfacePanel)
        .auroraDensity(.compact)
    }

    private var cueDetailPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraPanelHeader(title: "Cue 3: Verse 1")
            HStack(spacing: 4) {
                chipTab("Values", true)
                chipTab("Timing", false)
                chipTab("Notes", false)
            }
            .padding(.horizontal, 6)
            // Decorative intensity bars (visual only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Intensities")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<8, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AuroraColor.accent.opacity(0.5 + Double(i % 3) * 0.15))
                            .frame(width: 12, height: CGFloat(20 + (i * 7) % 40))
                    }
                }
                .frame(height: 60, alignment: .bottom)
                Text("Color Over Time")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue, .cyan, .yellow, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
            }
            .padding(8)
            Spacer(minLength: 0)
        }
        .background(AuroraColor.surfacePanel)
    }

    // MARK: 2 — Detailed Programmer

    private var detailedProgrammer: some View {
        section("2 · Programmer — detailed controls") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    AuroraFader(value: $dimmer, label: "Dimmer", showsOwnedChrome: true)
                    AuroraFader(value: $intensity, label: "Intensity", showsOwnedChrome: true)
                    AuroraPositionPad(pan: $pan, tilt: $tilt)
                    AuroraColorWheel(hue: $hue, saturation: $sat)
                    AuroraBeamWell(zoom: 0.38, isSelected: true)
                    AuroraGoboMatrix(selected: 3)
                }
                .padding(12)
                .background(AuroraColor.surfacePanel)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Attribute States Legend")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                AuroraAttributeStateLegend()
            }
        }
    }

    // MARK: 3 — Palette shelf

    private var paletteShelf: some View {
        section("3 · Palettes & presets") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Color Palettes")
                    .font(AuroraTypography.sectionHeading)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 8) {
                    AuroraPaletteTile(name: "Stage Wash", swatch: Color(red: 1, green: 0.35, blue: 0.15))
                    AuroraPaletteTile(name: "Deep Blue", swatch: Color(red: 0.1, green: 0.2, blue: 0.85), isSelected: true)
                    AuroraPaletteTile(name: "Sunset", swatch: Color(red: 1, green: 0.55, blue: 0.2))
                    AuroraPaletteTile(name: "Pastel", swatch: Color(red: 0.85, green: 0.7, blue: 0.95))
                    AuroraPaletteTile(name: "Neon", swatch: Color(red: 0.2, green: 0.95, blue: 0.7))
                    AuroraPaletteTile(name: "Greyscale", swatch: Color(red: 0.55, green: 0.55, blue: 0.55))
                }
                Text("Beam Palettes")
                    .font(AuroraTypography.sectionHeading)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 6) {
                    AuroraBeamPaletteIcon(name: "Narrow", systemImage: "circle.fill", isSelected: true)
                    AuroraBeamPaletteIcon(name: "Medium", systemImage: "circle")
                    AuroraBeamPaletteIcon(name: "Wide", systemImage: "circle.dotted")
                    AuroraBeamPaletteIcon(name: "Oval", systemImage: "oval")
                    AuroraBeamPaletteIcon(name: "Fan", systemImage: "fanblades")
                    AuroraBeamPaletteIcon(name: "Soft", systemImage: "circle.dashed")
                }
                Text("Look Presets")
                    .font(AuroraTypography.sectionHeading)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 8) {
                    AuroraLookTile(name: "Warm Concert", colors: [.orange, .red, .yellow.opacity(0.6)])
                    AuroraLookTile(name: "Cool Theater", colors: [.blue, .cyan, .purple], isSelected: true)
                    AuroraLookTile(name: "Intense", colors: [.red, .purple, .blue])
                    AuroraLookTile(name: "Soft Wash", colors: [.pink.opacity(0.7), .orange.opacity(0.5), .white.opacity(0.4)])
                    AuroraLookTile(name: "High Energy", colors: [.green, .cyan, .yellow])
                    AuroraLookTile(name: "Dreamy", colors: [.purple, .blue, .pink])
                }
            }
            .padding(12)
            .background(AuroraColor.surfacePanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: 4 — Cue list

    private var cueListBoard: some View {
        section("4 · Cue list") {
            VStack(spacing: 0) {
                AuroraTableHeader(columns: [
                    .init(id: "n", title: "Cue", width: 40),
                    .init(id: "name", title: "Name"),
                    .init(id: "trig", title: "Trigger", width: 72),
                    .init(id: "t", title: "Fade", width: 48),
                ])
                AuroraCueRow(number: "1", name: "House Down", timing: "3.0 s", role: .normal)
                AuroraCueRow(number: "2", name: "Intro Look", timing: "2.0 s", trigger: "Timecode", role: .normal)
                AuroraCueRow(number: "3", name: "Verse 1", timing: "1.0 s", role: .current)
                AuroraCueRow(number: "4", name: "Chorus 1", timing: "1.5 s", role: .next)
                AuroraCueRow(number: "5", name: "Solo Spot", timing: "0.5 s", role: .selected)
                AuroraCueRow(number: "6", name: "Blackout — missing target", timing: "1.0 s", role: .warning)
            }
            .frame(maxWidth: 520)
            .background(AuroraColor.surfacePanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .auroraDensity(.compact)
        }
    }

    // MARK: 5 — Perform cockpit

    private var performCockpit: some View {
        section("5 · Perform Mode — stage cockpit") {
            VStack(spacing: 0) {
                // Top chrome
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .foregroundStyle(AuroraColor.accentBright)
                            .rotationEffect(.degrees(45))
                        Text("AURORA")
                            .font(AuroraTypography.wordmark)
                        Text("PERFORM MODE — STAGE COCKPIT")
                            .font(AuroraTypography.status)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                    Spacer()
                    Text("Summer Night Show.aurora")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textSecondary)
                    AuroraModeToggle(mode: .constant(.perform))
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(AuroraColor.surfaceWorkspace)

                HStack(alignment: .top, spacing: 16) {
                    // Song / next
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Song")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                        Text("Opening")
                            .font(AuroraTypography.workspaceTitle)
                        Text("120.0 BPM")
                            .font(AuroraTypography.timingReadout)
                            .foregroundStyle(AuroraColor.textSecondary)
                        Text("Next Cues")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                            .padding(.top, 8)
                        ForEach([("3", "Verse 1", true), ("4", "Chorus 1", false), ("5", "Move 1", false)], id: \.0) { row in
                            HStack {
                                Text(row.0)
                                    .font(AuroraTypography.cueNumber)
                                    .foregroundStyle(row.2 ? AuroraColor.accentBright : AuroraColor.textTertiary)
                                    .frame(width: 20)
                                Text(row.1)
                                    .font(AuroraTypography.secondary)
                                    .foregroundStyle(row.2 ? AuroraColor.textPrimary : AuroraColor.textSecondary)
                            }
                        }
                        Text("Timecode")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                            .padding(.top, 8)
                        Text("01:02:14:11")
                            .font(AuroraTypography.primaryValue)
                            .foregroundStyle(AuroraColor.textPrimary)
                    }
                    .frame(width: 140, alignment: .leading)

                    // Current cue + transport
                    VStack(spacing: 12) {
                        Text("Current Cue")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("3")
                                .font(AuroraTypography.performCueNumber)
                                .foregroundStyle(AuroraColor.textPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Verse 1")
                                    .font(AuroraTypography.performancePrimary)
                                Text("Fade: 1.0s   Delay: 0.0s")
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textTertiary)
                                Text("Next: 4  Chorus 1")
                                    .font(AuroraTypography.secondary)
                                    .foregroundStyle(AuroraColor.textSecondary)
                            }
                        }
                        HStack(spacing: 10) {
                            AuroraTransportButton(kind: .back, action: {})
                            AuroraTransportButton(kind: .pause, action: {})
                            AuroraTransportButton(kind: .go, action: {})
                            AuroraTransportButton(kind: .stop, action: {})
                            AuroraTransportButton(kind: .blackout, useIcon: false, action: {})
                        }
                        .auroraDensity(.performance)

                        HStack(spacing: 8) {
                            ForEach(["All Wash Warm", "All Wash Cool", "Blue Look", "Band Look", "FX Look"], id: \.self) { name in
                                Text(name)
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(AuroraColor.surfaceRaised)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(name == "Blue Look" ? AuroraColor.accent : AuroraColor.separator, lineWidth: 0.5)
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Status column
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                        AuroraStatusIndicator(label: "Output OK", level: .healthy)
                        AuroraStatusIndicator(label: "sACN Active", level: .healthy)
                        AuroraStatusIndicator(label: "Art-Net Active", level: .healthy)
                        AuroraStatusIndicator(label: "Universe 1", level: .healthy)
                        AuroraStatusIndicator(label: "Universe 2", level: .healthy)
                        AuroraStatusIndicator(label: "Universe 3", level: .healthy)
                    }
                    .frame(width: 120, alignment: .leading)
                }
                .padding(16)

                // Masters
                HStack(spacing: 16) {
                    AuroraMasterFader(label: "Grand Master", value: $gm)
                    AuroraMasterFader(label: "Stage Lights", value: $stage)
                    AuroraMasterFader(label: "Audience Lights", value: $audience)
                    AuroraMasterFader(label: "FX", value: $fx)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(AuroraColor.surfacePanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AuroraColor.separatorStrong, lineWidth: 0.5)
            )
        }
    }

    // MARK: 6 — MIDI Settings

    private var midiSettings: some View {
        section("6 · Settings — MIDI Mappings") {
            HStack(alignment: .top, spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(AuroraTypography.panelTitle)
                        .foregroundStyle(AuroraColor.textSecondary)
                        .padding(10)
                    ForEach(
                        [
                            ("General", "gearshape"),
                            ("Audio & Sync", "waveform"),
                            ("MIDI", "pianokeys"),
                            ("OSC", "dot.radiowaves.left.and.right"),
                            ("Art-Net / sACN", "network"),
                            ("Remote", "iphone"),
                            ("Plugins", "puzzlepiece"),
                            ("Advanced", "slider.horizontal.3"),
                        ],
                        id: \.0
                    ) { item in
                        AuroraSidebarItem(
                            title: item.0,
                            systemImage: item.1,
                            isSelected: settingsNav == item.0,
                            action: { settingsNav = item.0 }
                        )
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 150)
                .background(AuroraColor.surfaceHeader)

                // Table
                VStack(spacing: 0) {
                    HStack {
                        Text("MIDI Mappings")
                            .font(AuroraTypography.panelTitle)
                            .foregroundStyle(AuroraColor.textSecondary)
                        Spacer()
                        Text("Device  MPK mini mk3")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                        Circle().fill(AuroraColor.success).frame(width: 6, height: 6)
                        Text("Connected")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.stateTracking)
                        AuroraButton("Test", kind: .secondary, action: {})
                        AuroraButton("Learn", kind: .primary, action: {})
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(AuroraColor.surfaceHeader)

                    AuroraTableHeader(columns: [
                        .init(id: "in", title: "Input", width: 64),
                        .init(id: "type", title: "Type", width: 48),
                        .init(id: "tgt", title: "Target", width: 56),
                        .init(id: "act", title: "Action / Parameter"),
                        .init(id: "min", title: "Min", width: 40),
                        .init(id: "max", title: "Max", width: 40),
                        .init(id: "curve", title: "Curve", width: 48),
                    ])

                    midiRow("Note 36", "Note", "Go", "Fire Next Cue", selected: false)
                    midiRow("Note 37", "Note", "Go", "Fire Previous Cue", selected: false)
                    midiRow("CC 1", "Fader", "Dimmer", "Grand Master", selected: true)
                    midiRow("CC 2", "Fader", "Intensity", "Grand Intensity", selected: false)
                    midiRow("CC 3", "Fader", "Color", "Hue", selected: false)
                    midiRow("CC 4", "Fader", "Color", "Saturation", selected: false)
                    midiRow("CC 5", "Fader", "Position", "Pan", selected: false)
                    midiRow("Note 60", "Note", "Effects", "Strobe Tap", selected: false)

                    HStack {
                        AuroraButton("+ Add Mapping", kind: .secondary, action: {})
                        Spacer()
                        AuroraButton("Import…", kind: .quiet, action: {})
                        AuroraButton("Export…", kind: .quiet, action: {})
                    }
                    .padding(8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                // Mapping inspector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mapping Inspector")
                        .font(AuroraTypography.panelTitle)
                        .foregroundStyle(AuroraColor.textSecondary)
                    inspectorField("Input", "CC 1")
                    inspectorField("Type", "Fader")
                    inspectorField("Target", "Dimmer")
                    inspectorField("Parameter", "Grand Master")
                    inspectorField("Min Value", "0%")
                    inspectorField("Max Value", "100%")
                    inspectorField("Curve", "Linear")
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(width: 160)
                .background(AuroraColor.surfaceHeader)
            }
            .frame(minHeight: 320)
            .background(AuroraColor.surfacePanel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AuroraColor.separatorStrong, lineWidth: 0.5)
            )
        }
    }

    private func midiRow(_ input: String, _ type: String, _ target: String, _ action: String, selected: Bool) -> some View {
        AuroraTableRow(role: selected ? .selected : .normal) {
            HStack(spacing: 0) {
                Text(input).frame(width: 64, alignment: .leading).padding(.horizontal, 6)
                Text(type).frame(width: 48, alignment: .leading).padding(.horizontal, 6)
                Text(target).frame(width: 56, alignment: .leading).padding(.horizontal, 6)
                Text(action).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                Text("0%").frame(width: 40, alignment: .leading).padding(.horizontal, 6)
                Text("100%").frame(width: 40, alignment: .leading).padding(.horizontal, 6)
                Text("Linear").frame(width: 48, alignment: .leading).padding(.horizontal, 6)
            }
            .font(AuroraTypography.tableCell)
            .foregroundStyle(AuroraColor.textPrimary)
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(AuroraTypography.sectionHeading)
                .foregroundStyle(AuroraColor.textTertiary)
                .tracking(0.8)
            content()
        }
    }
}

#if DEBUG
#Preview("Aurora Component Gallery") {
    AuroraComponentGallery()
        .frame(width: 1180, height: 900)
}

#Preview("Build Workspace") {
    ScrollView {
        AuroraComponentGallery()
    }
    .frame(width: 1180, height: 700)
    .preferredColorScheme(.dark)
}

#Preview("Perform Cockpit") {
    AuroraComponentGallery()
        .frame(width: 1100, height: 800)
}
#endif
