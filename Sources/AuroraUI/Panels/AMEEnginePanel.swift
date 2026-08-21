import AuroraDesignSystem
import AuroraEngine
import AuroraModel
import AuroraMusical
import SwiftUI

/// Dedicated Advanced MIDI Engine workspace (Wave 5 command-backed inspector).
public struct AMEEnginePanel: View {
    public var project: ShowProject
    public var performanceMode: AMEPerformanceMode
    public var onPerformanceModeChange: (AMEPerformanceMode) -> Void
    public var musicalState: MusicalState
    public var monitorEvents: [AMEDiagnosticEvent]
    public var validationIssues: [AMEValidationIssue]
    public var onSelectMapping: (UUID) -> Void
    public var selectedMappingID: UUID?
    public var selectedTriggerID: UUID?
    public var selectedSequenceID: UUID?
    public var isLearning: Bool
    public var onSelectTrigger: (UUID) -> Void
    public var onSelectSequence: (UUID) -> Void
    public var onAddTrigger: () -> Void
    public var onAddMapping: () -> Void
    public var onAddSequence: () -> Void
    public var onDeleteMapping: (UUID) -> Void
    public var onDeleteTrigger: (UUID) -> Void
    public var onDeleteSequence: (UUID) -> Void
    public var onDuplicateMapping: (UUID) -> Void
    public var onDuplicateTrigger: (UUID) -> Void
    public var onDuplicateSequence: (UUID) -> Void
    public var onUpdateMapping: (AMEMapping) -> Void
    public var onUpdateTrigger: (AMETriggerDefinition) -> Void
    public var onUpdateSequence: (AMETriggeredSequence) -> Void
    public var onUpdateMusicalSettings: (MusicalEngineProjectSettings) -> Void
    public var onUpsertSourceBinding: (MIDISourceBinding) -> Void
    public var onDeleteSourceBinding: (UUID) -> Void
    public var onLearn: () -> Void
    public var onCancelLearn: () -> Void
    public var onSelectValidationIssue: (AMEValidationIssue) -> Void

