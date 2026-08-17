import Foundation

/// Stable panel identifiers for layout persistence and the View menu.
public enum WorkspacePanelID: String, Codable, CaseIterable, Sendable, Identifiable {
    case fixtureBrowser
    case patch
    case cueList
    case programmer
    case livePlayback
    case groups
    case cueBlocks
    case palettes
    case midi
    case universeMonitor
    case inspector
    case console
    case song
    case effects

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fixtureBrowser: return "Fixture Browser"
        case .patch: return "Patch"
        case .cueList: return "Cue List"
        case .programmer: return "Programmer"
        case .livePlayback: return "Live"
        case .groups: return "Groups"
        case .cueBlocks: return "Cue Blocks"
        case .palettes: return "Palettes"
        case .midi: return "MIDI"
        case .universeMonitor: return "Universe Monitor"
        case .inspector: return "Inspector"
        case .console: return "Console"
        case .song: return "Song"
        case .effects: return "Effects"
        }
    }

    public var placeholderDetail: String {
        switch self {
        case .fixtureBrowser: return "Library browser."
        case .patch: return "Patch map."
        case .cueList: return "Cue list."
        case .programmer: return "Programmer."
        case .livePlayback: return "Live ops."
        case .groups: return "Fixture groups."
        case .cueBlocks: return "Fixture-scoped reusable Cue Blocks."
        case .palettes: return "Palettes & looks."
        case .midi: return "MIDI mappings & learn."
        case .universeMonitor: return "Universe monitor."
        case .inspector: return "Inspector."
        case .console: return "Console."
        case .song: return "Song mode."
        case .effects: return "Live effects."
        }
    }
}
