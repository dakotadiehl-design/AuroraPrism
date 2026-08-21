import AuroraDesignSystem
import AppKit
import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// FX-3 dedicated Effects workspace. Visualizers consume evaluator metadata;
/// this view never recreates fixture phase or semantic output math.
public struct EffectsPanel: View {
    public var orderedSelectionFixtureIDs: [UUID]
    public var orderedSelectionTargets: [FixtureTarget]
    public var effects: EffectRunner
    public var onChanged: () -> Void
    public var onApplyToProgrammer: (ActiveLook) -> Void
    public var evaluatePreview: (EffectInstance, TimeInterval) -> EffectEvaluationResult
    public var stagePlacements: [StageFixturePlacement]
    public var fixtureGroups: [AuroraModel.Group]
    public var onPrivatePreviewChanged: (EffectInstance?) -> Void
    public var onShowInMainStageChanged: (Bool) -> Void

    @AppStorage("prism.effects.followSelection") private var followSelection = true
    @AppStorage("prism.effects.showInMainStage") private var showInMainStage = false
    @AppStorage("prism.effects.workspaceMode") private var storedMode = Mode.preview.rawValue
    @AppStorage("prism.effects.gradientPresets") private var storedGradientPresets = ""
    @AppStorage("prism.effects.effectPresets") private var storedEffectPresets = ""
    @AppStorage("prism.effects.distributionPresets") private var storedDistributionPresets = ""
    @AppStorage("prism.effects.selectedEffectID") private var storedSelectedID = ""
    @AppStorage("prism.effects.inspectorTab") private var inspectorTab = "Effect"
    @AppStorage("prism.effects.selectedCategory") private var selectedCategory = "All"
    @AppStorage("prism.effects.previewSpeed") private var previewSpeed = 1.0
    @AppStorage("prism.effects.loopPreview") private var loopPreview = true
    @AppStorage("prism.effects.recentIDs") private var storedRecentIDs = ""
    @AppStorage("prism.effects.libraryWidth") private var libraryWidth = 238.0
    @AppStorage("prism.effects.inspectorWidth") private var inspectorWidth = 330.0
    @AppStorage("prism.effects.timingHeight") private var timingHeight = 142.0
    @AppStorage("prism.effects.visualizerHeight") private var visualizerHeight = 202.0
    @State private var revision: UInt64 = 0
    @State private var drafts: [UUID: EffectInstance] = [:]
    @State private var searchText = ""
    @State private var lastTapTime: TimeInterval?

    private enum Mode: String, CaseIterable { case preview, programmer, live }
    private enum TimingRateMode: String, CaseIterable { case frequency, period, musical }

    private var selectedID: UUID? {
        get { UUID(uuidString: storedSelectedID) }
        nonmutating set { storedSelectedID = newValue?.uuidString ?? "" }
    }

    public init(
        orderedSelectionFixtureIDs: [UUID],
        effects: EffectRunner,
        fixtureGroups: [AuroraModel.Group] = [],
        onChanged: @escaping () -> Void = {},
        onApplyToProgrammer: @escaping (ActiveLook) -> Void = { _ in },
        evaluatePreview: @escaping (EffectInstance, TimeInterval) -> EffectEvaluationResult = {
            PrismEffectEvaluator.evaluate(baseLook: .empty, time: $1, effects: [PrismEffectCompiler.compile($0)])
        },
        stagePlacements: [StageFixturePlacement] = [],
        orderedSelectionTargets: [FixtureTarget]? = nil,
        onPrivatePreviewChanged: @escaping (EffectInstance?) -> Void = { _ in },
        onShowInMainStageChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.orderedSelectionFixtureIDs = orderedSelectionFixtureIDs
        self.effects = effects
        self.onChanged = onChanged
        self.onApplyToProgrammer = onApplyToProgrammer
        self.evaluatePreview = evaluatePreview
        self.stagePlacements = stagePlacements
        self.fixtureGroups = fixtureGroups
        self.orderedSelectionTargets = orderedSelectionTargets ?? orderedSelectionFixtureIDs.map { FixtureTarget(fixtureID: $0) }
        self.onPrivatePreviewChanged = onPrivatePreviewChanged
        self.onShowInMainStageChanged = onShowInMainStageChanged
    }

    public init(selectionFixtureIDs: Set<UUID>, effects: EffectRunner, onChanged: @escaping () -> Void = {}) {
        self.init(orderedSelectionFixtureIDs: selectionFixtureIDs.sorted { $0.uuidString < $1.uuidString }, effects: effects, onChanged: onChanged)
    }

    private var mode: Binding<Mode> {
        Binding(get: { Mode(rawValue: storedMode) ?? .preview }, set: { requested in
            if requested == .live, let effect = selected {
                effects.upsert(effect)
                drafts[effect.id] = nil
                onPrivatePreviewChanged(nil)
                onChanged()
                recordRecent(effect.id)
            }
            storedMode = requested.rawValue
            revision &+= 1
        })
    }