    public init(
        project: ShowProject,
        performanceMode: AMEPerformanceMode,
        onPerformanceModeChange: @escaping (AMEPerformanceMode) -> Void,
        musicalState: MusicalState,
        monitorEvents: [AMEDiagnosticEvent],
        validationIssues: [AMEValidationIssue],
        selectedMappingID: UUID? = nil,
        selectedTriggerID: UUID? = nil,
        selectedSequenceID: UUID? = nil,
        isLearning: Bool = false,
        onSelectMapping: @escaping (UUID) -> Void = { _ in },
        onSelectTrigger: @escaping (UUID) -> Void = { _ in },
        onSelectSequence: @escaping (UUID) -> Void = { _ in },
        onAddTrigger: @escaping () -> Void = {},
        onAddMapping: @escaping () -> Void = {},
        onAddSequence: @escaping () -> Void = {},
        onDeleteMapping: @escaping (UUID) -> Void = { _ in },
        onDeleteTrigger: @escaping (UUID) -> Void = { _ in },
        onDeleteSequence: @escaping (UUID) -> Void = { _ in },
        onDuplicateMapping: @escaping (UUID) -> Void = { _ in },
        onDuplicateTrigger: @escaping (UUID) -> Void = { _ in },
        onDuplicateSequence: @escaping (UUID) -> Void = { _ in },
        onUpdateMapping: @escaping (AMEMapping) -> Void = { _ in },
        onUpdateTrigger: @escaping (AMETriggerDefinition) -> Void = { _ in },
        onUpdateSequence: @escaping (AMETriggeredSequence) -> Void = { _ in },
        onUpdateMusicalSettings: @escaping (MusicalEngineProjectSettings) -> Void = { _ in },
        onUpsertSourceBinding: @escaping (MIDISourceBinding) -> Void = { _ in },
        onDeleteSourceBinding: @escaping (UUID) -> Void = { _ in },
        onLearn: @escaping () -> Void = {},
        onCancelLearn: @escaping () -> Void = {},
        onSelectValidationIssue: @escaping (AMEValidationIssue) -> Void = { _ in }
    ) {
        self.project = project
        self.performanceMode = performanceMode
        self.onPerformanceModeChange = onPerformanceModeChange
        self.musicalState = musicalState
        self.monitorEvents = monitorEvents
        self.validationIssues = validationIssues
        self.selectedMappingID = selectedMappingID
        self.selectedTriggerID = selectedTriggerID
        self.selectedSequenceID = selectedSequenceID
        self.isLearning = isLearning
        self.onSelectMapping = onSelectMapping
        self.onSelectTrigger = onSelectTrigger
        self.onSelectSequence = onSelectSequence
        self.onAddTrigger = onAddTrigger
        self.onAddMapping = onAddMapping
        self.onAddSequence = onAddSequence
        self.onDeleteMapping = onDeleteMapping
        self.onDeleteTrigger = onDeleteTrigger
        self.onDeleteSequence = onDeleteSequence
        self.onDuplicateMapping = onDuplicateMapping
        self.onDuplicateTrigger = onDuplicateTrigger
        self.onDuplicateSequence = onDuplicateSequence
        self.onUpdateMapping = onUpdateMapping
        self.onUpdateTrigger = onUpdateTrigger
        self.onUpdateSequence = onUpdateSequence
        self.onUpdateMusicalSettings = onUpdateMusicalSettings
        self.onUpsertSourceBinding = onUpsertSourceBinding
        self.onDeleteSourceBinding = onDeleteSourceBinding
        self.onLearn = onLearn
        self.onCancelLearn = onCancelLearn
        self.onSelectValidationIssue = onSelectValidationIssue
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            timingStrip
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                VStack(spacing: 0) {
                    inspector
                    Divider()
                    monitor
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Text("MIDI Engine")
                .font(.headline)
            if isLearning {
                Text("Learning… hit a pad/key")
                    .foregroundStyle(.orange)
                Button("Cancel Learn") { onCancelLearn() }
            } else {
                Button("Learn MIDI") { onLearn() }
            }
            Button("+ Trigger") { onAddTrigger() }
            Button("+ Mapping") { onAddMapping() }
            Button("+ Sequence") { onAddSequence() }
            Spacer()
            Picker("Mode", selection: Binding(
                get: { performanceMode },
                set: { onPerformanceModeChange($0) }
            )) {
                Text("Edit").tag(AMEPerformanceMode.edit)
                Text("Dry-Run").tag(AMEPerformanceMode.dryRun)
                Text("Armed").tag(AMEPerformanceMode.armed)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            modeBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var modeBadge: some View {
        let (label, color): (String, Color) = {
            switch performanceMode {
            case .armed: return ("ARMED", .red)
            case .dryRun: return ("DRY-RUN", .orange)
            case .edit: return ("EDIT", .secondary)
            }
        }()
        return Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var timingStrip: some View {
        let t = musicalState.timing
        return HStack(spacing: 16) {
            labeled("Source", t.activeSourceID ?? "—")
            labeled("Tempo", t.tempoBPM.map { String(format: "%.1f BPM", $0) } ?? "—")
            labeled("Transport", t.transport.rawValue)
            labeled("Sync", t.sync.rawValue)
            if let bb = t.barBeat {
                labeled("Bar/Beat", "\(bb.barIndex).\(bb.beatIndexInBar)")
            }
            Spacer()
            Text("Policy: \(t.timingPolicy.rawValue)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var sidebar: some View {
        List {
            Section("Project Timing") {
                timingSettingsRows
            }
            Section("MIDI Sources (\(project.ame.sourceBindings.count))") {
                ForEach(project.ame.sourceBindings) { binding in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.displayName.isEmpty ? "Source" : binding.displayName)
                            Text(binding.lastCoreMIDIUniqueID.map { "uid:\($0)" } ?? (binding.endpointNameHint ?? "no UID"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { binding.enabled },
                            set: { en in
                                var b = binding
                                b.enabled = en
                                onUpsertSourceBinding(b)
                            }
                        ))
                        .labelsHidden()
                        Button(role: .destructive) { onDeleteSourceBinding(binding.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    }
                }
                Button("Add Source Binding") {
                    onUpsertSourceBinding(MIDISourceBinding(displayName: "Source \(project.ame.sourceBindings.count + 1)"))
                }
            }
            Section("Triggers (\(project.ame.triggers.count))") {
                ForEach(project.ame.triggers) { trigger in
                    HStack {
                        Button {
                            onSelectTrigger(trigger.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trigger.name.isEmpty ? trigger.friendlyName : trigger.name)
                                Text("\(trigger.messageType.rawValue) ch\(trigger.channel.map { String($0 + 1) } ?? "*")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if trigger.id == selectedTriggerID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        Button(role: .destructive) {
                            onDeleteTrigger(trigger.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    }
                    .contextMenu {
                        Button("Duplicate") { onDuplicateTrigger(trigger.id) }
                        Button("Delete", role: .destructive) { onDeleteTrigger(trigger.id) }
                    }
                }
            }
            Section("Mappings (\(project.ame.mappings.count))") {
                ForEach(project.ame.mappings) { mapping in
                    HStack {
                        Button {
                            onSelectMapping(mapping.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mapping.name.isEmpty ? mapping.id.uuidString.prefix(8).description : mapping.name)
                                    Text(mapping.behavior.rawValue + (mapping.enabled ? "" : " · disabled"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if mapping.id == selectedMappingID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            onDeleteMapping(mapping.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    }
                    .contextMenu {
                        Button("Duplicate") { onDuplicateMapping(mapping.id) }
                        Button("Delete", role: .destructive) { onDeleteMapping(mapping.id) }
                    }
                }
            }
            Section("Sequences (\(project.ame.sequences.count))") {
                ForEach(project.ame.sequences) { seq in
                    HStack {
                        Button {
                            onSelectSequence(seq.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(seq.name.isEmpty ? "Sequence" : seq.name)
                                Text("\(seq.steps.count) steps · \(seq.mode.rawValue) · \(seq.triggerPolicy.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if seq.id == selectedSequenceID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        Button(role: .destructive) {
                            onDeleteSequence(seq.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    }
                    .contextMenu {
                        Button("Duplicate") { onDuplicateSequence(seq.id) }
                        Button("Delete", role: .destructive) { onDeleteSequence(seq.id) }
                    }
                }
            }
            Section("Validation") {
                if validationIssues.isEmpty {
                    Text("No issues")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(validationIssues.prefix(20)) { issue in
                        Button {
                            onSelectValidationIssue(issue)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.code)
                                    .font(.caption.bold())
                                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                                Text(issue.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var inspector: some View {
        Group {
            if let id = selectedMappingID,
               let mapping = project.ame.mappings.first(where: { $0.id == id }) {
                mappingEditor(mapping)
            } else if let id = selectedTriggerID,
                      let trigger = project.ame.triggers.first(where: { $0.id == id }) {
                triggerEditor(trigger)
            } else if let id = selectedSequenceID,
                      let sequence = project.ame.sequences.first(where: { $0.id == id }) {
                sequenceEditor(sequence)
            } else {
                ContentUnavailableView(
                    "Select a mapping, trigger, or sequence",
                    systemImage: "pianokeys",
                    description: Text("Browse and edit AME configuration in the sidebar. All edits are undoable.")
                )
            }
        }
        .frame(minHeight: 200)
    }

    // MARK: - Project timing

    @ViewBuilder
    private var timingSettingsRows: some View {
        let settings = project.ame.musicalSettings
        Picker("Policy", selection: Binding(
            get: { settings.timingPolicy },
            set: { policy in
                var s = settings
                s.timingPolicy = policy
                onUpdateMusicalSettings(s)
            }
        )) {
            ForEach(AMETimingPolicyStorage.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        Picker("External source", selection: Binding(
            get: { settings.selectedExternalSourceBindingID },
            set: { id in
                var s = settings
                s.selectedExternalSourceBindingID = id
                onUpdateMusicalSettings(s)
            }
        )) {
            Text("— none —").tag(Optional<UUID>.none)
            ForEach(project.ame.sourceBindings) { b in
                Text(b.displayName).tag(Optional(b.id))
            }
        }
        HStack {
            Text("Default BPM")
            TextField(
                "",
                value: Binding(
                    get: { settings.defaultTempoBPM },
                    set: { bpm in
                        var s = settings
                        s.defaultTempoBPM = bpm
                        onUpdateMusicalSettings(s)
                    }
                ),
                format: .number
            )
            .frame(width: 70)
        }
        Picker("Default meter", selection: Binding(
            get: { settings.defaultMeter },
            set: { m in
                var s = settings
                s.defaultMeter = m
                onUpdateMusicalSettings(s)
            }
        )) {
            Text("4/4").tag(ShowMusicalMeter.fourFour)
            Text("3/4").tag(ShowMusicalMeter.threeFour)
            Text("6/8").tag(ShowMusicalMeter.sixEight)
            Text("7/8 (2+2+3)").tag(ShowMusicalMeter.sevenEight_223)
            Text("7/8 (3+2+2)").tag(ShowMusicalMeter.sevenEight_322)
        }
        HStack {
            Text("Freewheel s")
            TextField(
                "",
                value: Binding(
                    get: { settings.freewheelSeconds },
                    set: { v in
                        var s = settings
                        s.freewheelSeconds = v
                        onUpdateMusicalSettings(s)
                    }
                ),
                format: .number
            )
            .frame(width: 60)
        }
    }

    // MARK: - Mapping editor

    private func mappingEditor(_ mapping: AMEMapping) -> some View {
        ScrollView {
            Form {
                Section("Mapping") {
                    draftNameField(
                        title: "Name",
                        value: mapping.name,
                        onCommit: { name in
                            var m = mapping
                            m.name = name
                            onUpdateMapping(m)
                        }
                    )
                    Toggle("Enabled", isOn: binding(for: mapping, \.enabled))
                    Picker("Behavior", selection: binding(for: mapping, \.behavior)) {
                        ForEach(AMETriggerBehavior.allCases, id: \.self) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    Stepper("Priority \(mapping.priority)", value: binding(for: mapping, \.priority), in: -100...100)
                }
                Section("WHEN (trigger)") {
                    Picker("Trigger", selection: optionalUUIDBinding(for: mapping, \.triggerID)) {
                        Text("— none —").tag(Optional<UUID>.none)
                        ForEach(project.ame.triggers) { t in
                            Text(t.name.isEmpty ? t.friendlyName : t.name).tag(Optional(t.id))
                        }
                    }
                    Picker("Trigger group", selection: optionalUUIDBinding(for: mapping, \.triggerGroupID)) {
                        Text("— none —").tag(Optional<UUID>.none)
                        ForEach(project.ame.triggerGroups) { g in
                            Text(g.name).tag(Optional(g.id))
                        }
                    }
                    Picker("Timing requirement", selection: binding(for: mapping, \.timingRequirement)) {
                        ForEach(AMETimingRequirement.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }
                Section("CONDITIONS (scope / quantize)") {
                    scopeEditor(mapping)
                    Picker("Quantize", selection: quantizeBinding(mapping)) {
                        Text("immediate").tag(Optional<AMEQuantizationBoundary>.none)
                        ForEach(AMEQuantizationBoundary.allCases, id: \.self) { b in
                            Text(b.rawValue).tag(Optional(b))
                        }
                    }
                    Picker("Failure policy", selection: binding(for: mapping, \.quantizationFailurePolicy)) {
                        ForEach(AMEQuantizationFailurePolicy.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    HStack {
                        Text("Debounce ms")
                        TextField("", value: binding(for: mapping, \.debounceMilliseconds), format: .number)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Burst suppress ms")
                        TextField(
                            "off",
                            text: Binding(
                                get: { mapping.burstSuppressionMilliseconds.map { String($0) } ?? "" },
                                set: { text in
                                    var m = mapping
                                    let t = text.trimmingCharacters(in: .whitespaces)
                                    m.burstSuppressionMilliseconds = t.isEmpty ? nil : Double(t)
                                    onUpdateMapping(m)
                                }
                            )
                        )
                        .frame(width: 80)
                    }
                }
                Section("Value transform") {
                    Toggle("Enabled", isOn: Binding(
                        get: { mapping.transform != nil },
                        set: { on in
                            var m = mapping
                            m.transform = on ? (m.transform ?? AMEValueTransform()) : nil
                            onUpdateMapping(m)
                        }
                    ))
                    if var t = mapping.transform {
                        HStack {
                            Text("inMin/inMax")
                            TextField("", value: Binding(get: { t.inMin }, set: { v in t.inMin = v; var m = mapping; m.transform = t; onUpdateMapping(m) }), format: .number)
                                .frame(width: 50)
                            TextField("", value: Binding(get: { t.inMax }, set: { v in t.inMax = v; var m = mapping; m.transform = t; onUpdateMapping(m) }), format: .number)
                                .frame(width: 50)
                        }
                        HStack {
                            Text("outMin/outMax")
                            TextField("", value: Binding(get: { t.outMin }, set: { v in t.outMin = v; var m = mapping; m.transform = t; onUpdateMapping(m) }), format: .number)
                                .frame(width: 50)
                            TextField("", value: Binding(get: { t.outMax }, set: { v in t.outMax = v; var m = mapping; m.transform = t; onUpdateMapping(m) }), format: .number)
                                .frame(width: 50)
                        }
                        Toggle("Invert", isOn: Binding(get: { t.invert }, set: { v in t.invert = v; var m = mapping; m.transform = t; onUpdateMapping(m) }))
                        HStack {
                            Text("Dead zone")
                            TextField("", value: Binding(get: { t.deadZone }, set: { v in t.deadZone = v; var m = mapping; m.transform = t; onUpdateMapping(m) }), format: .number)
                                .frame(width: 60)
                        }
                        HStack {
                            Text("Threshold")
                            TextField(
                                "none",
                                text: Binding(
                                    get: { t.threshold.map { String($0) } ?? "" },
                                    set: { text in
                                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                                        t.threshold = trimmed.isEmpty ? nil : Double(trimmed)
                                        var m = mapping
                                        m.transform = t
                                        onUpdateMapping(m)
                                    }
                                )
                            )
                            .frame(width: 60)
                        }
                    }
                }
                Section("DO (actions)") {
                    actionListEditor(
                        title: "Activation actions",
                        actions: mapping.actions,
                        onChange: { actions in
                            var m = mapping
                            m.actions = actions
                            onUpdateMapping(m)
                        }
                    )
                    actionListEditor(
                        title: "Release actions",
                        actions: mapping.releaseActions,
                        onChange: { actions in
                            var m = mapping
                            m.releaseActions = actions
                            onUpdateMapping(m)
                        }
                    )
                    Picker("Sequence", selection: optionalUUIDBinding(for: mapping, \.sequenceID)) {
                        Text("— none —").tag(Optional<UUID>.none)
                        ForEach(project.ame.sequences) { s in
                            Text(s.name.isEmpty ? "Sequence" : s.name).tag(Optional(s.id))
                        }
                    }
                }
                DisclosureGroup("Advanced / inheritance") {
                    Picker("Override parent", selection: optionalUUIDBinding(for: mapping, \.overrideParentID)) {
                        Text("— none —").tag(Optional<UUID>.none)
                        ForEach(project.ame.mappings.filter { $0.id != mapping.id }) { m in
                            Text(m.name.isEmpty ? m.id.uuidString.prefix(8).description : m.name).tag(Optional(m.id))
                        }
                    }
                    Picker("Disables parent", selection: optionalUUIDBinding(for: mapping, \.disablesParentID)) {
                        Text("— none —").tag(Optional<UUID>.none)
                        ForEach(project.ame.mappings.filter { $0.id != mapping.id }) { m in
                            Text(m.name.isEmpty ? m.id.uuidString.prefix(8).description : m.name).tag(Optional(m.id))
                        }
                    }
                    Picker("Claims legacy map", selection: optionalUUIDBinding(for: mapping, \.claimsLegacyMappingID)) {
                        Text("— none —").tag(Optional<UUID>.none)
                        ForEach(project.midiMappings) { m in
                            Text(m.name.isEmpty ? m.id.uuidString.prefix(8).description : m.name).tag(Optional(m.id))
                        }
                    }
                }
                Section {
                    Button("Duplicate Mapping") { onDuplicateMapping(mapping.id) }
                    Button("Delete Mapping", role: .destructive) { onDeleteMapping(mapping.id) }
                }
            }
            .formStyle(.grouped)
            .padding(8)
        }
    }

    /// Commit free-form text on submit / focus loss (P1-4), not per keystroke.
    private func draftNameField(title: String, value: String, onCommit: @escaping (String) -> Void) -> some View {
        DraftTextField(title: title, value: value, onCommit: onCommit)
    }

    private func scopeEditor(_ mapping: AMEMapping) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scope").font(.caption).foregroundStyle(.secondary)
            Picker("Scope kind", selection: scopeKindBinding(mapping)) {
                Text("Project").tag(ScopeKind.project)
                Text("Song").tag(ScopeKind.song)
                Text("Section").tag(ScopeKind.section)
            }
            .labelsHidden()
            switch mapping.scope {
            case .project:
                EmptyView()
            case .song(let id):
                Picker("Song", selection: songScopeBinding(mapping, current: id)) {
                    ForEach(project.songs) { song in
                        Text(song.title).tag(song.id)
                    }
                }
            case .section(let id):
                Picker("Section", selection: sectionScopeBinding(mapping, current: id)) {
                    ForEach(allSections, id: \.section.id) { item in
                        Text("\(item.song.title) · \(item.section.name)").tag(item.section.id)
                    }
                }
            }
        }
    }

    private var allSections: [(song: Song, section: SongSection)] {
        project.songs.flatMap { song in song.sections.map { (song, $0) } }
    }

    private enum ScopeKind: String, Hashable {
        case project, song, section
    }

    private func scopeKindBinding(_ mapping: AMEMapping) -> Binding<ScopeKind> {
        Binding(
            get: {
                switch mapping.scope {
                case .project: return .project
                case .song: return .song
                case .section: return .section
                }
            },
            set: { kind in
                var m = mapping
                switch kind {
                case .project:
                    m.scope = .project
                case .song:
                    m.scope = .song(project.songs.first?.id ?? UUID())
                case .section:
                    m.scope = .section(allSections.first?.section.id ?? UUID())
                }
                onUpdateMapping(m)
            }
        )
    }

    private func songScopeBinding(_ mapping: AMEMapping, current: UUID) -> Binding<UUID> {
        Binding(
            get: { current },
            set: { id in
                var m = mapping
                m.scope = .song(id)
                onUpdateMapping(m)
            }
        )
    }

    private func sectionScopeBinding(_ mapping: AMEMapping, current: UUID) -> Binding<UUID> {
        Binding(
            get: { current },
            set: { id in
                var m = mapping
                m.scope = .section(id)
                onUpdateMapping(m)
            }
        )
    }

    private func quantizeBinding(_ mapping: AMEMapping) -> Binding<AMEQuantizationBoundary?> {
        Binding(
            get: { mapping.quantizeBoundary },
            set: { value in
                var m = mapping
                m.quantizeBoundary = value
                onUpdateMapping(m)
            }
        )
    }

    // MARK: - Trigger editor

    private func triggerEditor(_ trigger: AMETriggerDefinition) -> some View {
        ScrollView {
            Form {
                Section("Trigger") {
                    TextField("Name", text: triggerBinding(trigger, \.name))
                    TextField("Friendly name", text: triggerBinding(trigger, \.friendlyName))
                    Picker("Message", selection: triggerBinding(trigger, \.messageType)) {
                        ForEach(AMEMIDIMessageType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    HStack {
                        Text("Channel (0-based, empty = any)")
                        TextField(
                            "any",
                            text: optionalUInt8Text(trigger.channel) { ch in
                                var t = trigger
                                t.channel = ch
                                onUpdateTrigger(t)
                            }
                        )
                        .frame(width: 60)
                    }
                    HStack {
                        Text("Data1 min/max")
                        TextField("min", text: optionalUInt8Text(trigger.data1Min) { v in
                            var t = trigger; t.data1Min = v; onUpdateTrigger(t)
                        }).frame(width: 50)
                        TextField("max", text: optionalUInt8Text(trigger.data1Max) { v in
                            var t = trigger; t.data1Max = v; onUpdateTrigger(t)
                        }).frame(width: 50)
                    }
                    Picker("Source binding", selection: optionalUUIDBindingTrigger(trigger, \.sourceBindingID)) {
                        Text("— any source —").tag(Optional<UUID>.none)
                        ForEach(project.ame.sourceBindings) { b in
                            Text(b.displayName).tag(Optional(b.id))
                        }
                    }
                }
                Section {
                    Button("Duplicate Trigger") { onDuplicateTrigger(trigger.id) }
                    Button("Delete Trigger", role: .destructive) { onDeleteTrigger(trigger.id) }
                }
            }
            .formStyle(.grouped)
            .padding(8)
        }
    }

    // MARK: - Sequence editor

    private func sequenceEditor(_ sequence: AMETriggeredSequence) -> some View {
        ScrollView {
            Form {
                Section("Sequence") {
                    DraftTextField(title: "Name", value: sequence.name) { name in
                        var s = sequence
                        s.name = name
                        onUpdateSequence(s)
                    }
                    Picker("Mode", selection: sequenceBinding(sequence, \.mode)) {
                        ForEach(AMESequenceMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    Toggle("Loop", isOn: sequenceBinding(sequence, \.loop))
                    Stepper("Initial index \(sequence.initialIndex)", value: sequenceBinding(sequence, \.initialIndex), in: 0...max(0, sequence.steps.count))
                    Picker("Reset policy", selection: sequenceBinding(sequence, \.resetPolicy)) {
                        ForEach(AMESequenceResetPolicy.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    Picker("Trigger policy", selection: sequenceBinding(sequence, \.triggerPolicy)) {
                        ForEach(AMESequenceTriggerPolicy.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    Picker("State scope", selection: sequenceBinding(sequence, \.stateScope)) {
                        ForEach(AMESequenceStateScope.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }
                Section("Steps") {
                    ForEach(Array(sequence.steps.enumerated()), id: \.element.id) { index, step in
                        VStack(alignment: .leading, spacing: 4) {
                            DraftTextField(title: "Step name", value: step.name) { name in
                                var s = sequence
                                s.steps[index].name = name
                                onUpdateSequence(s)
                            }
                            HStack {
                                Text("Weight")
                                TextField(
                                    "",
                                    value: Binding(
                                        get: { sequence.steps[index].weight },
                                        set: { w in
                                            var s = sequence
                                            s.steps[index].weight = w
                                            onUpdateSequence(s)
                                        }
                                    ),
                                    format: .number
                                )
                                .frame(width: 60)
                            }
                            actionListEditor(
                                title: "Step actions",
                                actions: step.actions,
                                onChange: { actions in
                                    var s = sequence
                                    s.steps[index].actions = actions
                                    onUpdateSequence(s)
                                }
                            )
                            Button("Delete step", role: .destructive) {
                                var s = sequence
                                s.steps.remove(at: index)
                                onUpdateSequence(s)
                            }
                            .buttonStyle(AuroraButtonStyle(kind: .quiet))
                        }
                        .padding(.vertical, 4)
                    }
                    Button("Add Step") {
                        var s = sequence
                        s.steps.append(AMESequenceStep(name: "Step \(s.steps.count + 1)", actions: [.go]))
                        onUpdateSequence(s)
                    }
                }
                Section {
                    Button("Duplicate Sequence") { onDuplicateSequence(sequence.id) }
                    Button("Delete Sequence", role: .destructive) { onDeleteSequence(sequence.id) }
                }
            }
            .formStyle(.grouped)
            .padding(8)
        }
    }

    // MARK: - Action list editor

    private func actionListEditor(
        title: String,
        actions: [AuroraAction],
        onChange: @escaping ([AuroraAction]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                HStack {
                    Text(action.storageKey)
                        .font(.caption.monospaced())
                    Spacer()
                    Button(role: .destructive) {
                        var next = actions
                        next.remove(at: index)
                        onChange(next)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(AuroraButtonStyle(kind: .quiet))
                }
            }
            Menu("Add action") {
                Button("GO") { onChange(actions + [.go]) }
                Button("Stop") { onChange(actions + [.stop]) }
                Button("Back") { onChange(actions + [.back]) }
                Button("Blackout") { onChange(actions + [.blackout]) }
                Button("Blackout Off") { onChange(actions + [.blackoutOff]) }
                Button("Toggle Blackout") { onChange(actions + [.toggleBlackout]) }
                Button("Blind") { onChange(actions + [.blind]) }
                Button("Blind Off") { onChange(actions + [.blindOff]) }
                Button("Freeze") { onChange(actions + [.freeze]) }
                Button("Freeze Off") { onChange(actions + [.freezeOff]) }
                Button("Panic") { onChange(actions + [.panic]) }
                Button("Master Intensity") { onChange(actions + [.masterIntensity]) }
                Button("Tap Tempo") { onChange(actions + [.tapTempo]) }
                Button("Transport Start") { onChange(actions + [.setTransportStart]) }
                Button("Transport Stop") { onChange(actions + [.setTransportStop]) }
                Button("Set Tempo 120") { onChange(actions + [.setTempoBPM(120)]) }
                Button("Next Section") { onChange(actions + [.nextSection]) }
                Button("Previous Section") { onChange(actions + [.previousSection]) }
                if let firstCue = project.cueLists.first?.cues.first {
                    Button("Fire Cue \(firstCue.name.isEmpty ? "first" : firstCue.name)") {
                        onChange(actions + [.fireCue(firstCue.id)])
                    }
                }
                if let firstSong = project.songs.first {
                    Button("Select Song \(firstSong.title)") {
                        onChange(actions + [.selectSong(firstSong.id)])
                    }
                    if let sec = firstSong.sections.sorted(by: { $0.order < $1.order }).first {
                        Button("Enter Section \(sec.name)") {
                            onChange(actions + [.enterSection(sec.id)])
                        }
                    }
                }
                if let seq = project.ame.sequences.first {
                    Button("Advance Sequence \(seq.name)") {
                        onChange(actions + [.advanceSequence(seq.id)])
                    }
                    Button("Fire Sequence Step 0") {
                        onChange(actions + [.fireSequenceStep(sequenceID: seq.id, stepIndex: 0)])
                    }
                    Button("Reset Sequence") {
                        onChange(actions + [.resetSequence(seq.id)])
                    }
                }
                Button("Programmer Intensity") {
                    onChange(actions + [.programmerAttribute("intensity")])
                }
            }
        }
    }

    // MARK: - Bindings

    private func binding<T>(for mapping: AMEMapping, _ keyPath: WritableKeyPath<AMEMapping, T>) -> Binding<T> {
        Binding(
            get: { mapping[keyPath: keyPath] },
            set: { value in
                var m = mapping
                m[keyPath: keyPath] = value
                onUpdateMapping(m)
            }
        )
    }

    private func optionalUUIDBinding(
        for mapping: AMEMapping,
        _ keyPath: WritableKeyPath<AMEMapping, UUID?>
    ) -> Binding<UUID?> {
        binding(for: mapping, keyPath)
    }

    private func triggerBinding<T>(
        _ trigger: AMETriggerDefinition,
        _ keyPath: WritableKeyPath<AMETriggerDefinition, T>
    ) -> Binding<T> {
        Binding(
            get: { trigger[keyPath: keyPath] },
            set: { value in
                var t = trigger
                t[keyPath: keyPath] = value
                onUpdateTrigger(t)
            }
        )
    }

    private func optionalUUIDBindingTrigger(
        _ trigger: AMETriggerDefinition,
        _ keyPath: WritableKeyPath<AMETriggerDefinition, UUID?>
    ) -> Binding<UUID?> {
        triggerBinding(trigger, keyPath)
    }

    private func sequenceBinding<T>(
        _ sequence: AMETriggeredSequence,
        _ keyPath: WritableKeyPath<AMETriggeredSequence, T>
    ) -> Binding<T> {
        Binding(
            get: { sequence[keyPath: keyPath] },
            set: { value in
                var s = sequence
                s[keyPath: keyPath] = value
                onUpdateSequence(s)
            }
        )
    }

    private func stepNameBinding(_ sequence: AMETriggeredSequence, index: Int) -> Binding<String> {
        Binding(
            get: { sequence.steps[index].name },
            set: { value in
                var s = sequence
                s.steps[index].name = value
                onUpdateSequence(s)
            }
        )
    }

    private func optionalUInt8Text(_ value: UInt8?, onCommit: @escaping (UInt8?) -> Void) -> Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    onCommit(nil)
                } else if let v = UInt8(trimmed) {
                    onCommit(v)
                }
            }
        )
    }

    // MARK: - Monitor

    private var monitor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Live Monitor")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(monitorEvents.count) events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            List(monitorEvents.suffix(80).reversed()) { event in
                HStack(alignment: .top, spacing: 8) {
                    Text(event.kind.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(color(for: event.kind))
                        .frame(width: 160, alignment: .leading)
                    Text(event.message)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .listStyle(.plain)
        }
        .frame(minHeight: 180)
    }

    private func color(for kind: AMEDiagnosticKind) -> Color {
        switch kind {
        case .armedEmission, .behaviorFired, .sequenceStepFired:
            return .green
        case .unsupportedAction, .timingRequirementFailed, .sequenceMissing, .sequenceInvalidStep:
            return .red
        case .dryRunEmission, .debounceSuppressed, .burstSuppressed, .quantizeDeferred,
             .heldReleasedBySourceDisconnect:
            return .orange
        default:
            return .secondary
        }
    }
}

/// Local draft text field that commits on submit / focus loss (not per keystroke).
private struct DraftTextField: View {
    let title: String
    let value: String
    let onCommit: (String) -> Void
    @State private var draft: String = ""
    @State private var seeded = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft)
            .focused($focused)
            .onAppear {
                if !seeded {
                    draft = value
                    seeded = true
                }
            }
            .onChange(of: value) { _, new in
                if !focused { draft = new }
            }
            .onSubmit {
                if draft != value { onCommit(draft) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused, draft != value {
                    onCommit(draft)
                }
            }
    }
}
