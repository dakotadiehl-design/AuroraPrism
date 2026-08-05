import Foundation

/// Reference inside a song set list.
public enum SongEntryTarget: Codable, Equatable, Sendable, Hashable {
    case cueList(UUID)
    case cue(listId: UUID, cueId: UUID)

    private enum CodingKeys: String, CodingKey {
        case type, cueListId, cueId
    }

    private enum EntryType: String, Codable {
        case cueList
        case cue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EntryType.self, forKey: .type)
        switch type {
        case .cueList:
            let id = try container.decode(UUID.self, forKey: .cueListId)
            self = .cueList(id)
        case .cue:
            let listId = try container.decode(UUID.self, forKey: .cueListId)
            let cueId = try container.decode(UUID.self, forKey: .cueId)
            self = .cue(listId: listId, cueId: cueId)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cueList(let id):
            try container.encode(EntryType.cueList, forKey: .type)
            try container.encode(id, forKey: .cueListId)
        case .cue(let listId, let cueId):
            try container.encode(EntryType.cue, forKey: .type)
            try container.encode(listId, forKey: .cueListId)
            try container.encode(cueId, forKey: .cueId)
        }
    }
}

public struct SongEntry: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var target: SongEntryTarget
    public var label: String

    public init(id: UUID = UUID(), target: SongEntryTarget, label: String = "") {
        self.id = id
        self.target = target
        self.label = label
    }
}

public struct Annotation: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var text: String
    /// Optional timing offset from song start (seconds).
    public var timeOffset: TimeInterval?

    public init(id: UUID = UUID(), text: String, timeOffset: TimeInterval? = nil) {
        self.id = id
        self.text = text
        self.timeOffset = timeOffset
    }
}

/// Song / set-list container for ordered show progression.
public struct Song: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var notes: String
    public var entries: [SongEntry]
    public var annotations: [Annotation]

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        notes: String = "",
        entries: [SongEntry] = [],
        annotations: [Annotation] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.notes = notes
        self.entries = entries
        self.annotations = annotations
    }
}
