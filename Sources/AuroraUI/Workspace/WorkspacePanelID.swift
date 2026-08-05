import Foundation

/// Stable panel identifiers for layout persistence and the View menu.
public enum WorkspacePanelID: String, Codable, CaseIterable, Sendable, Identifiable {
    case fixtureBrowser
    case patch
    case cueList
    case programmer
    case universeMonitor
    case inspector
    case console
    case song

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fixtureBrowser: return "Fixture Browser"
        case .patch: return "Patch"
        case .cueList: return "Cue List"
        case .programmer: return "Programmer"
        case .universeMonitor: return "Universe Monitor"
        case .inspector: return "Inspector"
        case .console: return "Console"
        case .song: return "Song"
        }
    }

    public var placeholderDetail: String {
        switch self {
        case .fixtureBrowser: return "Library browser lands in PR8."
        case .patch: return "Visual patch map lands in PR8."
        case .cueList: return "Cue list UI lands in PR12."
        case .programmer: return "Programmer UI lands in PR14."
        case .universeMonitor: return "Live levels land with engine/diagnostics."
        case .inspector: return "Selection details (PR8+)."
        case .console: return "Log stream lands in PR24."
        case .song: return "Song mode UI lands in PR21."
        }
    }
}
