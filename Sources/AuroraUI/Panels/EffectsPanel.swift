import AuroraCore
import AuroraEngine
import SwiftUI

/// Live effect controls (PR23). All generation math lives in `EffectRunner`.
public struct EffectsPanel: View {
    /// Selection order drives chase/wave/rainbow phase (P1-5).
    public var orderedSelectionFixtureIDs: [UUID]
    public var effects: EffectRunner
    public var onChanged: () -> Void

    @State private var kind: EffectKind = .pulse
    @State private var rateHz: Double = 1
    @State private var size: Double = 0.5
    @State private var attribute: String = "intensity"
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
                            Text(k.rawValue.capitalized).tag(k)
                        }
                    }
                    .labelsHidden()

                    if kind != .rainbow {
                        HStack {
                            Text("Attr")
                            TextField("intensity", text: $attribute)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    labeledSlider("Rate Hz", value: $rateHz, range: 0.05...8)
                    labeledSlider("Size", value: $size, range: 0...1)

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
                                    "\(effect.kind.rawValue) · \(String(format: "%.2f", effect.rateHz)) Hz · size \(String(format: "%.2f", effect.size)) · \(effect.fixtureIDs.count) fx"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(
                                "On",
                                isOn: Binding(
                                    get: { effect.enabled },
                                    set: { enabled in
                                        effects.setEnabled(id: effect.id, enabled: enabled)
                                        bump()
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            Button("Remove", role: .destructive) {
                                effects.remove(id: effect.id)
                                bump()
                            }
                        }
                    }
                }
                .frame(minHeight: 120)
            }

            if !running.isEmpty {
                Button("Clear All", role: .destructive) {
                    effects.clear()
                    bump()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospaced())
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func startEffect() {
        let ids = orderedSelectionFixtureIDs
        guard !ids.isEmpty else { return }
        let name: String
        switch kind {
        case .pulse: name = "Pulse"
        case .chase: name = "Chase"
        case .wave: name = "Wave"
        case .rainbow: name = "Rainbow"
        }
        let spread: Double
        switch kind {
        case .wave, .rainbow: spread = 0.5
        case .chase, .pulse: spread = 0
        }
        let effect = EffectInstance(
            name: "\(name) \(running.count + 1)",
            kind: kind,
            rateHz: rateHz,
            size: size,
            phase: 0,
            spread: spread,
            attribute: kind == .rainbow ? "colorR" : attribute,
            fixtureIDs: ids,
            enabled: true
        )
        effects.upsert(effect)
        bump()
    }

    private func bump() {
        revision &+= 1
        onChanged()
    }
}
