import Foundation

/// Persisted workspace chrome (panel visibility + split fractions).
/// UI-11: schema version + named Build presets. Perform uses fixed shell (A9).
/// Schema 3: DESIGN Stage Preview / Programmer vertical split (C2).
public struct WorkspaceLayout: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var visiblePanels: Set<WorkspacePanelID>
    /// Leading column width fraction of the main horizontal split (0…1).
    public var leadingFraction: Double
    /// Trailing (inspector) width fraction of the main horizontal split (0…1).
    public var trailingFraction: Double
    /// Bottom strip height fraction of the vertical split (0…1) — preferred expanded size.
    public var bottomFraction: Double
    /// Within DESIGN center column: share of height for Stage Preview (rest is Programmer).
    public var designPreviewFraction: Double
    /// User hid Stage Preview for Programmer-focused work.
    public var stagePreviewCollapsed: Bool
    /// C3.1: lower creative shelf collapsed (does not zero `bottomFraction`).
    public var lowerShelfCollapsed: Bool
    public var leadingTab: WorkspacePanelID
    public var centerTab: WorkspacePanelID
    public var bottomTab: WorkspacePanelID
    public var namedPreset: String?

    public init(
        schemaVersion: Int = WorkspaceLayout.currentSchemaVersion,
        visiblePanels: Set<WorkspacePanelID> = WorkspaceLayout.defaultVisible,
        leadingFraction: Double = 0.20,
        trailingFraction: Double = 0.20,
        bottomFraction: Double = 0.26,
        designPreviewFraction: Double = 0.52,
        stagePreviewCollapsed: Bool = false,
        lowerShelfCollapsed: Bool = false,
        leadingTab: WorkspacePanelID = .fixtureBrowser,
        centerTab: WorkspacePanelID = .patch,
        bottomTab: WorkspacePanelID = .universeMonitor,
        namedPreset: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.visiblePanels = visiblePanels
        self.leadingFraction = leadingFraction
        self.trailingFraction = trailingFraction
        self.bottomFraction = bottomFraction
        self.designPreviewFraction = designPreviewFraction
        self.stagePreviewCollapsed = stagePreviewCollapsed
        self.lowerShelfCollapsed = lowerShelfCollapsed
        self.leadingTab = leadingTab
        self.centerTab = centerTab
        self.bottomTab = bottomTab
        self.namedPreset = namedPreset
    }

    public static let `default` = WorkspaceLayout()

    /// Clamp fractions to usable geometry (UI-11 A11).
    public mutating func clampToSafeGeometry() {
        leadingFraction = min(0.45, max(0.12, leadingFraction))
        trailingFraction = min(0.45, max(0.12, trailingFraction))
        bottomFraction = min(0.5, max(0.15, bottomFraction))
        designPreviewFraction = min(0.78, max(0.22, designPreviewFraction))
        if leadingFraction + trailingFraction > 0.85 {
            let scale = 0.85 / (leadingFraction + trailingFraction)
            leadingFraction *= scale
            trailingFraction *= scale
        }
    }

    /// Named Build presets aligned to Option A tools (UI11-04).
    /// Center is always Programmer in the shell; `centerTab` is retained for schema compat only.
    public static func namedBuildPreset(_ name: String) -> WorkspaceLayout {
        switch name {
        case "Patch":
            var l = WorkspaceLayout(
                leadingFraction: 0.28,
                trailingFraction: 0.18,
                bottomFraction: 0.22,
                leadingTab: .patch,
                centerTab: .programmer,
                bottomTab: .cueList,
                namedPreset: "Patch"
            )
            l.clampToSafeGeometry()
            return l
        case "Song":
            var l = WorkspaceLayout(
                leadingFraction: 0.18,
                trailingFraction: 0.2,
                bottomFraction: 0.36,
                leadingTab: .fixtureBrowser,
                centerTab: .programmer,
                bottomTab: .song,
                namedPreset: "Song"
            )
            l.clampToSafeGeometry()
            return l
        case "Diagnostics":
            var l = WorkspaceLayout(
                leadingFraction: 0.2,
                trailingFraction: 0.22,
                bottomFraction: 0.38,
                leadingTab: .fixtureBrowser,
                centerTab: .programmer,
                bottomTab: .console, // maps to BuildLowerTool.diagnostics
                namedPreset: "Diagnostics"
            )
            l.visiblePanels.insert(.console)
            l.visiblePanels.insert(.inspector)
            l.clampToSafeGeometry()
            return l
        default: // Programming
            var l = WorkspaceLayout(
                leadingTab: .fixtureBrowser,
                centerTab: .programmer,
                bottomTab: .cueList,
                namedPreset: "Programming"
            )
            l.clampToSafeGeometry()
            return l
        }
    }

    public static let defaultVisible: Set<WorkspacePanelID> = [
        .fixtureBrowser, .patch, .cueList, .programmer, .livePlayback,
        .groups, .palettes, .midi, .song, .effects,
        .universeMonitor, .inspector, .console,
    ]

    public mutating func toggle(_ panel: WorkspacePanelID) {
        if visiblePanels.contains(panel) {
            visiblePanels.remove(panel)
        } else {
            visiblePanels.insert(panel)
        }
    }

    public func isVisible(_ panel: WorkspacePanelID) -> Bool {
        visiblePanels.contains(panel)
    }
}

// Set is Codable via array bridge for stable JSON.
extension WorkspaceLayout {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, visiblePanels, leadingFraction, trailingFraction, bottomFraction
        case designPreviewFraction, stagePreviewCollapsed, lowerShelfCollapsed
        case leadingTab, centerTab, bottomTab, namedPreset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let panels = try c.decode([WorkspacePanelID].self, forKey: .visiblePanels)
        visiblePanels = Set(panels)
        leadingFraction = try c.decode(Double.self, forKey: .leadingFraction)
        trailingFraction = try c.decode(Double.self, forKey: .trailingFraction)
        bottomFraction = try c.decode(Double.self, forKey: .bottomFraction)
        designPreviewFraction = try c.decodeIfPresent(Double.self, forKey: .designPreviewFraction) ?? 0.52
        stagePreviewCollapsed = try c.decodeIfPresent(Bool.self, forKey: .stagePreviewCollapsed) ?? false
        lowerShelfCollapsed = try c.decodeIfPresent(Bool.self, forKey: .lowerShelfCollapsed) ?? false
        leadingTab = try c.decode(WorkspacePanelID.self, forKey: .leadingTab)
        centerTab = try c.decode(WorkspacePanelID.self, forKey: .centerTab)
        bottomTab = try c.decode(WorkspacePanelID.self, forKey: .bottomTab)
        namedPreset = try c.decodeIfPresent(String.self, forKey: .namedPreset)
        if schemaVersion < 4 {
            schemaVersion = 4
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(Array(visiblePanels).sorted { $0.rawValue < $1.rawValue }, forKey: .visiblePanels)
        try c.encode(leadingFraction, forKey: .leadingFraction)
        try c.encode(trailingFraction, forKey: .trailingFraction)
        try c.encode(bottomFraction, forKey: .bottomFraction)
        try c.encode(designPreviewFraction, forKey: .designPreviewFraction)
        try c.encode(stagePreviewCollapsed, forKey: .stagePreviewCollapsed)
        try c.encode(lowerShelfCollapsed, forKey: .lowerShelfCollapsed)
        try c.encode(leadingTab, forKey: .leadingTab)
        try c.encode(centerTab, forKey: .centerTab)
        try c.encode(bottomTab, forKey: .bottomTab)
        try c.encodeIfPresent(namedPreset, forKey: .namedPreset)
    }
}
