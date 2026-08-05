import Foundation

/// Persisted workspace chrome (panel visibility + split fractions).
public struct WorkspaceLayout: Codable, Equatable, Sendable {
    public var visiblePanels: Set<WorkspacePanelID>
    /// Leading column width fraction of the main horizontal split (0…1).
    public var leadingFraction: Double
    /// Trailing (inspector) width fraction of the main horizontal split (0…1).
    public var trailingFraction: Double
    /// Bottom strip height fraction of the vertical split (0…1).
    public var bottomFraction: Double
    public var leadingTab: WorkspacePanelID
    public var centerTab: WorkspacePanelID
    public var bottomTab: WorkspacePanelID

    public init(
        visiblePanels: Set<WorkspacePanelID> = WorkspaceLayout.defaultVisible,
        leadingFraction: Double = 0.22,
        trailingFraction: Double = 0.22,
        bottomFraction: Double = 0.28,
        leadingTab: WorkspacePanelID = .fixtureBrowser,
        centerTab: WorkspacePanelID = .patch,
        bottomTab: WorkspacePanelID = .universeMonitor
    ) {
        self.visiblePanels = visiblePanels
        self.leadingFraction = leadingFraction
        self.trailingFraction = trailingFraction
        self.bottomFraction = bottomFraction
        self.leadingTab = leadingTab
        self.centerTab = centerTab
        self.bottomTab = bottomTab
    }

    public static let `default` = WorkspaceLayout()

    public static let defaultVisible: Set<WorkspacePanelID> = [
        .fixtureBrowser, .patch, .cueList, .programmer,
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
        case visiblePanels, leadingFraction, trailingFraction, bottomFraction
        case leadingTab, centerTab, bottomTab
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let panels = try c.decode([WorkspacePanelID].self, forKey: .visiblePanels)
        visiblePanels = Set(panels)
        leadingFraction = try c.decode(Double.self, forKey: .leadingFraction)
        trailingFraction = try c.decode(Double.self, forKey: .trailingFraction)
        bottomFraction = try c.decode(Double.self, forKey: .bottomFraction)
        leadingTab = try c.decode(WorkspacePanelID.self, forKey: .leadingTab)
        centerTab = try c.decode(WorkspacePanelID.self, forKey: .centerTab)
        bottomTab = try c.decode(WorkspacePanelID.self, forKey: .bottomTab)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Array(visiblePanels).sorted { $0.rawValue < $1.rawValue }, forKey: .visiblePanels)
        try c.encode(leadingFraction, forKey: .leadingFraction)
        try c.encode(trailingFraction, forKey: .trailingFraction)
        try c.encode(bottomFraction, forKey: .bottomFraction)
        try c.encode(leadingTab, forKey: .leadingTab)
        try c.encode(centerTab, forKey: .centerTab)
        try c.encode(bottomTab, forKey: .bottomTab)
    }
}
