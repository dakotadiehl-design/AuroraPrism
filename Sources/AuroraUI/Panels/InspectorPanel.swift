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
    public var onSelectFixtures: ([UUID]) -> Void

    public init(
        context: WorkspacePanelContext,
        focus: InspectorFocusKind = .project,
        playbackCueIndex: Int = -1,
        playbackCueListID: UUID? = nil,
        playbackCueID: UUID? = nil,
        onSelectFixtures: @escaping ([UUID]) -> Void = { _ in }
    ) {
        self.context = context
        self.focus = focus
        self.playbackCueIndex = playbackCueIndex
        self.playbackCueListID = playbackCueListID
        self.playbackCueID = playbackCueID
        self.onSelectFixtures = onSelectFixtures
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
                    labeled("Address", "\(fixture.address)")
                    if let universe = context.project.universe(id: fixture.universeId) {
                        labeled("Universe", "\(universe.number) — \(universe.name)")
                    }
                    labeled(
                        "End",
                        "\(fixture.endAddress(channelCount: context.project.channelCount(for: fixture)))"
                    )
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
            }
            .padding(.bottom, 8)
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
                        .buttonStyle(.bordered)
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
                    Text(cue.name)
                        .font(AuroraTypography.workspaceTitle)
                        .foregroundStyle(AuroraColor.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    AuroraInspectorSection("Cue") {
                        labeled("Number", NSDecimalNumber(decimal: cue.number).stringValue)
                        labeled("List", list.name)
                        labeled("Fade in", String(format: "%.2f s", cue.fadeIn))
                        labeled("Delay", String(format: "%.2f s", cue.delay))
                        labeled("Tracking", cue.tracking.rawValue)
                        if isCurrentPlaybackCue(cueID: cue.id, listID: list.id, index: index) {
                            Text("CURRENT")
                                .font(AuroraTypography.status)
                                .foregroundStyle(AuroraColor.accentBright)
                        }
                    }
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
                    Text(palette.name)
                        .font(AuroraTypography.workspaceTitle)
                        .foregroundStyle(AuroraColor.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    AuroraInspectorSection("Palette") {
                        labeled("Type", palette.type.rawValue)
                        labeled("Attributes", "\(palette.values.count)")
                        ForEach(palette.values.keys.sorted(), id: \.self) { key in
                            labeled(key, String(format: "%.2f", palette.values[key] ?? 0))
                        }
                    }
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
                    Text(preset.name)
                        .font(AuroraTypography.workspaceTitle)
                        .foregroundStyle(AuroraColor.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    AuroraInspectorSection("Preset / Look") {
                        labeled("Fixture levels", "\(preset.levels.fixtures.count)")
                        if !preset.notes.isEmpty {
                            labeled("Notes", preset.notes)
                        }
                    }
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
                    Text(song.title)
                        .font(AuroraTypography.workspaceTitle)
                        .foregroundStyle(AuroraColor.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                    AuroraInspectorSection("Song") {
                        labeled("Artist", song.artist.isEmpty ? "—" : song.artist)
                        labeled("Entries", "\(song.entries.count)")
                        Text("Progression: manual only")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                    AuroraInspectorSection("Sections") {
                        ForEach(song.entries) { entry in
                            Text(entry.label.isEmpty ? "Entry" : entry.label)
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textSecondary)
                        }
                    }
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
