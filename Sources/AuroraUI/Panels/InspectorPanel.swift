import AuroraDesignSystem
import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// Contextual Inspector — answers “what is being inspected?” (UI-02B).
/// Host-agnostic content root; focus is supplied by the shell.
public struct InspectorPanel: View {
    public var context: WorkspacePanelContext
    /// Explicit focus from workspace (not a hidden selection-priority heuristic).
    public var focus: InspectorFocusKind
    public var playbackCueIndex: Int
    /// Active playback list — required so CURRENT is not index-only (UI-02 A5).
    public var playbackCueListID: UUID?
    /// Active playback cue id when known.
    public var playbackCueID: UUID?
    /// Optional programmer values for single-fixture inspect (UI-03 D1).
    public var programmerValues: [UUID: [String: Double]]
    public var onSelectFixtures: ([UUID]) -> Void
    public var onProjectChanged: () -> Void
    public var onError: (String) -> Void
    /// Document replacement epoch (New/Open). Prefer `documentGeneration` for mutations.
    public var documentEpoch: Int
    /// Authoritative document mutation revision (CR-11 fix) — bumps on command/undo/redo.
    public var documentGeneration: UInt64

    public init(
        context: WorkspacePanelContext,
        focus: InspectorFocusKind = .project,
        playbackCueIndex: Int = -1,
        playbackCueListID: UUID? = nil,
        playbackCueID: UUID? = nil,
        programmerValues: [UUID: [String: Double]] = [:],
        onSelectFixtures: @escaping ([UUID]) -> Void = { _ in },
        onProjectChanged: @escaping () -> Void = {},
        onError: @escaping (String) -> Void = { _ in },
        documentEpoch: Int = 0,
        documentGeneration: UInt64 = 0
    ) {
        self.context = context
        self.focus = focus
        self.playbackCueIndex = playbackCueIndex
        self.playbackCueListID = playbackCueListID
        self.playbackCueID = playbackCueID
        self.programmerValues = programmerValues
        self.onSelectFixtures = onSelectFixtures
        self.onProjectChanged = onProjectChanged
        self.onError = onError
        self.documentEpoch = documentEpoch
        self.documentGeneration = documentGeneration
    }

    public var body: some View {
        Group {
            switch focus {
            case .project:
                projectContext
            case .fixtures:
                singleOrMissingFixture
            case .multiFixtures:
                multiSelection(context.session.selection.snapshot.fixtureIDs)
            case .group(let id):
                groupInspector(id)
            case .cue(let id):
                cueInspector(id)
            case .palette(let id):
                paletteInspector(id)
            case .preset(let id):
                presetInspector(id)
            case .song(let id):
                songInspector(id)
            }
        }
        .background(AuroraColor.surfacePanel)
        .auroraDensity(.compact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Contexts

    private var projectContext: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(context.project.metadata.name)
                    .font(AuroraTypography.workspaceTitle)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                AuroraInspectorSection("Project") {
                    labeled("Fixtures", "\(context.project.fixtures.count)")
                    labeled("Universes", "\(context.project.universes.count)")
                    labeled("Cue lists", "\(context.project.cueLists.count)")
                    labeled("Songs", "\(context.project.songs.count)")
                }
                AuroraEmptyState(
                    title: "Inspector",
                    detail: "Select a fixture, group, cue, palette, or song to inspect.",
                    systemImage: "sidebar.right"
                )
                .frame(height: 120)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var singleOrMissingFixture: some View {
        let ids = context.session.selection.snapshot.orderedFixtureIDs
        if let id = ids.first,
           let fixture = context.project.fixtures.first(where: { $0.id == id }) {
            singleFixture(fixture)
        } else if ids.count > 1 {
            multiSelection(Set(ids))
        } else {
            AuroraEmptyState(
                title: "Nothing selected",
                detail: "Select fixtures to inspect patch and capabilities.",
                systemImage: "sidebar.right"
            )
        }
    }

    private func multiSelection(_ ids: Set<UUID>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                AuroraInspectorSection("Selection") {
                    Text("\(ids.count) fixtures")
                        .font(AuroraTypography.primaryValue)
                        .foregroundStyle(AuroraColor.textPrimary)
                    Text("Programmer edits apply to the selection.")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
            }
            .padding(8)
        }
    }

    private func singleFixture(_ fixture: PatchedFixture) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(fixture.name)
                    .font(AuroraTypography.workspaceTitle)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                AuroraInspectorSection("Patch") {
                    if fixture.isPatched {
                        labeled("Address", "\(fixture.address)")
                        if let universe = context.project.universe(id: fixture.universeId) {
                            labeled("Universe", "\(universe.number) — \(universe.name)")
                        }
                        labeled(
                            "End",
                            "\(fixture.endAddress(channelCount: context.project.channelCount(for: fixture)))"
                        )
                    } else {
                        labeled("Address", "Unpatched")
                        if let universe = context.project.universe(id: fixture.universeId) {
                            labeled("Preferred U", "\(universe.number) — \(universe.name)")
                        }
                        Text("No DMX assignment — identity preserved for repatch.")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.warning)
                    }
                }

