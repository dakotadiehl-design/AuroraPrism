import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// Dominant Build-mode Programmer using UI-01C controls (UI-02A).
public struct ProgrammerPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var project: ShowProject
    public var onChanged: () -> Void

    @State private var intensity: Double = 0
    @State private var colorR: Double = 0
    @State private var colorG: Double = 0
    @State private var colorB: Double = 0
    @State private var colorW: Double = 0
    @State private var pan: Double = 0.5
    @State private var tilt: Double = 0.5
    @State private var hue: Double = 0.08
    @State private var sat: Double = 0.8
    @State private var val: Double = 1

    public init(
        context: WorkspacePanelContext,
        programmer: Programmer,
        project: ShowProject,
        onChanged: @escaping () -> Void = {}
    ) {
        self.context = context
        self.programmer = programmer
        self.project = project
        self.onChanged = onChanged
    }

    private var selectedIDs: [UUID] {
        Array(context.session.selection.snapshot.orderedFixtureIDs)
    }

    private var availableAttributes: Set<String> {
        var tags = Set<String>()
        for id in selectedIDs {
            guard let fixture = project.fixtures.first(where: { $0.id == id }),
                  let def = project.definition(id: fixture.definitionId)
            else { continue }
            tags.formUnion(def.channels.map(\.attribute))
        }
        return tags
    }

    private var state: ProgrammerState { programmer.snapshot() }
    private var hasColor: Bool {
        availableAttributes.contains("colorR")
            || availableAttributes.contains("colorG")
            || availableAttributes.contains("colorB")
    }
    private var hasPosition: Bool {
        availableAttributes.contains("pan") || availableAttributes.contains("tilt")
    }

    public var body: some View {
        if selectedIDs.isEmpty {
            AuroraEmptyState(
                title: "No selection",
                detail: "Select fixtures in the browser to create a look.",
                systemImage: "slider.horizontal.3"
            )
            .background(AuroraColor.surfacePanel)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: AuroraSpacing.md) {
                    headerBar
                    HStack(alignment: .top, spacing: AuroraSpacing.lg) {
                        if availableAttributes.contains("intensity") {
                            AuroraFader(
                                value: intensityBinding,
                                label: "Intensity",
                                iconName: AuroraLightingIcon.intensity.rawValue,
                                showsOwnedChrome: true
                            )
                        }
                        if hasPosition {
                            AuroraPositionPad(pan: panBinding, tilt: tiltBinding)
                        }
                        if hasColor {
                            AuroraColorWheel(hue: $hue, saturation: $sat, brightness: val, size: 120)
                                .onChange(of: hue) { _, _ in applyHSV() }
                                .onChange(of: sat) { _, _ in applyHSV() }
                        }
                        if hasColor {
                            AuroraBeamWell(label: "Beam", zoom: intensity, isSelected: false)
                        }
                    }
                    fixtureChips
                    toolRow
                }
                .padding(AuroraSpacing.md)
            }
            .background(AuroraColor.surfacePanel)
            .onAppear { loadFromProgrammer() }
            .onChange(of: context.session.selection.snapshot.fixtureIDs) { _, _ in
                loadFromProgrammer()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("\(selectedIDs.count) fixtures")
                .font(AuroraTypography.sectionHeading)
                .foregroundStyle(AuroraColor.accentBright)
            Text(selectedNames)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(1)
            Spacer()
            Toggle("Blind", isOn: Binding(
                get: { state.isBlind },
                set: { programmer.setBlind($0); onChanged() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            Toggle("HL", isOn: Binding(
                get: { state.isHighlight },
                set: { programmer.setHighlight($0); onChanged() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Highlight")
        }
    }

    private var selectedNames: String {
        let names = selectedIDs.prefix(4).compactMap { id in
            project.fixtures.first(where: { $0.id == id })?.name
        }
        let extra = selectedIDs.count > 4 ? " +\(selectedIDs.count - 4)" : ""
        return names.joined(separator: ", ") + extra
    }

    private var fixtureChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(selectedIDs, id: \.self) { id in
                    let name = project.fixtures.first(where: { $0.id == id })?.name ?? "·"
                    AuroraFixtureChip(name: name, isSelected: true)
                }
            }
        }
    }

    private var toolRow: some View {
        HStack(spacing: 8) {
            AuroraButton("Locate", kind: .secondary) {
                programmer.locate(fixtureIDs: Set(selectedIDs), project: project)
                loadFromProgrammer()
                onChanged()
            }
            AuroraButton("Home", kind: .secondary) {
                programmer.home(fixtureIDs: Set(selectedIDs), project: project)
                loadFromProgrammer()
                onChanged()
            }
            AuroraButton("Clear", kind: .quiet) {
                programmer.clear(fixtureIDs: Set(selectedIDs))
                loadFromProgrammer()
                onChanged()
            }
            Spacer()
        }
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { intensity },
            set: { newValue in
                intensity = newValue
                apply(attribute: "intensity", value: newValue)
            }
        )
    }

    private var panBinding: Binding<Double> {
        Binding(
            get: { pan },
            set: { newValue in
                pan = newValue
                apply(attribute: "pan", value: newValue)
            }
        )
    }

    private var tiltBinding: Binding<Double> {
        Binding(
            get: { tilt },
            set: { newValue in
                tilt = newValue
                apply(attribute: "tilt", value: newValue)
            }
        )
    }

    private func applyHSV() {
        let rgb = ColorMath.rgb(from: HSVColor(h: hue * 360, s: sat, v: val))
        let includeW = availableAttributes.contains("colorW")
        let attrs = ColorMath.programmerAttributes(from: rgb, includeWhite: includeW)
        for id in selectedIDs {
            for (k, v) in attrs {
                programmer.set(fixtureID: id, attribute: k, value: v)
            }
        }
        colorR = attrs["colorR"] ?? 0
        colorG = attrs["colorG"] ?? 0
        colorB = attrs["colorB"] ?? 0
        colorW = attrs["colorW"] ?? 0
        onChanged()
    }

    private func apply(attribute: String, value: Double) {
        let ordered = selectedIDs
        let map = ProgrammerGeometry.align(fixtureIDs: ordered, value: value)
        programmer.setMany(attribute: attribute, values: map)
        onChanged()
    }

    private func loadFromProgrammer() {
        let snap = programmer.snapshot()
        guard let first = selectedIDs.first else { return }
        let attrs = snap.values[first] ?? [:]
        intensity = attrs["intensity"] ?? 0
        colorR = attrs["colorR"] ?? 0
        colorG = attrs["colorG"] ?? 0
        colorB = attrs["colorB"] ?? 0
        colorW = attrs["colorW"] ?? 0
        pan = attrs["pan"] ?? 0.5
        tilt = attrs["tilt"] ?? 0.5
        let hsv = ColorMath.hsv(from: RGBColor(r: colorR, g: colorG, b: colorB))
        hue = hsv.h / 360
        sat = hsv.s
        val = hsv.v
    }
}
