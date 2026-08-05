import Foundation

/// Category for settings / Perform binding UI (P1-9).
public enum ShowActionCategory: String, Sendable, CaseIterable {
    case playback
    case song
    case programmer
    case safety
}

/// Descriptor for a bindable show action (populates MIDI/OSC/Settings UI).
public struct ShowActionDescriptor: Equatable, Sendable, Identifiable {
    public var id: String { storageKey }
    public var storageKey: String
    public var displayName: String
    public var category: ShowActionCategory
    /// When true, the action consumes a 0…1 scalar (CC / note velocity).
    public var acceptsScalar: Bool
    public var needsParameter: Bool

    public init(
        storageKey: String,
        displayName: String,
        category: ShowActionCategory,
        acceptsScalar: Bool = false,
        needsParameter: Bool = false
    ) {
        self.storageKey = storageKey
        self.displayName = displayName
        self.category = category
        self.acceptsScalar = acceptsScalar
        self.needsParameter = needsParameter
    }
}

/// Canonical catalog of show-control actions (single source for Settings + remote).
public enum ShowActionCatalog {
    public static let all: [ShowActionDescriptor] = [
        ShowActionDescriptor(storageKey: "go", displayName: "GO", category: .playback),
        ShowActionDescriptor(storageKey: "stop", displayName: "Stop", category: .playback),
        ShowActionDescriptor(storageKey: "back", displayName: "Back", category: .playback),
        ShowActionDescriptor(
            storageKey: "fireCue",
            displayName: "Fire Cue",
            category: .playback,
            needsParameter: true
        ),
        ShowActionDescriptor(
            storageKey: "fireCueIndex",
            displayName: "Fire Cue Index",
            category: .playback,
            needsParameter: true
        ),
        ShowActionDescriptor(
            storageKey: "programmerAttr",
            displayName: "Programmer Attribute",
            category: .programmer,
            acceptsScalar: true,
            needsParameter: true
        ),
    ]

    public static func descriptor(for storageKey: String) -> ShowActionDescriptor? {
        all.first { $0.storageKey == storageKey }
    }
}