    private var running: [EffectInstance] {
        _ = revision
        var merged = Dictionary(uniqueKeysWithValues: effects.snapshot().map { ($0.id, $0) })
        for (id, draft) in drafts { merged[id] = draft }
        return merged.values.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var selected: EffectInstance? {
        running.first { $0.id == selectedID } ?? running.first
    }

    private var visibleEffects: [EffectInstance] {
        running.filter { effect in
            let categoryMatches = selectedCategory == "All"
                || (selectedCategory == "Favorites" && effect.isFavorite)
                || category(for: effect.kind) == selectedCategory
            let searchMatches = searchText.isEmpty || effect.name.localizedCaseInsensitiveContains(searchText)
                || effect.kind.rawValue.localizedCaseInsensitiveContains(searchText)
            return categoryMatches && searchMatches
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                library.frame(width: libraryWidth)
                resizeDivider(width: $libraryWidth, range: 190...380, direction: 1)
                workspace.frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
                resizeDivider(width: $inspectorWidth, range: 280...520, direction: -1)
                inspector.frame(width: inspectorWidth)
            }
            Divider()
            footer
        }
        .background(AuroraColor.surfaceBase)
        .onAppear { reconcileSelection(); onPrivatePreviewChanged(selected.flatMap { drafts[$0.id] }); onShowInMainStageChanged(showInMainStage) }
        .onDisappear { onPrivatePreviewChanged(nil) }
        .onChange(of: running.map(\.id)) { _, _ in reconcileSelection() }
        .onChange(of: selectedID) { _, _ in onPrivatePreviewChanged(selected.flatMap { drafts[$0.id] }) }
        .onChange(of: showInMainStage) { _, enabled in onShowInMainStageChanged(enabled) }
        .onChange(of: orderedSelectionFixtureIDs) { _, ids in
            guard followSelection, !ids.isEmpty, var effect = selected else { return }
            effect.fixtureIDs = ids
            let cellTargets = orderedSelectionTargets.filter { $0.elementID != nil }.map(EffectTargetID.init)
            if !cellTargets.isEmpty {
                effect.cellTargeting = .init(mode: .selectedCells, selectedTargets: cellTargets)
            }
            store(effect)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            tool("Library", "books.vertical") { selectedCategory = "All" }
            tool("New Effect", "plus.square.on.square") { createEffect() }
            tool("Save", "square.and.arrow.down") {
                if let effect = selected, drafts[effect.id] != nil { saveEffectPreset(effect) }
                else { onChanged() }
            }
            Divider().frame(height: 30)
            Picker("Workspace", selection: mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 310)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Label(mode.wrappedValue == .preview ? "PRIVATE PREVIEW" : mode.wrappedValue.rawValue.uppercased(), systemImage: "circle.fill")
                    .font(.caption2.bold()).foregroundStyle(mode.wrappedValue == .live ? .green : AuroraColor.accent)
                Text(mode.wrappedValue == .preview ? "Output is preview only" : "Authoring workspace state")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Follow Selection", isOn: $followSelection).toggleStyle(.button).controlSize(.small)
            Toggle("Show in Stage", isOn: $showInMainStage)
                .toggleStyle(.button).controlSize(.small)
                .help("Show this private preview in the main Stage without changing live output.")
        }
        .padding(.horizontal, 14).frame(height: 62).background(AuroraColor.surfaceRaised)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("EFFECT LIBRARY").padding(12)
            TextField("Search", text: $searchText).textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 9)
            ForEach(["All", "Favorites", "Color", "Intensity", "Movement", "Beam", "Pixel", "Atmosphere", "Custom"], id: \.self) { name in
                HStack {
                    Image(systemName: icon(name)).frame(width: 18)
                    Text(name); Spacer(); Text("\(categoryCount(name))").foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal, 12).frame(height: 30)
                .background(name == selectedCategory ? AuroraColor.accent.opacity(0.18) : .clear)
                .contentShape(Rectangle()).onTapGesture { selectedCategory = name }
            }
            Divider().padding(.vertical, 8)
            sectionTitle("MY EFFECTS").padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(visibleEffects) { effect in
                        Button { selectEffect(effect) } label: {
                            HStack {
                                Circle().fill(effect.enabled ? AuroraColor.accent : .gray).frame(width: 7, height: 7)
                                Text(effect.name).lineLimit(1); Spacer()
                                Button { update(effect) { $0.isFavorite.toggle() } } label: {
                                    Image(systemName: effect.isFavorite ? "star.fill" : "star").foregroundStyle(effect.isFavorite ? .yellow : .secondary)
                                }.buttonStyle(.plain)
                            }
                            .font(.caption).padding(.horizontal, 10).frame(height: 30)
                            .background(effect.id == selected?.id ? AuroraColor.accent.opacity(0.25) : .clear)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(6)
            }
            Button { createEffect() } label: { Label("New Effect", systemImage: "plus") }
                .frame(maxWidth: .infinity).padding(10)
            if !recentEffects.isEmpty {
                Divider()
                sectionTitle("RECENTLY USED").padding(.horizontal, 12)
                ForEach(recentEffects.prefix(3)) { effect in
                    Button { selectEffect(effect) } label: {
                        HStack { Image(systemName: icon(category(for: effect.kind))); Text(effect.name).lineLimit(1); Spacer() }
                    }.buttonStyle(.plain).font(.caption).padding(.horizontal, 12).frame(height: 28)
                }
            }
        }.background(AuroraColor.surfaceRaised.opacity(0.7))
    }

    private var workspace: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            let frame = previewFrame(at: ProcessInfo.processInfo.systemUptime)
            workspaceContent(frame: frame)
        }
    }

    private func workspaceContent(frame: EffectEvaluationResult?) -> some View {
        VStack(spacing: 8) {
            HStack {
                sectionTitle("TARGET")
                Text(selected.map { "\($0.name) Target" } ?? "No Effect Selected").font(.caption.bold())
                Text("\(selected?.fixtureIDs.count ?? 0) fixtures selected").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Picker("View", selection: .constant("Fixture Layout")) { Text("Fixture Layout").tag("Fixture Layout") }
                    .labelsHidden().frame(width: 130)
            }.padding(.horizontal, 12).frame(height: 38).background(AuroraColor.surfaceRaised)

            stagePreview(frame: frame)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.46)).clipShape(RoundedRectangle(cornerRadius: 5))
            timing(frame: frame).frame(height: timingHeight)
                .overlay(alignment: .bottom) { horizontalResizeHandle(value: $timingHeight, range: 110...260, direction: 1) }
            HStack(spacing: 8) {
                if selected?.kind == .movement {
                    visualCard("EVALUATED MOVEMENT PATH", content: movementPath(frame: frame))
                } else {
                    visualCard("EVALUATED OUTPUT", content: VStack(spacing: 4) {
                        waveform(frame: frame)
                        HStack {
                            Picker("Preview Speed", selection: $previewSpeed) {
                                Text("25%").tag(0.25); Text("50%").tag(0.5); Text("100%").tag(1.0); Text("200%").tag(2.0)
                            }.frame(width: 150)
                            Toggle("Loop", isOn: $loopPreview).toggleStyle(.checkbox)
                            Spacer()
                        }.controlSize(.small)
                    })
                }
                visualCard("FIXTURE PHASE VISUALIZER", content: phaseVisualizer(frame: frame)).frame(maxWidth: 360)
            }.frame(height: visualizerHeight)
                .overlay(alignment: .top) { horizontalResizeHandle(value: $visualizerHeight, range: 150...360, direction: -1) }
        }.padding(8)
    }

    private func stagePreview(frame: EffectEvaluationResult?) -> some View {
        ZStack {
            Canvas { context, size in
                var path = Path()
                for x in stride(from: 0.0, through: size.width, by: 48) { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)) }
                for y in stride(from: 0.0, through: size.height, by: 40) { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)) }
                context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<(selected?.fixtureIDs.count ?? 0), id: \.self) { index in
                    let values = targetValues(frame: frame)
                    let value = index < values.count ? values[index] : 0.15
                    let fixtureID = selected?.fixtureIDs.indices.contains(index) == true ? selected?.fixtureIDs[index] : nil
                    let color = evaluatedColor(frame: frame, fixtureID: fixtureID)
                    VStack(spacing: 3) {
                        Image(systemName: "light.overhead.left.fill").font(.title2).foregroundStyle(.white.opacity(0.8))
                        LinearGradient(colors: [color.opacity(0.9), color.opacity(max(0.12, value)), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(maxWidth: 70, minHeight: 80).clipShape(BeamShape())
                    }
                }
            }.padding(.top, 36).padding(.horizontal, 28)
        }
    }

    private func timing(frame: EffectEvaluationResult?) -> some View {
        HStack(spacing: 0) {
            timingCell("SOURCE") {
                Text(clockSourceName(selected)).font(.caption.bold())
                Text(timingStatusDescription(frame)).foregroundStyle(timingStatusColor(frame))
            }
            timingCell("RATE") { Text(rateDescription(selected)).font(.title3.monospacedDigit()); Text(modifierDescription(selected)).foregroundStyle(.secondary) }
            timingCell("BPM") { Text(bpmDescription(selected)).font(.title3.monospacedDigit()); Text(quantizationDescription(selected)).foregroundStyle(.secondary) }
            timingCell("PHASE") { Gauge(value: selected?.phase ?? 0) { EmptyView() }.gaugeStyle(.accessoryCircular); Text(String(format: "%.0f°", (selected?.phase ?? 0) * 360)) }
            timingCell("FIXTURE SPREAD") { Gauge(value: selected?.spread ?? 0) { EmptyView() }.gaugeStyle(.accessoryCircular); Text(String(format: "%.0f%%", (selected?.spread ?? 0) * 100)) }
        }.background(AuroraColor.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack { Text("EFFECT INSPECTOR").font(.caption2.bold()).foregroundStyle(AuroraColor.accent); Spacer() }.padding(12)
            Picker("Inspector", selection: $inspectorTab) { ForEach(["Effect", "Timing", "Output"], id: \.self) { Text($0).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal, 12)
            ScrollView {
                if let effect = selected {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorContent(effect)
                    }.padding(12)
                } else {
                    ContentUnavailableView("No Effect Selected", systemImage: "waveform.path", description: Text("Create or select an effect to edit."))
                        .padding(.top, 80)
                }
            }
        }.background(AuroraColor.surfaceRaised.opacity(0.72))
    }

    private var footer: some View {
        HStack {
            Label(statusText, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
            Spacer()
            Button("Revert") { if let id = selected?.id { drafts[id] = nil; onPrivatePreviewChanged(nil); revision &+= 1 } }.disabled(selected == nil)
            Button("Apply to Programmer") { applySelectedToProgrammer() }.disabled(selected == nil)
            Button("Apply & Take Live") { applySelectedLive() }.disabled(selected == nil).buttonStyle(AuroraButtonStyle(kind: .primary))
        }.padding(.horizontal, 14).frame(height: 48).background(AuroraColor.surfaceRaised)
    }

    private func waveform(frame: EffectEvaluationResult?) -> some View {
        Canvas { context, size in
            let currentMetadata = metadata(frame: frame)
            let samples = currentMetadata?.waveformSamples ?? []
            var path = Path()
            if samples.isEmpty {
                path.move(to: .init(x: 0, y: size.height / 2)); path.addLine(to: .init(x: size.width, y: size.height / 2))
            } else {
                for index in samples.indices {
                    let sourceIndex = currentMetadata?.waveformDirection == -1 ? samples.count - 1 - index : index
                    let point = CGPoint(x: size.width * Double(index) / Double(max(1, samples.count - 1)), y: size.height * (1 - samples[sourceIndex]))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            context.stroke(path, with: .color(.purple), lineWidth: 2)
            if let playhead = currentMetadata?.playheadPhase {
                var marker = Path()
                let x = size.width * playhead
                marker.move(to: CGPoint(x: x, y: 0)); marker.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(marker, with: .color(AuroraColor.accent), lineWidth: 1.5)
            }
        }
    }

    private func phaseVisualizer(frame: EffectEvaluationResult?) -> some View {
        Canvas { context, size in
            let samples = metadata(frame: frame)?.targets ?? []
            let count = max(1, samples.count)
            var line = Path()
            for index in 0..<count {
                let phase = index < samples.count ? samples[index].phase : Double(index) / Double(count)
                let point = CGPoint(x: size.width * (Double(index) + 0.5) / Double(count), y: size.height * (0.5 - 0.35 * sin(phase * .pi * 2)))
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
                context.fill(Path(ellipseIn: .init(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(AuroraColor.accent))
            }
            context.stroke(line, with: .color(.purple), lineWidth: 1.5)
        }
    }

    private func movementPath(frame: EffectEvaluationResult?) -> some View {
        Canvas { context, size in
            let metadata = metadata(frame: frame)
            let points = metadata?.movementPathSamples ?? []
            guard let first = points.first else { return }
            func screen(_ point: EffectMovementPoint) -> CGPoint {
                CGPoint(x: size.width * (0.5 + point.x), y: size.height * (0.5 + point.y))
            }
            var path = Path()
            path.move(to: screen(first))
            for point in points.dropFirst() { path.addLine(to: screen(point)) }
            context.stroke(path, with: .color(.purple), lineWidth: 2)
            if let phase = metadata?.playheadPhase, !points.isEmpty {
                let index = min(points.count - 1, Int((phase * Double(points.count - 1)).rounded()))
                let center = screen(points[index])
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(AuroraColor.accent))
            }
            for target in metadata?.targets ?? [] {
                guard let pan = target.pan, let tilt = target.tilt else { continue }
                let center = CGPoint(x: pan * size.width, y: tilt * size.height)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(.white))
            }
        }
    }

    private func metadata(frame: EffectEvaluationResult?) -> EffectVisualizationMetadata? {
        guard let id = selected?.id else { return nil }
        return frame?.visualizations[id]
    }
    private func targetValues(frame: EffectEvaluationResult?) -> [Double] { metadata(frame: frame)?.targets.map { $0.value ?? 0 } ?? [] }

    private func previewFrame(at time: TimeInterval) -> EffectEvaluationResult? {
        guard let effect = selected else { return nil }
        let previewTime = time * previewSpeed
        if drafts[effect.id] != nil {
            return evaluatePreview(effect, previewTime)
        }
        return effects.latestEvaluationResult()
            ?? evaluatePreview(effect, previewTime)
    }

    private func createEffect() {
        let wantsGradient = selectedCategory == "Color"
        let wantsMovement = selectedCategory == "Movement"
        let wantsPattern = selectedCategory == "Custom"
        let effect = EffectInstance(
            name: wantsGradient ? "New Color Gradient" : (wantsMovement ? "New Movement" : "New Intensity Wave"),
            kind: wantsGradient ? .colorGradient : (wantsMovement ? .movement : (wantsPattern ? .pattern : .wave)),
            rateHz: 1,
            size: 1,
            spread: 0.5,
            fixtureIDs: orderedSelectionFixtureIDs,
            generator: EffectGeneratorDefinition(shape: .sine),
            timing: EffectTimingDefinition(source: .freeRun, rate: .frequencyHz(1)),
            distribution: FixtureDistributionDefinition(order: .selection),
            base: 0,
            colorGradient: wantsGradient ? EffectColorGradientDefinition() : nil,
            movement: wantsMovement ? EffectMovementDefinition() : nil,
            pattern: wantsPattern ? EffectPatternDefinition() : nil,
            cellTargeting: initialCellTargeting
        )
        drafts[effect.id] = effect; selectedID = effect.id; onPrivatePreviewChanged(effect); revision &+= 1
    }
    private func update(_ effect: EffectInstance, _ mutation: (inout EffectInstance) -> Void) { var copy = effect; mutation(&copy); store(copy) }
    private func store(_ effect: EffectInstance) {
        if mode.wrappedValue == .live {
            effects.upsert(effect)
            drafts[effect.id] = nil
            onPrivatePreviewChanged(nil)
            revision &+= 1
            return
        }
        drafts[effect.id] = effect
        if selectedID == effect.id { onPrivatePreviewChanged(effect) }
        revision &+= 1
    }
    private func applySelectedLive() {
        guard let effect = selected else { return }
        effects.upsert(effect); drafts[effect.id] = nil; onPrivatePreviewChanged(nil); storedMode = Mode.live.rawValue; changed()
        recordRecent(effect.id)
    }
    private func applySelectedToProgrammer() {
        guard let effect = selected else { return }
        let result = evaluatePreview(effect, ProcessInfo.processInfo.systemUptime)
        onApplyToProgrammer(result.semanticLook)
        storedMode = Mode.programmer.rawValue
        recordRecent(effect.id)
    }

    private func categoryCount(_ name: String) -> Int {
        if name == "All" { return running.count }
        if name == "Favorites" { return running.filter(\.isFavorite).count }
        return running.filter { category(for: $0.kind) == name }.count
    }

    private func moveSelected(_ effect: EffectInstance, offset: Int) {
        guard drafts[effect.id] == nil,
              let index = effects.snapshot().firstIndex(where: { $0.id == effect.id }) else { return }
        effects.move(id: effect.id, to: index + offset)
        changed()
    }

    private func createLinkedInstance(from effect: EffectInstance) {
        guard drafts[effect.id] == nil,
              let id = effects.createLinkedInstance(templateID: effect.id, fixtureIDs: orderedSelectionFixtureIDs) else { return }
        selectedID = id
        changed()
    }

    private var savedEffectPresets: [EffectDefinition] {
        guard let data = storedEffectPresets.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([EffectDefinition].self, from: data)) ?? []
    }

    private func saveEffectPreset(_ effect: EffectInstance) {
        var presets = savedEffectPresets
        var preset = effect.asDefinition()
        preset.id = UUID()
        preset.name = "\(effect.name) Preset"
        preset.fixtureIDs = []
        preset.order = presets.count
        preset.templateEffectID = nil
        preset.templateLinkMode = .detached
        presets.append(preset)
        if let data = try? JSONEncoder().encode(presets) { storedEffectPresets = String(decoding: data, as: UTF8.self) }
    }

    private func applyEffectPreset(_ preset: EffectDefinition, to effect: EffectInstance) {
        let identity = (effect.id, effect.name, effect.fixtureIDs, effect.order, effect.enabled, effect.isFavorite)
        var applied = EffectInstance(definition: preset)
        applied.id = identity.0
        applied.name = identity.1
        applied.fixtureIDs = identity.2
        applied.order = identity.3
        applied.enabled = identity.4
        applied.isFavorite = identity.5
        store(applied)
    }

    private var statusText: String {
        guard let effect = selected else { return "Ready — create an effect to begin." }
        if drafts[effect.id] != nil { return "\(effect.name) is a private draft; live output is unchanged." }
        return "\(effect.name) is saved in the live Effects stack."
    }

    @ViewBuilder private func inspectorContent(_ effect: EffectInstance) -> some View {
        switch inspectorTab {
        case "Timing":
            inspectSection("CLOCK") {
                Picker("Source", selection: Binding(get: { effect.timing?.source ?? .freeRun }, set: { source in updateTiming(effect) { timing in
                    timing.source = source
                    if source != .freeRun, case .frequencyHz = timing.rate { timing.rate = .musical(.init(unit: .note, noteDivision: .quarter)) }
                } })) {
                    ForEach(EffectClockSource.allCases, id: \.self) { Text(clockSourceName($0)).tag($0) }
                }
                Picker("Rate Type", selection: Binding(get: { timingRateMode(effect) }, set: { mode in updateTiming(effect) { timing in
                    switch mode {
                    case .frequency: timing.rate = .frequencyHz(max(0.001, effect.rateHz))
                    case .period: timing.rate = .periodSeconds(1 / max(0.001, effect.rateHz))
                    case .musical: timing.rate = .musical(.init(unit: .note, noteDivision: .quarter))
                    }
                } })) {
                    ForEach(TimingRateMode.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
                }
                timingRateControls(effect)
                if effect.timing?.source == .internalBPM {
                    slider("Internal BPM", effect.timing?.internalBPM ?? 120, 20...300) { value in updateTiming(effect) { $0.internalBPM = value } }
                    Button("Tap Tempo") { tapTempo(effect) }
                }
                Picker("Start", selection: Binding(get: { effect.timing?.startQuantization ?? .immediate }, set: { value in updateTiming(effect) { $0.startQuantization = value } })) {
                    ForEach(EffectStartQuantization.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
                }
                Picker("Source Switch", selection: Binding(get: { effect.timing?.sourceSwitchPolicy ?? .preservePhase }, set: { value in updateTiming(effect) { $0.sourceSwitchPolicy = value } })) {
                    Text("Preserve Phase").tag(EffectClockSwitchPolicy.preservePhase)
                    Text("Re-Quantize").tag(EffectClockSwitchPolicy.requantize)
                    Text("Restart").tag(EffectClockSwitchPolicy.restart)
                }
                Picker("Clock Loss", selection: Binding(get: { effect.timing?.clockLossPolicy ?? .holdPhase }, set: { value in updateTiming(effect) { $0.clockLossPolicy = value } })) {
                    ForEach(EffectClockLossPolicy.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
                }
            }
            inspectSection("RATE & PHASE") {
                slider("Rate Hz", effect.rateHz, 0.05...8) { value in updateRate(effect, value: value) }
                slider("Phase", effect.phase, 0...1) { value in update(effect) { $0.phase = value } }
                slider("Spread", effect.spread, 0...1) { value in update(effect) { $0.spread = value } }
            }
        case "Output":
            inspectSection("ROUTING") {
                field("Editing", drafts[effect.id] == nil ? "Saved state" : "Private draft")
                field("Main Stage", "Live output unchanged")
                Toggle("Effect Enabled", isOn: Binding(get: { effect.enabled }, set: { enabled in update(effect) { $0.enabled = enabled } }))
            }
            inspectSection("SAFETY") {
                Text("Only Apply & Take Live writes this draft to the live Effects runner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default:
            inspectSection("EFFECT") {
                field("Name", effect.name)
                field("Type", effect.kind.rawValue.capitalized)
                field("Property", effect.attribute)
            }
            inspectSection("STACK & REUSE") {
                Picker("Blend", selection: Binding(get: { effect.blendMode }, set: { value in update(effect) { $0.blendMode = value } })) {
                    ForEach(EffectBlendMode.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
                }
                slider("Blend Amount", effect.blendAmount, 0...1) { value in update(effect) { $0.blendAmount = value } }
                Picker("Mask", selection: Binding(get: { effect.mask?.kind ?? EffectMaskKind.none }, set: { value in update(effect) { current in
                    var mask = current.mask ?? EffectMaskDefinition(); mask.kind = value
                    if value == .selectedTargets {
                        mask.selectedTargets = orderedSelectionTargets.map(EffectTargetID.init)
                    } else if value == .fixtureGroup && mask.fixtureGroupID == nil {
                        mask.fixtureGroupID = fixtureGroups.first?.id
                    } else if value == .spatialRegion && mask.maximumX > 1000 {
                        mask.minimumX = -100; mask.maximumX = 100; mask.minimumY = -100; mask.maximumY = 100
                    }
                    current.mask = mask
                } })) {
                    ForEach(EffectMaskKind.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
                }
                if effect.mask?.kind == .fixtureGroup {
                    Picker("Fixture Group", selection: Binding(get: {
                        effect.mask?.fixtureGroupID
                    }, set: { groupID in
                        updateMask(effect) { $0.fixtureGroupID = groupID }
                    })) {
                        Text("Choose a group").tag(Optional<UUID>.none)
                        ForEach(fixtureGroups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    if fixtureGroups.isEmpty {
                        Text("Create a fixture group before using this mask.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if effect.mask?.kind == .everyNth {
                    Stepper("Every \(effect.mask?.everyNth ?? 2)", value: Binding(get: { effect.mask?.everyNth ?? 2 }, set: { value in update(effect) { current in
                        var mask = current.mask ?? EffectMaskDefinition(kind: .everyNth); mask.everyNth = max(1, value); current.mask = mask
                    } }), in: 1...64)
                }
                if effect.mask?.kind == .selectedTargets {
                    Text("\(effect.mask?.selectedTargets.count ?? 0) selected targets captured")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Recapture Selection") { update(effect) { current in
                        var mask = current.mask ?? EffectMaskDefinition(kind: .selectedTargets)
                        mask.selectedTargets = orderedSelectionTargets.map(EffectTargetID.init)
                        current.mask = mask
                    } }
                }
                if effect.mask?.kind == .spatialRegion {
                    slider("Minimum X", effect.mask?.minimumX ?? -100, -1000...1000) { value in updateMask(effect) { $0.minimumX = min(value, $0.maximumX) } }
                    slider("Maximum X", effect.mask?.maximumX ?? 100, -1000...1000) { value in updateMask(effect) { $0.maximumX = max(value, $0.minimumX) } }
                    slider("Minimum Y", effect.mask?.minimumY ?? -100, -1000...1000) { value in updateMask(effect) { $0.minimumY = min(value, $0.maximumY) } }
                    slider("Maximum Y", effect.mask?.maximumY ?? 100, -1000...1000) { value in updateMask(effect) { $0.maximumY = max(value, $0.minimumY) } }
                }
                HStack {
                    Button("Move Up") { moveSelected(effect, offset: -1) }
                    Button("Move Down") { moveSelected(effect, offset: 1) }
                }
                if effect.templateLinkMode == .linked {
                    Label("Linked reusable effect", systemImage: "link")
                    Button("Detach") { effects.detachTemplate(id: effect.id); drafts[effect.id] = nil; changed() }
                } else {
                    Button("Create Linked Instance") { createLinkedInstance(from: effect) }
                }
                Button("Save as Effect Preset") { saveEffectPreset(effect) }
                ForEach(savedEffectPresets.prefix(5)) { preset in
                    Button(preset.name) { applyEffectPreset(preset, to: effect) }
                }
            }
            inspectSection("PROPERTY FAN") {
                Toggle("Static Scalar Fan", isOn: Binding(
                    get: { effect.scalarFan != nil },
                    set: { enabled in update(effect) { current in current.scalarFan = enabled ? (current.scalarFan ?? .init()) : nil } }
                ))
                if let fan = effect.scalarFan {
                    Picker("Property", selection: Binding(get: { fan.attribute }, set: { value in updateScalarFan(effect) { $0.attribute = value } })) {
                        ForEach(["intensity", "pan", "tilt", "zoom", "frost"], id: \.self) { Text(valueName($0)).tag($0) }
                    }
                    slider("Start", fan.start, 0...1) { value in updateScalarFan(effect) { $0.start = value } }
                    slider("End", fan.end, 0...1) { value in updateScalarFan(effect) { $0.end = value } }
                }
            }
            inspectSection("GENERATOR") {
                Picker("Shape", selection: Binding(
                    get: { effect.generator?.shape ?? .sine },
                    set: { shape in update(effect) { current in
                        var generator = current.generator ?? EffectGeneratorDefinition()
                        generator.shape = shape
                        if shape == .customCurve, generator.customCurve.isEmpty {
                            generator.customCurve = [.init(position: 0, value: 0), .init(position: 1, value: 1)]
                        }
                        current.generator = generator
                    } }
                )) {
                    ForEach(EffectGeneratorShape.allCases, id: \.self) {
                        Text(generatorName($0)).tag($0)
                    }
                }
                slider("Amplitude", effect.size, 0...1) { value in update(effect) { $0.size = value } }
                slider("Base", effect.base, 0...1) { value in update(effect) { $0.base = value } }
                if effect.generator?.shape == .pulse {
                    slider("Duty Cycle", effect.generator?.dutyCycle ?? 0.5, 0.01...0.99) { value in update(effect) { current in
                        var generator = current.generator ?? EffectGeneratorDefinition(shape: .pulse)
                        generator.dutyCycle = value
                        current.generator = generator
                    } }
                }
            }
            if effect.generator?.shape == .customCurve {
                inspectSection("CUSTOM CURVE") {
                    ForEach(effect.generator?.customCurve ?? []) { point in
                        VStack(spacing: 3) {
                            HStack {
                                Text("X").foregroundStyle(.secondary)
                                Slider(value: Binding(get: { point.position }, set: { value in updateCurvePoint(effect, id: point.id, position: value) }), in: 0...1)
                                Text(String(format: "%.2f", point.position)).monospacedDigit().frame(width: 34)
                            }
                            HStack {
                                Text("Y").foregroundStyle(.secondary)
                                Slider(value: Binding(get: { point.value }, set: { value in updateCurvePoint(effect, id: point.id, value: value) }), in: 0...1)
                                Text(String(format: "%.2f", point.value)).monospacedDigit().frame(width: 34)
                                Button { removeCurvePoint(effect, id: point.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button { addCurvePoint(effect) } label: { Label("Add Point", systemImage: "plus") }
                }
            }
            inspectSection("DIRECTION") {
                Picker("", selection: Binding(get: { effect.direction >= 0 }, set: { forward in update(effect) { $0.direction = forward ? 1 : -1 } })) {
                    Text("Forward").tag(true); Text("Reverse").tag(false)
                }.pickerStyle(.segmented)
            }
            inspectSection("DISTRIBUTION (FAN)") {
                Picker("Order", selection: Binding(
                    get: { effect.distribution?.order ?? .selection },
                    set: { order in updateDistribution(effect) { $0.order = order; $0.frozenOrder = nil } }
                )) {
                    ForEach(EffectDistributionOrder.allCases, id: \.self) { Text(distributionOrderName($0)).tag($0) }
                }
                Picker("Symmetry", selection: Binding(
                    get: { effect.distribution?.symmetry ?? .asymmetric },
                    set: { value in updateDistribution(effect) { $0.symmetry = value } }
                )) {
                    ForEach(EffectDistributionSymmetry.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Grouping: \(effect.distribution?.grouping ?? 1)", value: Binding(
                    get: { effect.distribution?.grouping ?? 1 },
                    set: { value in updateDistribution(effect) { $0.grouping = value } }
                ), in: 1...64)
                Stepper("Repetitions: \(effect.distribution?.repetitions ?? 1)", value: Binding(
                    get: { effect.distribution?.repetitions ?? 1 },
                    set: { value in updateDistribution(effect) { $0.repetitions = value } }
                ), in: 1...64)
                Picker("Curve", selection: Binding(
                    get: { effect.distribution?.curve ?? .linear },
                    set: { value in updateDistribution(effect) { $0.curve = value } }
                )) {
                    ForEach(EffectDistributionCurve.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
                }
                if effect.distribution?.order == .random {
                    field("Seed", "\(effect.distribution?.randomSeed ?? 0)")
                    Button("New Deterministic Seed") { updateDistribution(effect) { $0.randomSeed &+= 1 } }
                }
                if effect.distribution?.order == .custom {
                    ForEach(customOrderedTargets(effect), id: \.self) { target in
                        HStack {
                            Text(target.elementID ?? String(target.fixtureID.uuidString.prefix(8))).font(.caption.monospaced())
                            Spacer()
                            Button { moveCustomTarget(effect, target: target, offset: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain)
                            Button { moveCustomTarget(effect, target: target, offset: 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain)
                        }
                    }
                }
                if effect.distribution?.frozenOrder != nil {
                    Button("Return to Dynamic Spatial Order") { updateDistribution(effect) { $0.frozenOrder = nil } }
                } else if effect.distribution?.isSpatialRule == true {
                    Button("Freeze Current Spatial Order") { freezeSpatialOrder(effect) }
                }
                HStack {
                    Button("Pairs") { updateDistribution(effect) { $0.grouping = 2 } }
                    Button("Quads") { updateDistribution(effect) { $0.grouping = 4 } }
                    Button("Center Out") { updateDistribution(effect) { $0.order = .centerOut } }
                }
                Button("Save Fan Preset") { saveDistributionPreset(effect.distribution ?? .init()) }
                ForEach(savedDistributionPresets.prefix(5)) { preset in
                    Button(preset.name) { updateDistribution(effect) { $0 = preset.distribution } }
                }
            }
            if effect.kind == .colorGradient {
                gradientInspector(effect)
            }
            if effect.kind == .movement {
                movementInspector(effect)
            }
            if effect.kind == .pattern { patternInspector(effect) }
            cellTargetingInspector(effect)
        }
    }

    @ViewBuilder private func cellTargetingInspector(_ effect: EffectInstance) -> some View {
        let targeting = effect.cellTargeting ?? EffectCellTargetingDefinition()
        inspectSection("FIXTURES / CELLS") {
            Picker("Target", selection: Binding(get: { targeting.mode }, set: { value in updateCellTargeting(effect) { $0.mode = value } })) {
                Text("Whole Fixtures").tag(EffectCellTargetMode.fixtures)
                Text("All Cells").tag(EffectCellTargetMode.allCells)
                Text("Selected Cells").tag(EffectCellTargetMode.selectedCells)
            }
            Picker("Cell Order", selection: Binding(get: { targeting.order }, set: { value in updateCellTargeting(effect) { $0.order = value } })) {
                Text("Forward").tag(EffectCellOrder.forward); Text("Reverse").tag(EffectCellOrder.reverse)
            }
            Stepper("Cell Grouping: \(targeting.grouping)", value: Binding(get: { targeting.grouping }, set: { value in updateCellTargeting(effect) { $0.grouping = value } }), in: 1...64)
            if targeting.mode == .selectedCells { field("Selected Cells", "\(targeting.selectedTargets.count)") }
        }
    }

    private var initialCellTargeting: EffectCellTargetingDefinition? {
        let cells = orderedSelectionTargets.filter { $0.elementID != nil }.map(EffectTargetID.init)
        return cells.isEmpty ? nil : .init(mode: .selectedCells, selectedTargets: cells)
    }
    private func changed() { revision &+= 1; onChanged() }
    private func reconcileSelection() { if selectedID == nil || !running.contains(where: { $0.id == selectedID }) { selectedID = running.first?.id } }

    private func tool(_ title: String, _ image: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 3) { Image(systemName: image); Text(title).font(.caption2) } }.buttonStyle(.plain).frame(width: 58) }
    private func resizeDivider(width: Binding<Double>, range: ClosedRange<Double>, direction: Double) -> some View {
        EffectsResizeHandle(value: width, range: range, direction: direction, axis: .horizontal)
    }
    private func horizontalResizeHandle(value: Binding<Double>, range: ClosedRange<Double>, direction: Double) -> some View {
        EffectsResizeHandle(value: value, range: range, direction: direction, axis: .vertical)
    }
    private func sectionTitle(_ text: String) -> some View { Text(text).font(.caption2.bold()).foregroundStyle(.secondary) }
    private func field(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1) }.font(.caption) }
    private func slider(_ title: String, _ value: Double, _ range: ClosedRange<Double>, changed: @escaping (Double) -> Void) -> some View { VStack(spacing: 3) { HStack { Text(title); Spacer(); Text(String(format: "%.2f", value)).monospacedDigit() }.font(.caption); Slider(value: Binding(get: { value }, set: changed), in: range) } }

    @ViewBuilder private func timingCell<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 8) { sectionTitle(title); content(); Spacer(minLength: 0) }.font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .trailing) { Divider() } }
    private func visualCard<Content: View>(_ title: String, content: Content) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption2.bold()).foregroundStyle(AuroraColor.accent); content.frame(maxWidth: .infinity, maxHeight: .infinity) }.padding(10).background(AuroraColor.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 5)) }
    @ViewBuilder private func inspectSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 9) { sectionTitle(title); content() }.padding(10).background(.black.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 5)) }

    private func icon(_ name: String) -> String {
        ["Favorites": "star.fill", "Color": "paintpalette.fill", "Intensity": "sun.max.fill", "Movement": "move.3d", "Beam": "light.beacon.max.fill", "Pixel": "square.grid.3x3.fill", "Atmosphere": "aqi.medium"][name] ?? "slider.horizontal.3"
    }

    private func category(for kind: EffectKind) -> String {
        switch kind {
        case .pulse, .chase, .wave: return "Intensity"
        case .rainbow, .colorStep, .colorGradient: return "Color"
        case .positionCircle, .movement: return "Movement"
        case .beamPulse: return "Beam"
        case .cellChase: return "Pixel"
        case .pattern: return "Custom"
        }
    }

    @ViewBuilder private func patternInspector(_ effect: EffectInstance) -> some View {
        let pattern = effect.pattern ?? EffectPatternDefinition()
        inspectSection("PATTERN") {
            Picker("Pattern", selection: Binding(get: { pattern.kind }, set: { value in updatePattern(effect) { $0.kind = value } })) {
                ForEach(EffectPatternKind.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
            }
            slider("Width", pattern.width, 0.01...1) { value in updatePattern(effect) { $0.width = value } }
            slider("Softness", pattern.softness, 0...1) { value in updatePattern(effect) { $0.softness = value } }
            slider("Density", pattern.density, 0...1) { value in updatePattern(effect) { $0.density = value } }
            slider("Trail", pattern.trail, 0...1) { value in updatePattern(effect) { $0.trail = value } }
            field("Random Seed", "\(pattern.randomSeed)")
            Button("New Deterministic Seed") { updatePattern(effect) { $0.randomSeed &+= 1 } }
        }
    }

    @ViewBuilder private func gradientInspector(_ effect: EffectInstance) -> some View {
        let gradient = effect.colorGradient ?? EffectColorGradientDefinition()
        inspectSection("COLOR GRADIENT") {
            GradientStopEditor(stops: gradient.stops) { stops in updateGradient(effect) { $0.stops = stops } }
                .frame(height: 54)
            Picker("Interpolation", selection: Binding(
                get: { gradient.interpolation },
                set: { value in updateGradient(effect) { $0.interpolation = value } }
            )) {
                ForEach(EffectColorInterpolation.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
            }
            Toggle("Reverse", isOn: Binding(get: { gradient.reversed }, set: { value in updateGradient(effect) { $0.reversed = value } }))
            Toggle("Mirror", isOn: Binding(get: { gradient.mirrored }, set: { value in updateGradient(effect) { $0.mirrored = value } }))
            slider("Position", gradient.positionOffset, -1...1) { value in updateGradient(effect) { $0.positionOffset = value } }
            ForEach(gradient.stops) { stop in
                VStack(spacing: 3) {
                    slider("Stop", stop.position, 0...1) { value in updateGradientStop(effect, id: stop.id, position: value) }
                    HStack(spacing: 4) {
                        colorChannel("R", stop.color.red, effect: effect, stopID: stop.id, keyPath: \.red)
                        colorChannel("G", stop.color.green, effect: effect, stopID: stop.id, keyPath: \.green)
                        colorChannel("B", stop.color.blue, effect: effect, stopID: stop.id, keyPath: \.blue)
                        Button { removeGradientStop(effect, id: stop.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
            }
            Button { addGradientStop(effect) } label: { Label("Add Stop", systemImage: "plus") }
            Divider()
            HStack {
                Button("Blue → Magenta") { updateGradient(effect) { $0 = Self.blueMagentaGradient } }
                Button("Rainbow") { updateGradient(effect) { $0 = Self.rainbowGradient } }
            }
            Button("Save Gradient as Preset") { saveGradientPreset(gradient) }
            ForEach(savedGradientPresets) { preset in
                Button(preset.name) { updateGradient(effect) { $0 = preset.gradient } }
            }
        }
    }

    private func colorChannel(_ name: String, _ value: Double, effect: EffectInstance, stopID: UUID, keyPath: WritableKeyPath<EffectColor, Double>) -> some View {
        VStack { Text(name).font(.caption2); Slider(value: Binding(get: { value }, set: { newValue in updateGradientStop(effect, id: stopID, color: (keyPath, newValue)) }), in: 0...1) }
    }

    @ViewBuilder private func movementInspector(_ effect: EffectInstance) -> some View {
        let movement = effect.movement ?? EffectMovementDefinition()
        inspectSection("MOVEMENT PATH") {
            Picker("Template", selection: Binding(get: { movement.template }, set: { value in updateMovement(effect) { $0.template = value } })) {
                ForEach(EffectMovementTemplate.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
            }
            Picker("Coordinates", selection: Binding(get: { movement.coordinateMode }, set: { value in updateMovement(effect) { $0.coordinateMode = value } })) {
                Text("Relative to Focus").tag(EffectMovementCoordinateMode.relative)
                Text("Absolute").tag(EffectMovementCoordinateMode.absolute)
            }
            Picker("Interpolation", selection: Binding(get: { movement.interpolation }, set: { value in updateMovement(effect) { $0.interpolation = value } })) {
                ForEach(EffectMovementInterpolation.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            slider("Width", movement.width, 0...1) { value in updateMovement(effect) { $0.width = value } }
            slider("Height", movement.height, 0...1) { value in updateMovement(effect) { $0.height = value } }
            slider("Rotation", movement.rotation, -1...1) { value in updateMovement(effect) { $0.rotation = value } }
            Toggle("Mirror Pan", isOn: Binding(get: { movement.mirrorPan }, set: { value in updateMovement(effect) { $0.mirrorPan = value } }))
            Toggle("Mirror Tilt", isOn: Binding(get: { movement.mirrorTilt }, set: { value in updateMovement(effect) { $0.mirrorTilt = value } }))
            if movement.coordinateMode == .absolute {
                slider("Pan Center", movement.centerPan, 0...1) { value in updateMovement(effect) { $0.centerPan = value } }
                slider("Tilt Center", movement.centerTilt, 0...1) { value in updateMovement(effect) { $0.centerTilt = value } }
            }
            if movement.template == .customPath {
                MovementPathEditor(points: movement.customPath) { points in updateMovement(effect) { $0.customPath = points } }
                    .frame(height: 180)
                HStack {
                    Button("Add Point") { updateMovement(effect) { $0.customPath.append(.init(x: 0, y: 0)) } }
                    Button("Clear") { updateMovement(effect) { $0.customPath.removeAll() } }
                }
            }
        }
    }

    private func generatorName(_ shape: EffectGeneratorShape) -> String {
        switch shape {
        case .sawUp: return "Saw Up"
        case .sawDown: return "Saw Down"
        case .customCurve: return "Custom Curve"
        default: return shape.rawValue.capitalized
        }
    }

    private func clockSourceName(_ effect: EffectInstance?) -> String {
        guard let timing = effect?.timing else { return "Free Run (Legacy)" }
        return clockSourceName(timing.source)
    }

    private func clockSourceName(_ source: EffectClockSource) -> String {
        switch source {
        case .freeRun: return "Free Run"
        case .internalBPM: return "Internal BPM"
        case .musicEngine: return "Music Engine"
        case .midiClock: return "MIDI Clock"
        case .ame: return "AME"
        }
    }

    private func timingRateMode(_ effect: EffectInstance) -> TimingRateMode {
        switch effect.timing?.rate {
        case .periodSeconds?: return .period
        case .musical?: return .musical
        case .frequencyHz?, nil: return .frequency
        }
    }

    @ViewBuilder private func timingRateControls(_ effect: EffectInstance) -> some View {
        switch effect.timing?.rate ?? .frequencyHz(effect.rateHz) {
        case let .frequencyHz(value):
            slider("Frequency (Hz)", value, 0.01...20) { newValue in updateTiming(effect) { $0.rate = .frequencyHz(newValue) } }
        case let .periodSeconds(value):
            slider("Period (seconds)", value, 0.05...60) { newValue in updateTiming(effect) { $0.rate = .periodSeconds(newValue) } }
        case let .musical(duration):
            Picker("Unit", selection: Binding(get: { duration.unit }, set: { value in updateMusicalRate(effect) { $0.unit = value } })) {
                Text("Note").tag(EffectMusicalDurationUnit.note)
                Text("Beat").tag(EffectMusicalDurationUnit.metricalBeat)
                Text("Bar").tag(EffectMusicalDurationUnit.bar)
            }
            if duration.unit == .note {
                Picker("Division", selection: Binding(get: { duration.noteDivision }, set: { value in updateMusicalRate(effect) { $0.noteDivision = value } })) {
                    ForEach(EffectNoteDivision.allCases, id: \.self) { Text(noteDivisionName($0)).tag($0) }
                }
            } else {
                Picker("Count", selection: Binding(get: { duration.count }, set: { value in updateMusicalRate(effect) { $0.count = value } })) {
                    ForEach([1.0, 2.0, 4.0, 8.0], id: \.self) { Text(String(format: "%.0f", $0)).tag($0) }
                }
            }
            Picker("Modifier", selection: Binding(get: { duration.modifier }, set: { value in updateMusicalRate(effect) { $0.modifier = value } })) {
                ForEach(EffectTimingModifier.allCases, id: \.self) { Text(valueName($0.rawValue)).tag($0) }
            }
        }
    }

    private func noteDivisionName(_ division: EffectNoteDivision) -> String {
        switch division {
        case .thirtySecond: return "1/32"
        case .sixteenth: return "1/16"
        case .eighth: return "1/8"
        case .quarter: return "1/4"
        case .half: return "1/2"
        case .whole: return "Whole"
        }
    }

    private func rateDescription(_ effect: EffectInstance?) -> String {
        guard let effect else { return "—" }
        guard let rate = effect.timing?.rate else { return String(format: "%.2f Hz", effect.rateHz) }
        switch rate {
        case let .frequencyHz(value): return String(format: "%.2f Hz", value)
        case let .periodSeconds(value): return String(format: "%.2f sec", value)
        case let .musical(duration):
            switch duration.unit {
            case .bar: return duration.count == 1 ? "1 Bar" : String(format: "%.2g Bars", duration.count)
            case .metricalBeat: return duration.count == 1 ? "1 Beat" : String(format: "%.2g Beats", duration.count)
            case .note: return duration.noteDivision.rawValue.capitalized
            }
        }
    }

    private func modifierDescription(_ effect: EffectInstance?) -> String {
        guard case let .musical(duration)? = effect?.timing?.rate else { return "Continuous" }
        return duration.modifier.rawValue.capitalized
    }

    private func bpmDescription(_ effect: EffectInstance?) -> String {
        guard let timing = effect?.timing else { return "—" }
        switch timing.source {
        case .freeRun: return "—"
        case .internalBPM: return String(format: "%.1f", timing.internalBPM)
        case .musicEngine, .midiClock, .ame: return "External"
        }
    }

    private func timingStatusDescription(_ frame: EffectEvaluationResult?) -> String {
        guard let id = selected?.id, let sample = frame?.timingSamples[id] else { return "Legacy continuous" }
        let status = sample.status
        let source = sample.sourceID
        return "\(status.rawValue.capitalized) · \(source)"
    }

    private func timingStatusColor(_ frame: EffectEvaluationResult?) -> Color {
        let status = selected.flatMap { frame?.timingSamples[$0.id]?.status }
        switch status {
        case .running, .fallback: return .green
        case .waitingForQuantization, .holding: return .yellow
        case .stopped: return .secondary
        case nil: return .secondary
        }
    }

    private func quantizationDescription(_ effect: EffectInstance?) -> String {
        effect?.timing?.startQuantization.rawValue.capitalized ?? "Immediate"
    }

    private func updateDistribution(_ effect: EffectInstance, mutation: (inout FixtureDistributionDefinition) -> Void) {
        update(effect) { current in
            var distribution = current.distribution ?? FixtureDistributionDefinition()
            mutation(&distribution)
            current.distribution = distribution
        }
    }

    private func customOrderedTargets(_ effect: EffectInstance) -> [EffectTargetID] {
        let eligible = effect.fixtureIDs.map { EffectTargetID(fixtureID: $0) }
        let explicit = effect.distribution?.customOrder ?? []
        let eligibleSet = Set(eligible)
        return explicit.filter(eligibleSet.contains) + eligible.filter { !Set(explicit).contains($0) }
    }

    private func moveCustomTarget(_ effect: EffectInstance, target: EffectTargetID, offset: Int) {
        updateDistribution(effect) { distribution in
            var ordered = customOrderedTargets(effect)
            guard let index = ordered.firstIndex(of: target) else { return }
            let destination = min(max(0, index + offset), ordered.count - 1)
            guard destination != index else { return }
            ordered.swapAt(index, destination)
            distribution.customOrder = ordered
        }
    }

    private func freezeSpatialOrder(_ effect: EffectInstance) {
        let targets = effect.fixtureIDs.map { EffectTargetID(fixtureID: $0) }
        update(effect) { current in
            let definition = current.distribution ?? FixtureDistributionDefinition()
            current.distribution = EffectDistributionResolver.freezeCurrentSpatialOrder(
                targets: targets,
                definition: definition,
                stagePlacements: stagePlacements
            )
        }
    }

    private func updateGradient(_ effect: EffectInstance, mutation: (inout EffectColorGradientDefinition) -> Void) {
        update(effect) { current in
            var gradient = current.colorGradient ?? EffectColorGradientDefinition()
            mutation(&gradient)
            current.colorGradient = gradient
        }
    }

    private func updateMovement(_ effect: EffectInstance, mutation: (inout EffectMovementDefinition) -> Void) {
        update(effect) { current in
            var movement = current.movement ?? EffectMovementDefinition()
            mutation(&movement)
            current.movement = movement
        }
    }

    private func updatePattern(_ effect: EffectInstance, mutation: (inout EffectPatternDefinition) -> Void) {
        update(effect) { current in
            var pattern = current.pattern ?? EffectPatternDefinition()
            mutation(&pattern)
            current.pattern = pattern
        }
    }

    private func updateCellTargeting(_ effect: EffectInstance, mutation: (inout EffectCellTargetingDefinition) -> Void) {
        update(effect) { current in
            var targeting = current.cellTargeting ?? EffectCellTargetingDefinition()
            mutation(&targeting)
            if targeting.mode == .selectedCells {
                targeting.selectedTargets = orderedSelectionTargets.filter { $0.elementID != nil }.map(EffectTargetID.init)
            }
            current.cellTargeting = targeting
        }
    }

    private func updateMask(_ effect: EffectInstance, mutation: (inout EffectMaskDefinition) -> Void) {
        update(effect) { current in
            var mask = current.mask ?? EffectMaskDefinition(kind: .spatialRegion, minimumX: -100, maximumX: 100, minimumY: -100, maximumY: 100)
            mutation(&mask)
            current.mask = mask
        }
    }

    private func updateScalarFan(_ effect: EffectInstance, mutation: (inout EffectScalarFanDefinition) -> Void) {
        update(effect) { current in
            var fan = current.scalarFan ?? EffectScalarFanDefinition()
            mutation(&fan)
            current.scalarFan = fan
        }
    }

    private func updateGradientStop(_ effect: EffectInstance, id: UUID, position: Double? = nil, color: (WritableKeyPath<EffectColor, Double>, Double)? = nil) {
        updateGradient(effect) { gradient in
            guard let index = gradient.stops.firstIndex(where: { $0.id == id }) else { return }
            if let position { gradient.stops[index].position = min(1, max(0, position)) }
            if let color { gradient.stops[index].color[keyPath: color.0] = min(1, max(0, color.1)) }
        }
    }

    private func addGradientStop(_ effect: EffectInstance) {
        updateGradient(effect) { gradient in
            gradient.stops.append(.init(position: 0.5, color: EffectColor(red: 1, green: 1, blue: 1)))
        }
    }

    private func removeGradientStop(_ effect: EffectInstance, id: UUID) {
        updateGradient(effect) { gradient in
            guard gradient.stops.count > 1 else { return }
            gradient.stops.removeAll { $0.id == id }
        }
    }

    private var savedGradientPresets: [EffectColorGradientPreset] {
        guard let data = storedGradientPresets.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([EffectColorGradientPreset].self, from: data)) ?? []
    }

    private func saveGradientPreset(_ gradient: EffectColorGradientDefinition) {
        var presets = savedGradientPresets
        presets.append(.init(name: "Saved Gradient \(presets.count + 1)", gradient: gradient))
        if let data = try? JSONEncoder().encode(presets) { storedGradientPresets = String(decoding: data, as: UTF8.self) }
    }

    private var savedDistributionPresets: [EffectDistributionPreset] {
        guard let data = storedDistributionPresets.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([EffectDistributionPreset].self, from: data)) ?? []
    }

    private func saveDistributionPreset(_ distribution: FixtureDistributionDefinition) {
        var presets = savedDistributionPresets
        presets.append(.init(name: "Saved Fan \(presets.count + 1)", distribution: distribution))
        if let data = try? JSONEncoder().encode(presets) { storedDistributionPresets = String(decoding: data, as: UTF8.self) }
    }

    private static let blueMagentaGradient = EffectColorGradientDefinition(stops: [
        .init(position: 0, color: .init(red: 0, green: 0.15, blue: 1)),
        .init(position: 1, color: .init(red: 1, green: 0, blue: 0.8)),
    ])
    private static let rainbowGradient = EffectColorGradientDefinition(stops: [
        .init(position: 0, color: .init(red: 1, green: 0, blue: 0)),
        .init(position: 0.33, color: .init(red: 0, green: 1, blue: 0)),
        .init(position: 0.66, color: .init(red: 0, green: 0, blue: 1)),
        .init(position: 1, color: .init(red: 1, green: 0, blue: 0)),
    ], interpolation: .hsvShortest)

    private func evaluatedColor(frame: EffectEvaluationResult?, fixtureID: UUID?) -> Color {
        guard let fixtureID, let attributes = frame?.semanticLook.fixtureAttributes[fixtureID] else { return AuroraColor.accent }
        return Color(red: attributes["colorR"] ?? 0.1, green: attributes["colorG"] ?? 0.35, blue: attributes["colorB"] ?? 1)
    }

    private func distributionOrderName(_ order: EffectDistributionOrder) -> String { valueName(order.rawValue) }
    private func valueName(_ raw: String) -> String {
        raw.reduce(into: "") { result, character in
            if character.isUppercase { result.append(" ") }
            result.append(character)
        }.capitalized
    }

    private func addCurvePoint(_ effect: EffectInstance) {
        update(effect) { current in
            var generator = current.generator ?? EffectGeneratorDefinition(shape: .customCurve)
            let occupied = Set(generator.customCurve.map { Int(($0.position * 10).rounded()) })
            let slot = (0...10).first { !occupied.contains($0) } ?? 5
            generator.customCurve.append(.init(position: Double(slot) / 10, value: 0.5))
            current.generator = generator
        }
    }

    private func updateCurvePoint(_ effect: EffectInstance, id: UUID, value: Double) {
        update(effect) { current in
            guard var generator = current.generator, let index = generator.customCurve.firstIndex(where: { $0.id == id }) else { return }
            generator.customCurve[index].value = value
            current.generator = generator
        }
    }

    private func updateCurvePoint(_ effect: EffectInstance, id: UUID, position: Double) {
        update(effect) { current in
            guard var generator = current.generator, let index = generator.customCurve.firstIndex(where: { $0.id == id }) else { return }
            let others = generator.customCurve.filter { $0.id != id }.map(\.position).sorted()
            let lower = others.last(where: { $0 < generator.customCurve[index].position }).map { $0 + 0.001 } ?? 0
            let upper = others.first(where: { $0 > generator.customCurve[index].position }).map { $0 - 0.001 } ?? 1
            generator.customCurve[index].position = min(upper, max(lower, position))
            current.generator = generator
        }
    }

    private func updateRate(_ effect: EffectInstance, value: Double) {
        update(effect) { current in
            current.rateHz = value
            if current.timing != nil { current.timing?.rate = .frequencyHz(value) }
        }
    }

    private func updateTiming(_ effect: EffectInstance, mutation: (inout EffectTimingDefinition) -> Void) {
        update(effect) { current in
            var timing = current.timing ?? EffectTimingDefinition(source: .freeRun, rate: .frequencyHz(max(0.001, current.rateHz)))
            mutation(&timing)
            switch timing.rate {
            case let .frequencyHz(value): current.rateHz = max(0, value)
            case let .periodSeconds(value): current.rateHz = 1 / max(0.001, value)
            case .musical: break
            }
            current.timing = timing
        }
    }

    private func updateMusicalRate(_ effect: EffectInstance, mutation: (inout EffectMusicalDuration) -> Void) {
        updateTiming(effect) { timing in
            var duration: EffectMusicalDuration
            if case let .musical(existing) = timing.rate { duration = existing }
            else { duration = .init(unit: .note, noteDivision: .quarter) }
            mutation(&duration)
            timing.rate = .musical(duration)
        }
    }

    private func tapTempo(_ effect: EffectInstance) {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTapTime = now }
        guard let lastTapTime else { return }
        let interval = now - lastTapTime
        guard (0.2...3).contains(interval) else { return }
        updateTiming(effect) { $0.internalBPM = min(300, max(20, 60 / interval)) }
    }

    private var recentIDs: [UUID] {
        storedRecentIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    private var recentEffects: [EffectInstance] {
        let byID = Dictionary(uniqueKeysWithValues: running.map { ($0.id, $0) })
        return recentIDs.compactMap { byID[$0] }
    }

    private func selectEffect(_ effect: EffectInstance) {
        selectedID = effect.id
        recordRecent(effect.id)
    }

    private func recordRecent(_ id: UUID) {
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        storedRecentIDs = ids.prefix(12).map(\.uuidString).joined(separator: ",")
    }

    private func removeCurvePoint(_ effect: EffectInstance, id: UUID) {
        update(effect) { current in
            guard var generator = current.generator else { return }
            generator.customCurve.removeAll { $0.id == id }
            current.generator = generator
        }
    }
}

private struct EffectsResizeHandle: View {
    enum Axis { case horizontal, vertical }
    @Binding var value: Double
    let range: ClosedRange<Double>
    let direction: Double
    let axis: Axis
    @State private var initialValue: Double?

    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08))
            .frame(width: axis == .horizontal ? 5 : nil, height: axis == .vertical ? 5 : nil)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                let initial = initialValue ?? value
                if initialValue == nil { initialValue = initial }
                let translation = axis == .horizontal ? gesture.translation.width : gesture.translation.height
                value = min(range.upperBound, max(range.lowerBound, initial + translation * direction))
            }.onEnded { _ in initialValue = nil })
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

private struct BeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: .init(x: rect.midX - rect.width * 0.12, y: rect.minY)); path.addLine(to: .init(x: rect.midX + rect.width * 0.12, y: rect.minY)); path.addLine(to: .init(x: rect.maxX, y: rect.maxY)); path.addLine(to: .init(x: rect.minX, y: rect.maxY)); path.closeSubpath(); return path
    }
}

private struct MovementPathEditor: View {
    let points: [EffectMovementPoint]
    let onChange: ([EffectMovementPoint]) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.35))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: screen(first, size: proxy.size))
                    for point in points.dropFirst() { path.addLine(to: screen(point, size: proxy.size)) }
                    if points.count > 1 { path.closeSubpath() }
                }.stroke(.purple, lineWidth: 2)
                ForEach(points) { point in
                    Circle().fill(AuroraColor.accent).frame(width: 12, height: 12)
                        .position(screen(point, size: proxy.size))
                        .gesture(DragGesture().onChanged { gesture in
                            var updated = points
                            guard let index = updated.firstIndex(where: { $0.id == point.id }) else { return }
                            updated[index].x = min(1, max(-1, gesture.location.x / proxy.size.width * 2 - 1))
                            updated[index].y = min(1, max(-1, gesture.location.y / proxy.size.height * 2 - 1))
                            onChange(updated)
                        })
                }
            }
        }
    }

    private func screen(_ point: EffectMovementPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (point.x + 1) * 0.5 * size.width, y: (point.y + 1) * 0.5 * size.height)
    }
}

private struct GradientStopEditor: View {
    let stops: [EffectGradientStop]
    let onChange: ([EffectGradientStop]) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(gradient: Gradient(stops: stops.sorted(by: { $0.position < $1.position }).map {
                        Gradient.Stop(color: Color(red: $0.color.red, green: $0.color.green, blue: $0.color.blue), location: $0.position)
                    }), startPoint: .leading, endPoint: .trailing))
                    .frame(height: 30)
                ForEach(stops) { stop in
                    Image(systemName: "triangle.fill")
                        .font(.caption).foregroundStyle(.white)
                        .position(x: stop.position * proxy.size.width, y: 42)
                        .gesture(DragGesture().onChanged { gesture in
                            var updated = stops
                            guard let index = updated.firstIndex(where: { $0.id == stop.id }) else { return }
                            updated[index].position = min(1, max(0, gesture.location.x / proxy.size.width))
                            onChange(updated)
                        })
                }
            }
        }
    }
}
