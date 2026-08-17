import AuroraCore
import AuroraEngine
import SwiftUI

/// Live effect controls (PR23 + Pass-1 families). Math lives in `EffectRunner`.
public struct EffectsPanel: View {
    /// Selection order drives chase/wave/rainbow phase (P1-5).
    public var orderedSelectionFixtureIDs: [UUID]
    public var effects: EffectRunner
    public var onChanged: () -> Void

    @State private var kind: EffectKind = .pulse
    @State private var rateHz: Double = 1
    @State private var size: Double = 0.5
    @State private var phase: Double = 0
    @State private var spread: Double = 0.5
    @State private var directionForward: Bool = true
    @State private var attribute: String = "intensity"
    @State private var cellCount: Int = 8
    @State private var revision: UInt64 = 0

    public init(
        orderedSelectionFixtureIDs: [UUID],
        effects: EffectRunner,
        onChanged: @escaping () -> Void = {}
    ) {
        self.orderedSelectionFixtureIDs = orderedSelectionFixtureIDs
        self.effects = effects
        self.onChanged = onChanged
    }

    /// Compatibility: unordered set (stable UUID sort) when order is unknown.
    public init(
        selectionFixtureIDs: Set<UUID>,
        effects: EffectRunner,
        onChanged: @escaping () -> Void = {}
    ) {
        self.orderedSelectionFixtureIDs = selectionFixtureIDs.sorted { $0.uuidString < $1.uuidString }
        self.effects = effects
        self.onChanged = onChanged
    }

    private var running: [EffectInstance] {
        _ = revision
        return effects.snapshot()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effects").font(.headline)

            GroupBox("New on selection") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Kind", selection: $kind) {
                        ForEach(EffectKind.allCases, id: \.self) { k in
                            Text(displayName(k)).tag(k)
                        }
                    }
                    .labelsHidden()

                    if needsAttribute {
                        HStack {
                            Text("Attr")
                            TextField(defaultAttributeHint, text: $attribute)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    labeledSlider("Rate Hz", value: $rateHz, range: 0.05...8)
                    labeledSlider("Size", value: $size, range: 0...1)
                    labeledSlider("Phase", value: $phase, range: 0...1)
                    labeledSlider("Spread", value: $spread, range: 0...1)
                    Toggle("Forward direction", isOn: $directionForward)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    if kind == .cellChase {
                        Stepper("Cells: \(cellCount)", value: $cellCount, in: 1...128)
                    }

                    Text("\(orderedSelectionFixtureIDs.count) fixture(s) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Start Effect") { startEffect() }
                        .disabled(orderedSelectionFixtureIDs.isEmpty)
                }
                .padding(4)
            }

            Text("Running (\(running.count))")
                .font(.subheadline.weight(.semibold))

            if running.isEmpty {
                Text("No live effects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(running) { effect in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(effect.name)
                                Text(
                                    "\(effect.kind.rawValue) · \(String(format: "%.2f", effect.rateHz)) Hz · size \(String(format: "%.2f", effect.size)) · ph \(String(format: "%.2f", effect.phase)) · \(effect.fixtureIDs.count) fx"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(
                                "On",
                                isOn: Binding(
                                    get: { effect.enabled },
                                    set: { effects.setEnabled(id: effect.id, enabled: $0); bump(); onChanged() }
                                )
                            )
                            .labelsHidden()
                            Button(role: .destructive) {
                                effects.remove(id: effect.id)
                                bump()
                                onChanged()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(AuroraButtonStyle(kind: .quiet))
                        }
                    }
                }
                .frame(minHeight: 120)
            }

            HStack {
                Button("Clear All") {
                    effects.clear()
                    bump()
                    onChanged()
                }
                .disabled(running.isEmpty)
                Spacer()
            }
        }
        .padding(8)
    }

    private var needsAttribute: Bool {
        switch kind {
        case .rainbow, .positionCircle, .colorStep: return false
        default: return true
        }
    }

    private var defaultAttributeHint: String {
        switch kind {
        case .beamPulse: return "zoom"
        case .cellChase: return "colorR"
        default: return "intensity"
        }
    }

    private func displayName(_ k: EffectKind) -> String {
        switch k {
        case .pulse: return "Pulse"
        case .chase: return "Chase"
        case .wave: return "Wave"
        case .rainbow: return "Rainbow"
        case .positionCircle: return "Position Circle"
        case .colorStep: return "Color Step"
        case .cellChase: return "Cell Chase"
        case .beamPulse: return "Beam Pulse"
        }
    }

    private func startEffect() {
        var attr = attribute
        if kind == .beamPulse && (attr.isEmpty || attr == "intensity") { attr = "zoom" }
        if kind == .cellChase && attr.isEmpty { attr = "colorR" }
        let effect = EffectInstance(
            name: "\(displayName(kind)) \(orderedSelectionFixtureIDs.count)fx",
            kind: kind,
            rateHz: rateHz,
            size: size,
            phase: phase,
            spread: kind == .pulse ? 0 : spread,
            attribute: attr,
            fixtureIDs: orderedSelectionFixtureIDs,
            direction: directionForward ? 1 : -1,
            cellCount: cellCount
        )
        effects.upsert(effect)
        bump()
        onChanged()
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 36)
        }
    }

    private func bump() { revision &+= 1 }
}
