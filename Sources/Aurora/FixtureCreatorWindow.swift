import AuroraDesignSystem
import AuroraDiagnostics
import AuroraFixtureLib
import AuroraModel
import AuroraUI
import SwiftUI

struct FixtureCreatorWindow: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var template: FixtureCreationTemplate = .dimmer
    @State private var draft = FixtureDefinitionFactory.make(template: .dimmer)
    @State private var errorReport: PrismErrorReport?
    @State private var status: String?

    var body: some View {
        HSplitView {
            templateSidebar
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 260)
            editor
                .frame(minWidth: 560)
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(AuroraColor.surfacePanel)
        .prismErrorAlert(item: $errorReport)
    }

    private var templateSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STARTING POINT")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
                .padding(12)
            List(FixtureCreationTemplate.allCases, selection: $template) { item in
                Label(item.title, systemImage: icon(for: item))
                    .tag(item)
            }
            .onChange(of: template) { _, value in
                let manufacturer = draft.manufacturer
                let model = value.title
                draft = FixtureDefinitionFactory.make(
                    template: value,
                    manufacturer: manufacturer,
                    model: model,
                    modeName: draft.modeName
                )
                status = nil
            }
        }
        .background(AuroraColor.surfaceRaised)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identitySection
                    if FixtureDefinitionFactory.isSafetySensitive(draft) {
                        safetyNotice
                    }
                    channelSection
                    capabilitySection
                }
                .padding(18)
            }
            Divider()
            actionBar
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("IDENTITY")
            HStack {
                labeledField("Manufacturer", text: $draft.manufacturer)
                labeledField("Model", text: $draft.model)
            }
            HStack {
                labeledField("Mode", text: $draft.modeName)
                labeledField("Category", text: $draft.category)
            }
        }
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Safety-sensitive fixture").font(.headline)
                Text("Protected ranges require deliberate confirmation and default to zero. Creating this definition never sends DMX or activates the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("DMX CHANNELS")
                Spacer()
                Button("Add Channel") { addChannel() }.controlSize(.small)
            }
            ForEach(Array(draft.channels.indices), id: \.self) { index in
                channelRow(index)
            }
        }
    }

    private func channelRow(_ index: Int) -> some View {
        let protected = draft.channels[index].dmxFunctions.contains(where: \.isProtected)
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text("\(draft.channels[index].offset)")
                    .font(.body.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
                TextField("Name", text: channelBinding(index, \.name))
                TextField("Attribute", text: channelBinding(index, \.attribute))
                Picker("Kind", selection: channelBinding(index, \.semanticKind)) {
                    Text("Semantic").tag(ChannelSemanticKind.semantic)
                    Text("Generic").tag(ChannelSemanticKind.generic)
                }
                .labelsHidden()
                .frame(width: 110)
                Button(role: .destructive) { removeChannel(index) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(draft.channels.count == 1)
            }
            HStack {
                Toggle("Protected activation range", isOn: Binding(
                    get: { protected },
                    set: { setProtected($0, at: index) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                Spacer()
                if protected {
                    Text("DMX 200–255 · confirm · hold 1 second")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Divider()
            HStack {
                Text("FUNCTION RANGES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AuroraColor.textTertiary)
                Spacer()
                Button("Add Range") { addFunctionRange(to: index) }
                    .controlSize(.mini)
                    .disabled(nextAvailableRange(in: draft.channels[index]) == nil)
            }
            if draft.channels[index].dmxFunctions.isEmpty {
                Text("No ranges — the channel uses the full DMX range 0–255.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(draft.channels[index].dmxFunctions.indices), id: \.self) { functionIndex in
                    functionRangeRow(channel: index, function: functionIndex)
                }
            }
        }
        .padding(10)
        .background(AuroraColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
    }

    private func functionRangeRow(channel channelIndex: Int, function functionIndex: Int) -> some View {
        HStack(spacing: 8) {
            TextField("Function", text: functionBinding(channelIndex, functionIndex, \.name))
                .frame(minWidth: 120)
            TextField("Min", value: functionBinding(channelIndex, functionIndex, \.dmxMin), format: .number)
                .frame(width: 58)
            Text("–").foregroundStyle(.secondary)
            TextField("Max", value: functionBinding(channelIndex, functionIndex, \.dmxMax), format: .number)
                .frame(width: 58)
            Picker("Meaning", selection: functionBinding(channelIndex, functionIndex, \.semantic)) {
                Text("Off / Raw").tag(DMXFunctionSemantic.generic)
                Text("Controls Attribute").tag(DMXFunctionSemantic.attribute)
                Text("Protected Command").tag(DMXFunctionSemantic.protectedCommand)
            }
            .labelsHidden()
            .frame(width: 150)
            Button(role: .destructive) { removeFunctionRange(channel: channelIndex, function: functionIndex) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("CAPABILITIES")
            HStack {
                Toggle("Pan / Tilt", isOn: $draft.hasPanTilt)
                Picker("Color", selection: Binding(
                    get: { draft.colorModel },
                    set: { draft.colorModel = $0 }
                )) {
                    Text("None").tag(ColorModel?.none)
                    ForEach(ColorModel.allCases, id: \.self) { model in
                        Text(model.rawValue).tag(Optional(model))
                    }
                }
                .frame(maxWidth: 220)
                Spacer()
                Text("Footprint: \(draft.calculatedFootprint) ch")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset Template") {
                draft = FixtureDefinitionFactory.make(template: template)
                status = nil
            }
            Button("Create Fixture") { save() }
                .buttonStyle(AuroraButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(AuroraColor.surfaceHeader)
    }

    private func save() {
        normalizeOffsets()
        synchronizePhysicalIdentity()
        do {
            try FixtureDefinitionValidation.validate(draft)
            try FixtureDefinitionValidation.validateAuthoredFunctionRanges(draft)
            try appModel.createUserFixture(draft)
            status = "Created \(draft.displayName) in the User Fixture Library"
            let manufacturer = draft.manufacturer
            draft = FixtureDefinitionFactory.make(template: template, manufacturer: manufacturer)
        } catch {
            status = PrismErrorReporting.userFacingMessage(for: error)
            errorReport = PrismErrorReporting.report(
                error: error,
                context: PrismErrorContext(
                    operation: "create fixture",
                    category: .fixtureLibrary,
                    fallbackTitle: "Prism Couldn't Create the Fixture",
                    fallbackMessage: "Check the fixture identity and DMX channels, then try again."
                )
            )
        }
    }

    private func addChannel() {
        let offset = UInt16(draft.channels.count + 1)
        draft.channels.append(ChannelDef(offset: offset, name: "Channel \(offset)", attribute: "generic\(offset)", semanticKind: .generic))
        draft.channelCount = draft.calculatedFootprint
    }

    private func removeChannel(_ index: Int) {
        draft.channels.remove(at: index)
        normalizeOffsets()
    }

    private func normalizeOffsets() {
        for index in draft.channels.indices { draft.channels[index].offset = UInt16(index + 1) }
        draft.channelCount = draft.calculatedFootprint
    }

    private func synchronizePhysicalIdentity() {
        guard var physical = draft.portablePhysicalDefinition else { return }
        physical.manufacturer = draft.manufacturer
        physical.model = draft.model
        draft.portablePhysicalDefinition = physical
        draft.physicalFixtureID = physical.id
    }

    private func setProtected(_ enabled: Bool, at index: Int) {
        if enabled {
            draft.channels[index].defaultValue = 0
            draft.channels[index].highlightValue = 0
            draft.channels[index].semanticKind = .generic
            draft.channels[index].dmxFunctions = [DMXFunctionRange(
                name: "Protected Activation",
                dmxMin: 200,
                dmxMax: 255,
                semantic: .protectedCommand,
                commandCategory: .custom,
                holdDurationMilliseconds: 1000,
                requiresConfirmation: true
            )]
        } else {
            draft.channels[index].dmxFunctions.removeAll(where: \.isProtected)
        }
    }

    private func nextAvailableRange(in channel: ChannelDef) -> ClosedRange<UInt8>? {
        let ordered = channel.dmxFunctions.sorted { $0.dmxMin < $1.dmxMin }
        var candidate = 0
        for function in ordered {
            if candidate < Int(function.dmxMin) {
                return UInt8(candidate)...UInt8(Int(function.dmxMin) - 1)
            }
            candidate = max(candidate, Int(function.dmxMax) + 1)
        }
        guard candidate <= 255 else { return nil }
        return UInt8(candidate)...255
    }

    private func addFunctionRange(to channelIndex: Int) {
        guard let range = nextAvailableRange(in: draft.channels[channelIndex]) else { return }
        let attribute = draft.channels[channelIndex].attribute
        draft.channels[channelIndex].dmxFunctions.append(DMXFunctionRange(
            name: "Function \(draft.channels[channelIndex].dmxFunctions.count + 1)",
            dmxMin: range.lowerBound,
            dmxMax: range.upperBound,
            attribute: attribute,
            semantic: .attribute
        ))
    }

    private func removeFunctionRange(channel channelIndex: Int, function functionIndex: Int) {
        draft.channels[channelIndex].dmxFunctions.remove(at: functionIndex)
    }

    private func channelBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<ChannelDef, Value>) -> Binding<Value> {
        Binding(get: { draft.channels[index][keyPath: keyPath] }, set: { draft.channels[index][keyPath: keyPath] = $0 })
    }

    private func functionBinding<Value>(
        _ channelIndex: Int,
        _ functionIndex: Int,
        _ keyPath: WritableKeyPath<DMXFunctionRange, Value>
    ) -> Binding<Value> {
        Binding(
            get: { draft.channels[channelIndex].dmxFunctions[functionIndex][keyPath: keyPath] },
            set: { draft.channels[channelIndex].dmxFunctions[functionIndex][keyPath: keyPath] = $0 }
        )
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(AuroraTypography.controlLabel).foregroundStyle(AuroraColor.textTertiary)
    }

    private func icon(for template: FixtureCreationTemplate) -> String {
        switch template {
        case .fogger, .hazer: return "cloud.fill"
        case .snowMachine: return "snowflake"
        case .bubbleMachine: return "circle.grid.3x3.fill"
        case .fan: return "fan.fill"
        case .flameEffect: return "flame.fill"
        case .movingHead: return "move.3d"
        case .laser: return "scope"
        case .strobe: return "bolt.fill"
        case .generic: return "slider.horizontal.3"
        default: return "lightbulb.fill"
        }
    }
}