                if let definition = context.project.definition(id: fixture.definitionId) {
                    AuroraInspectorSection("Personality") {
                        labeled("Type", definition.displayName)
                        labeled("Channels", "\(definition.channelCount)")
                    }
                    AuroraInspectorSection("Capabilities") {
                        ForEach(capabilityRows(definition), id: \.title) { row in
                            HStack(spacing: 6) {
                                if let icon = row.icon {
                                    AuroraAssetIcon(icon, size: 11)
                                        .foregroundStyle(AuroraColor.textTertiary)
                                }
                                Text(row.title)
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textSecondary)
                            }
                        }
                    }
                }
                let selectedElements = context.session.selection.snapshot.orderedFixtureTargets.filter {
                    $0.fixtureID == fixture.id && $0.elementID != nil
                }
                if !selectedElements.isEmpty {
                    AuroraInspectorSection("Selection") {
                        labeled("Target", selectedElements.compactMap(\.elementID).joined(separator: ", "))
                    }
                }
                if let attrs = programmerValues[fixture.id], !attrs.isEmpty {
                    AuroraInspectorSection("Programmer") {
                        ForEach(attrs.keys.sorted(), id: \.self) { key in
                            labeled(key, InspectorProgrammerValueFormatter.string(key: key, value: attrs[key] ?? 0))
                        }
                    }
                }

                // C4.1: Stage layout aim (geometry — not DMX channels)
                if let place = context.project.stageLayout.fixtures.first(where: { $0.fixtureID == fixture.id }) {
                    stageAimSection(
                        placement: place,
                        fixtureID: fixture.id,
                        supportsSoftGlow: context.project.definition(id: fixture.definitionId).map { definition in
                            let form = context.project.visualizationDescriptor(for: definition).form
                            return form == .linearBar || form == .strip || form == .multiHeadBar
                        } ?? false
                    )
                }
            }
            .padding(.bottom, 8)
        }
    }

    /// Physical Stage beam visualization controls (independent of Pan/Tilt DMX).
    @ViewBuilder
    private func stageAimSection(placement: StageFixturePlacement, fixtureID: UUID, supportsSoftGlow: Bool) -> some View {
        AuroraInspectorSection("Stage Aim") {
            StageAimControls(
                placement: placement,
                supportsSoftGlow: supportsSoftGlow,
                onCommit: { mutate in
                    var layout = context.project.stageLayout
                    guard let i = layout.fixtures.firstIndex(where: { $0.fixtureID == fixtureID }) else { return }
                    mutate(&layout.fixtures[i])
                    do {
                        try context.session.perform(UpdateStageLayoutCommand(layout: layout))
                        onProjectChanged()
                    } catch {
                        onError(prismReportCommandFailure(error, operation: "edit"))
                    }
                }
            )
        }
    }
    private func groupInspector(_ id: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let group = context.project.groups.first(where: { $0.id == id }) {
                    Text(group.name)
                        .font(AuroraTypography.workspaceTitle)
                        .foregroundStyle(AuroraColor.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    AuroraInspectorSection("Group") {
                        labeled("Members", "\(group.fixtureIds.count)")
                        Button("Select members") {
                            onSelectFixtures(group.fixtureIds)
                        }
                        .buttonStyle(AuroraButtonStyle(kind: .secondary))
                        .controlSize(.small)
                    }
                    AuroraInspectorSection("Fixtures") {
                        ForEach(group.fixtureIds.prefix(12), id: \.self) { fid in
                            Text(context.project.fixtures.first(where: { $0.id == fid })?.name ?? fid.uuidString.prefix(8).description)
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textSecondary)
                        }
                        if group.fixtureIds.count > 12 {
                            Text("+\(group.fixtureIds.count - 12) more")
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textTertiary)
                        }
                    }
                } else {
                    AuroraEmptyState(title: "Group not found", detail: "Selection is out of date.")
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func cueInspector(_ id: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let found = findCue(id) {
                    let (list, cue, index) = found
                    CueInspectorContent(
                        list: list,
                        cue: cue,
                        isCurrent: isCurrentPlaybackCue(cueID: cue.id, listID: list.id, index: index),
                        documentRevision: documentGeneration,
                        onCommit: { updated in
                            do {
                                try context.session.perform(
                                    UpdateCueCommand(listID: list.id, cue: updated)
                                )
                                onProjectChanged()
                            } catch {
                                onError(prismReportCommandFailure(error, operation: "edit"))
                            }
                        }
                    )
                } else {
                    AuroraEmptyState(title: "Cue not found", detail: "Selection is out of date.")
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func paletteInspector(_ id: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let palette = context.project.palettes.first(where: { $0.id == id }) {
                    PaletteInspectorContent(
                        palette: palette,
                        referenceCount: context.project.paletteReferenceCount(palette.id),
                        referenceSummaries: context.project.paletteReferenceCueSummaries(palette.id),
                        documentRevision: documentGeneration,
                        onCommit: { updated in
                            do {
                                try context.session.perform(UpdatePaletteCommand(palette: updated))
                                onProjectChanged()
                            } catch {
                                onError(prismReportCommandFailure(error, operation: "edit"))
                            }
                        }
                    )
                } else {
                    AuroraEmptyState(title: "Palette not found", detail: "")
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func presetInspector(_ id: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let preset = context.project.presets.first(where: { $0.id == id }) {
                    PresetInspectorContent(
                        preset: preset,
                        documentRevision: documentGeneration,
                        onCommit: { updated in
                            do {
                                try context.session.perform(UpdatePresetCommand(preset: updated))
                                onProjectChanged()
                            } catch {
                                onError(prismReportCommandFailure(error, operation: "edit"))
                            }
                        }
                    )
                } else {
                    AuroraEmptyState(title: "Preset not found", detail: "")
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func songInspector(_ id: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let song = context.project.songs.first(where: { $0.id == id }) {
                    SongInspectorContent(
                        song: song,
                        documentRevision: documentGeneration,
                        onCommit: { updated in
                            do {
                                try context.session.perform(UpdateSongCommand(song: updated))
                                onProjectChanged()
                            } catch {
                                onError(prismReportCommandFailure(error, operation: "edit"))
                            }
                        }
                    )
                } else {
                    AuroraEmptyState(title: "Song not found", detail: "")
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Helpers

    /// CURRENT only when inspected cue matches live playback (list + cue, not index alone).
    private func isCurrentPlaybackCue(cueID: UUID, listID: UUID, index: Int) -> Bool {
        if let playbackCueID {
            return cueID == playbackCueID
        }
        guard let playbackCueListID, playbackCueListID == listID, playbackCueIndex >= 0 else {
            return false
        }
        return index == playbackCueIndex
    }

    private func findCue(_ id: UUID) -> (CueList, Cue, Int)? {
        for list in context.project.cueLists {
            if let index = list.cues.firstIndex(where: { $0.id == id }) {
                return (list, list.cues[index], index)
            }
        }
        return nil
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(value)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
        }
    }

    private struct CapabilityRow: Hashable {
        var title: String
        var icon: AuroraLightingIcon?
    }

    private func capabilityRows(_ def: FixtureDefinition) -> [CapabilityRow] {
        var rows: [CapabilityRow] = []
        let attrs = Set(def.channels.map(\.attribute))
        if attrs.contains("pan") || attrs.contains("tilt") || def.hasPanTilt {
            rows.append(CapabilityRow(title: "Pan / Tilt", icon: .panTilt))
        }
        if attrs.contains("colorR") || def.colorModel != nil {
            rows.append(CapabilityRow(title: "Color", icon: .colorWheel))
        }
        if attrs.contains("intensity") {
            rows.append(CapabilityRow(title: "Dimmer", icon: .dimmer))
        }
        if attrs.contains(where: { $0.contains("gobo") }) {
            rows.append(CapabilityRow(title: "Gobos", icon: .gobo))
        }
        if attrs.contains(where: { $0.contains("zoom") || $0.contains("iris") }) {
            rows.append(CapabilityRow(title: "Beam", icon: .beam))
        }
        if rows.isEmpty {
            rows.append(CapabilityRow(title: "Channels: \(def.channelCount)", icon: nil))
        }
        return rows
    }
}

public enum InspectorProgrammerValueFormatter {
    public static func string(key: String, value: Double) -> String {
        let base = key.split(separator: "@").first.map(String.init) ?? key
        if base == ColorAuthoringAttribute.hue {
            return String(format: "%.0f°", value)
        }
        return String(format: "%.0f%%", value * 100)
    }
}

// MARK: - Stage aim editor (coalesced undo on slider end)

/// Local slider state so continuous drag does not flood the Undo stack.
private struct StageAimControls: View {
    let placement: StageFixturePlacement
    let supportsSoftGlow: Bool
    var onCommit: ((inout StageFixturePlacement) -> Void) -> Void

    @State private var directionDeg: Double = 0
    @State private var spreadDeg: Double = 30
    @State private var length: Double = 160
    @State private var beamVisible: Bool = true
    @State private var renderMode: StageBeamRenderMode = .directional

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Physical plot aim — not a DMX channel")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)

            AuroraFader(
                value: normalizedBinding(
                    value: $directionDeg,
                    range: -180...180
                ),
                label: "Direction",
                display: .value(normalized(directionDeg, in: -180...180)),
                axis: .horizontal,
                valueFormatter: { value in
                    "\(Int(denormalized(value, in: -180...180).rounded()))°"
                },
                onEditingChanged: { editing in
                    if !editing {
                        onCommit { $0.aimDirection = directionDeg * .pi / 180 }
                    }
                }
            )

            AuroraFader(
                value: normalizedBinding(
                    value: $spreadDeg,
                    range: 2...120
                ),
                label: "Spread",
                display: .value(normalized(spreadDeg, in: 2...120)),
                axis: .horizontal,
                valueFormatter: { value in
                    "\(Int(denormalized(value, in: 2...120).rounded()))°"
                },
                onEditingChanged: { editing in
                    if !editing {
                        onCommit { $0.beamSpread = max(1, spreadDeg) * .pi / 180 }
                    }
                }
            )

            AuroraFader(
                value: normalizedBinding(
                    value: $length,
                    range: 40...400
                ),
                label: "Length",
                display: .value(normalized(length, in: 40...400)),
                axis: .horizontal,
                valueFormatter: { value in
                    "\(Int(denormalized(value, in: 40...400).rounded()))"
                },
                onEditingChanged: { editing in
                    if !editing {
                        onCommit { $0.beamLength = max(8, length) }
                    }
                }
            )

            Toggle("Show beam", isOn: $beamVisible)
                .font(AuroraTypography.metadata)
                .toggleStyle(.checkbox)
                .onChange(of: beamVisible) { _, v in
                    onCommit { $0.beamVisible = v }
                }

            if supportsSoftGlow {
                Picker("Render", selection: $renderMode) {
                    Text("Directional beam").tag(StageBeamRenderMode.directional)
                    Text("Soft glow").tag(StageBeamRenderMode.softGlow)
                }
                .font(AuroraTypography.metadata)
                .onChange(of: renderMode) { _, value in
                    onCommit { $0.beamRenderMode = value }
                }
            }
        }
        .onAppear { syncFromPlacement() }
        .onChange(of: placement.id) { _, _ in syncFromPlacement() }
        .onChange(of: placement.aimDirection) { _, _ in syncFromPlacement() }
        .onChange(of: placement.beamSpread) { _, _ in syncFromPlacement() }
        .onChange(of: placement.beamLength) { _, _ in syncFromPlacement() }
        .onChange(of: placement.beamVisible) { _, _ in syncFromPlacement() }
        .onChange(of: placement.beamRenderMode) { _, _ in syncFromPlacement() }
    }

    private func syncFromPlacement() {
        var deg = placement.aimDirection * 180 / .pi
        while deg > 180 { deg -= 360 }
        while deg < -180 { deg += 360 }
        directionDeg = deg
        spreadDeg = placement.beamSpread * 180 / .pi
        length = placement.beamLength
        beamVisible = placement.beamVisible
        renderMode = placement.beamRenderMode
    }

    private func normalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private func denormalized(_ value: Double, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + min(1, max(0, value)) * (range.upperBound - range.lowerBound)
    }

    private func normalizedBinding(
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> Binding<Double> {
        Binding(
            get: { normalized(value.wrappedValue, in: range) },
            set: { value.wrappedValue = denormalized($0, in: range) }
        )
    }

}

/// UI-facing inspector focus kind (mirrors app WorkspaceController.InspectorFocus).
public enum InspectorFocusKind: Equatable, Sendable {
    case project
    case fixtures
    case multiFixtures
    case group(UUID)
    case cue(UUID)
    case palette(UUID)
    case preset(UUID)
    case song(UUID)
}

// MARK: - UI-04 palette / preset inspectors (rename via command on commit)

private struct SongInspectorContent: View {
    let song: Song
    let documentRevision: UInt64
    let onCommit: (Song) -> Void

    @State private var titleDraft = ""
    @State private var artistDraft = ""
    @State private var notesDraft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.roundedBorder)
                .font(AuroraTypography.workspaceTitle)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .focused($fieldFocused)
                .onSubmit { commit() }
            AuroraInspectorSection("Song") {
                field("Artist", $artistDraft)
                labeled("Entries", "\(song.entries.count)")
                Text("Progression: manual only")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            AuroraInspectorSection("Notes") {
                TextField("Notes", text: $notesDraft, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
            }
            AuroraInspectorSection("Entries") {
                ForEach(song.entries) { entry in
                    Text(entry.label.isEmpty ? "Entry" : entry.label)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textSecondary)
                }
            }
            Button("Save Song Fields") { commit() }
                .controlSize(.small)
                .padding(.horizontal, 8)
        }
        .onAppear { load() }
        .onChange(of: song.id) { _, _ in load() }
        .onChange(of: documentRevision) { _, _ in
            if !fieldFocused { load() }
        }
    }

    private func load() {
        titleDraft = song.title
        artistDraft = song.artist
        notesDraft = song.notes
    }

    private func commit() {
        var updated = song
        let t = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = t.isEmpty ? song.title : t
        updated.artist = artistDraft
        updated.notes = notesDraft
        guard updated != song else { return }
        onCommit(updated)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(value)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
        }
    }
}

private struct CueInspectorContent: View {
    let list: CueList
    let cue: Cue
    let isCurrent: Bool
    let documentRevision: UInt64
    let onCommit: (Cue) -> Void

    @State private var nameDraft = ""
    @State private var numberDraft = ""
    @State private var fadeInDraft = ""
    @State private var fadeOutDraft = ""
    @State private var delayDraft = ""
    @State private var tracking: TrackingMode = .track
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .font(AuroraTypography.workspaceTitle)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .focused($fieldFocused)
                .onSubmit { commit() }
            AuroraInspectorSection("Cue") {
                labeled("List", list.name)
                fieldRow("Number (display)", $numberDraft)
                fieldRow("Fade in (s)", $fadeInDraft)
                fieldRow("Fade out (s)", $fadeOutDraft)
                fieldRow("Delay (s)", $delayDraft)
                Picker("Tracking", selection: $tracking) {
                    Text("Track").tag(TrackingMode.track)
                    Text("Cue only").tag(TrackingMode.cueOnly)
                }
                .onChange(of: tracking) { _, _ in commit() }
                labeled("Fixture levels", "\(cue.levels.fixtures.count)")
                if isCurrent {
                    Text("CURRENT")
                        .font(AuroraTypography.status)
                        .foregroundStyle(AuroraColor.accentBright)
                }
                Text("Playback order = list position, not number")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            Button("Save Cue Fields") { commit() }
                .controlSize(.small)
                .padding(.horizontal, 8)
        }
        .onAppear { load() }
        .onChange(of: cue.id) { _, _ in load() }
        .onChange(of: documentRevision) { _, _ in
            if !fieldFocused { load() }
        }
    }

    private func load() {
        nameDraft = cue.name
        numberDraft = NSDecimalNumber(decimal: cue.number).stringValue
        fadeInDraft = String(format: "%.2f", cue.fadeIn)
        fadeOutDraft = String(format: "%.2f", cue.fadeOut)
        delayDraft = String(format: "%.2f", cue.delay)
        tracking = cue.tracking
    }

    private func commit() {
        var updated = cue
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed
        if let n = Decimal(string: numberDraft.trimmingCharacters(in: .whitespacesAndNewlines)) {
            updated.number = n
        }
        if let v = Double(fadeInDraft) { updated.fadeIn = max(0, v) }
        if let v = Double(fadeOutDraft) { updated.fadeOut = max(0, v) }
        if let v = Double(delayDraft) { updated.delay = max(0, v) }
        updated.tracking = tracking
        // Levels intentionally untouched here (Record/Update owns levels).
        updated.levels = cue.levels
        guard updated != cue else { return }
        onCommit(updated)
    }

    private func fieldRow(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(value)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
        }
    }
}

private struct PaletteInspectorContent: View {
    let palette: Palette
    let referenceCount: Int
    let referenceSummaries: [String]
    let documentRevision: UInt64
    let onCommit: (Palette) -> Void

    @State private var nameDraft: String = ""
    @State private var notesDraft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .font(AuroraTypography.workspaceTitle)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .focused($fieldFocused)
                .onSubmit { commit() }
            AuroraInspectorSection("Palette") {
                labeled("Type", palette.type.rawValue)
                labeled("Attributes", "\(palette.values.count)")
                ForEach(palette.values.keys.sorted(), id: \.self) { key in
                    labeled(key, String(format: "%.2f", palette.values[key] ?? 0))
                }
            }
            AuroraInspectorSection("References") {
                labeled("Fixture slots", "\(referenceCount)")
                if referenceSummaries.isEmpty {
                    Text("Not referenced by cues or presets")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                } else {
                    ForEach(Array(referenceSummaries.prefix(8)), id: \.self) { line in
                        Text(line)
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textSecondary)
                    }
                    if referenceSummaries.count > 8 {
                        Text("…and \(referenceSummaries.count - 8) more")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                }
            }
            AuroraInspectorSection("Notes") {
                TextField("Notes", text: $notesDraft, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
            }
            Button("Save Name / Notes") { commit() }
                .controlSize(.small)
                .padding(.horizontal, 8)
        }
        .onAppear { load() }
        .onChange(of: palette.id) { _, _ in load() }
        .onChange(of: documentRevision) { _, _ in
            if !fieldFocused { load() }
        }
    }

    private func load() {
        nameDraft = palette.name
        notesDraft = palette.notes
    }

    private func commit() {
        var updated = palette
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? palette.name : trimmed
        updated.notes = notesDraft
        guard updated != palette else { return }
        onCommit(updated)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(value)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
        }
    }
}

private struct PresetInspectorContent: View {
    let preset: Preset
    let documentRevision: UInt64
    let onCommit: (Preset) -> Void

    @State private var nameDraft: String = ""
    @State private var notesDraft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .font(AuroraTypography.workspaceTitle)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .focused($fieldFocused)
                .onSubmit { commit() }
            AuroraInspectorSection("Preset / Look") {
                labeled("Fixture levels", "\(preset.levels.fixtures.count)")
            }
            AuroraInspectorSection("Notes") {
                TextField("Notes", text: $notesDraft, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit() }
            }
            Button("Save Name / Notes") { commit() }
                .controlSize(.small)
                .padding(.horizontal, 8)
        }
        .onAppear { load() }
        .onChange(of: preset.id) { _, _ in load() }
        .onChange(of: documentRevision) { _, _ in
            if !fieldFocused { load() }
        }
    }

    private func load() {
        nameDraft = preset.name
        notesDraft = preset.notes
    }

    private func commit() {
        var updated = preset
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? preset.name : trimmed
        updated.notes = notesDraft
        guard updated != preset else { return }
        onCommit(updated)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(value)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
        }
    }
}
