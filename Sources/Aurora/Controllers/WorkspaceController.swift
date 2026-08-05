import AuroraModel
import AuroraUI
import Foundation

/// What the Inspector is currently presenting (UI-02B).
/// Independent of Programmer fixture selection so cues/groups can be inspected without clearing fixtures.
enum InspectorFocus: Equatable, Sendable {
    case project
    case fixtures
    case multiFixtures
    case group(UUID)
    case cue(UUID)
    case palette(UUID)
    case preset(UUID)
    case song(UUID)
}

/// Left column tools (UI-02E Option A).
enum BuildLeftTool: String, CaseIterable, Identifiable, Sendable {
    case browser = "Browser"
    case patch = "Patch"
    case groups = "Groups"
    var id: String { rawValue }
}

/// Lower region tools (UI-02E Option A).
enum BuildLowerTool: String, CaseIterable, Identifiable, Sendable {
    case palettes = "Palettes"
    case cues = "Cues"
    case song = "Song"
    var id: String { rawValue }
}

/// Build/Perform mode, panel layout, and UI-only workspace state (Stage C / UI-02).
@MainActor
final class WorkspaceController: ObservableObject {
    @Published var layout: WorkspaceLayout
    @Published var mode: WorkspaceMode = .build
    /// Explicit Inspector context — not a hidden priority over selection sets.
    @Published var inspectorFocus: InspectorFocus = .project
    @Published var leftTool: BuildLeftTool = .browser
    @Published var lowerTool: BuildLowerTool = .cues
    /// Bumps when the document is replaced so panel `@State` can self-heal (UI-02 B2/B3).
    @Published private(set) var documentEpoch: Int = 0

    init(layout: WorkspaceLayout = WorkspaceLayoutStore.load()) {
        self.layout = layout
    }

    func togglePanel(_ id: WorkspacePanelID) {
        layout.toggle(id)
        WorkspaceLayoutStore.save(layout)
    }

    func setMode(_ mode: WorkspaceMode) {
        self.mode = mode
    }

    func isVisible(_ id: WorkspacePanelID) -> Bool {
        layout.isVisible(id)
    }

    func setInspectorFocus(_ focus: InspectorFocus) {
        inspectorFocus = focus
    }

    func setLeftTool(_ tool: BuildLeftTool) {
        leftTool = tool
    }

    func setLowerTool(_ tool: BuildLowerTool) {
        lowerTool = tool
    }

    /// Programmatic fixture selection change — may keep sticky non-fixture Inspector focus.
    func noteFixtureSelectionChanged(count: Int) {
        switch inspectorFocus {
        case .cue, .group, .palette, .preset, .song:
            break
        default:
            applyFixtureFocus(count: count)
        }
    }

    /// User explicitly clicked fixtures for inspection.
    func noteExplicitFixtureInspect(count: Int) {
        applyFixtureFocus(count: count)
    }

    /// User explicitly clicked a group row for inspection.
    func noteExplicitGroupInspect(id: UUID) {
        inspectorFocus = .group(id)
    }

    private func applyFixtureFocus(count: Int) {
        if count == 0 {
            inspectorFocus = .project
        } else if count == 1 {
            inspectorFocus = .fixtures
        } else {
            inspectorFocus = .multiFixtures
        }
    }

    /// Reset all document-scoped UI state after New/Open/Demo (UI-02 B2).
    /// Does **not** change Build/Perform mode (presentation-only).
    func didReplaceDocument(project: ShowProject) {
        inspectorFocus = .project
        leftTool = .browser
        lowerTool = .cues
        documentEpoch &+= 1
        _ = project // available for future validation of sticky IDs
    }
}
