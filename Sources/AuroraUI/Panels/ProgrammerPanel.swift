import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// Live programmer editors for the current fixture selection.
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
    @State private var fanStart: Double = 0
    @State private var fanEnd: Double = 1
    @State private var fanAttribute: String = "intensity"
    @State private var hue: Double = 0
    @State private var sat: Double = 1
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
        Array(context.session.selection.snapshot.fixtureIDs)
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

    public var body: some View {
        if selectedIDs.isEmpty {
            PlaceholderPanel(
                title: "Programmer",
                detail: "Select fixtures in the Patch panel to edit live values."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    tools
                    if availableAttributes.contains("intensity") {
                        sliderRow("Intensity", value: $intensity, attribute: "intensity")
                    }
                    if availableAttributes.contains("colorR") || availableAttributes.contains("colorG") || availableAttributes.contains("colorB") {
                        colorSection
                    }
                    if availableAttributes.contains("pan") {
                        sliderRow("Pan", value: $pan, attribute: "pan")
                    }
                    if availableAttributes.contains("tilt") {
                        sliderRow("Tilt", value: $tilt, attribute: "tilt")
                    }
                    fanAlignSection
                }
                .padding(12)
            }
            .onAppear { loadFromProgrammer() }
            .onChange(of: context.session.selection.snapshot.fixtureIDs) { _, _ in
                loadFromProgrammer()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("\(selectedIDs.count) selected")
                .font(.headline)
            Spacer()
            Toggle("Blind", isOn: Binding(
                get: { state.isBlind },
                set: {
                    programmer.setBlind($0)
                    onChanged()
                }
            ))
            .toggleStyle(.switch)
            Toggle("Highlight", isOn: Binding(
                get: { state.isHighlight },
                set: {
                    programmer.setHighlight($0)
                    onChanged()
                }
            ))
            .toggleStyle(.switch)
        }
    }

    private var tools: some View {
        HStack {
            Button("Locate") {
                programmer.locate(fixtureIDs: Set(selectedIDs), project: project)
                loadFromProgrammer()
                onChanged()
            }
            Button("Home") {
                programmer.home(fixtureIDs: Set(selectedIDs), project: project)
                loadFromProgrammer()
                onChanged()
            }
            Button("Clear Sel") {
                programmer.clear(fixtureIDs: Set(selectedIDs))
                loadFromProgrammer()
                onChanged()
            }
            Button("Clear All") {
                programmer.clearAll()
                loadFromProgrammer()
                onChanged()
            }
        }
        .buttonStyle(.bordered)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color (HSV)").font(.subheadline.weight(.semibold))
            HStack {
                Text("H")
                Slider(value: $hue, in: 0...360)
            }
            HStack {
                Text("S")
                Slider(value: $sat, in: 0...1)
            }
            HStack {
                Text("V")
                Slider(value: $val, in: 0...1)
            }
            .onChange(of: hue) { _, _ in applyHSV() }
            .onChange(of: sat) { _, _ in applyHSV() }
            .onChange(of: val) { _, _ in applyHSV() }
            sliderRow("Red", value: $colorR, attribute: "colorR")
            sliderRow("Green", value: $colorG, attribute: "colorG")
            sliderRow("Blue", value: $colorB, attribute: "colorB")
            if availableAttributes.contains("colorW") {
                sliderRow("White", value: $colorW, attribute: "colorW")
            }
        }
    }

    private func applyHSV() {
        let rgb = ColorMath.rgb(from: HSVColor(h: hue, s: sat, v: val))
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

    private var fanAlignSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fan / Align")
                .font(.subheadline.weight(.semibold))
            Picker("Attribute", selection: $fanAttribute) {
                ForEach(Array(availableAttributes).sorted(), id: \.self) { attr in
                    Text(attr).tag(attr)
                }
            }
            HStack {
                Text("Fan")
                Slider(value: $fanStart, in: 0...1)
                Slider(value: $fanEnd, in: 0...1)
                Button("Apply Fan") { applyFan() }
            }
            HStack {
                Text("Align")
                Slider(value: $intensity, in: 0...1)
                Button("Apply Align") { applyAlign() }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, attribute: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1) { editing in
                if !editing {
                    apply(attribute: attribute, value: value.wrappedValue)
                }
            }
            .onChange(of: value.wrappedValue) { _, newValue in
                apply(attribute: attribute, value: newValue)
            }
        }
    }

    private func apply(attribute: String, value: Double) {
        let ordered = orderedSelection()
        let map = ProgrammerGeometry.align(fixtureIDs: ordered, value: value)
        programmer.setMany(attribute: attribute, values: map)
        onChanged()
    }

    private func applyFan() {
        let ordered = orderedSelection()
        let map = ProgrammerGeometry.fan(fixtureIDs: ordered, start: fanStart, end: fanEnd)
        programmer.setMany(attribute: fanAttribute, values: map)
        loadFromProgrammer()
        onChanged()
    }

    private func applyAlign() {
        apply(attribute: fanAttribute, value: intensity)
        loadFromProgrammer()
    }

    private func orderedSelection() -> [UUID] {
        let selected = Set(selectedIDs)
        return project.fixtures
            .filter { selected.contains($0.id) }
            .sorted { $0.address < $1.address }
            .map(\.id)
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
        if let attr = availableAttributes.sorted().first {
            fanAttribute = attr
        }
    }
}
