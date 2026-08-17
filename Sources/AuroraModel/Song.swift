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
///
/// `entries` remain the cue set-list. `sections` are first-class AME/performance structure.
/// Entry labels are **not** silently reinterpreted as sections.
public struct Song: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var notes: String
    public var entries: [SongEntry]
    public var annotations: [Annotation]
    /// First-class sections; default `[Main]` when absent on decode (legacy packages).
    public var sections: [SongSection]
    public var defaultTempoBPM: Double?
    /// Full metrical structure (grouping survives save/load). Prefer over bare numerator/denominator.
    public var defaultMeter: ShowMusicalMeter?

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String = "",
        notes: String = "",
        entries: [SongEntry] = [],
        annotations: [Annotation] = [],
        sections: [SongSection] = [],
        defaultTempoBPM: Double? = nil,
        defaultMeter: ShowMusicalMeter? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.notes = notes
        self.entries = entries
        self.annotations = annotations
        self.sections = sections.isEmpty ? [.main()] : sections
        self.defaultTempoBPM = defaultTempoBPM
        self.defaultMeter = defaultMeter
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, notes, entries, annotations
        case sections, defaultTempoBPM, defaultMeter
        case defaultMeterNumerator, defaultMeterDenominator // legacy only
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        entries = try c.decodeIfPresent([SongEntry].self, forKey: .entries) ?? []
        annotations = try c.decodeIfPresent([Annotation].self, forKey: .annotations) ?? []
        let decodedSections = try c.decodeIfPresent([SongSection].self, forKey: .sections) ?? []
        sections = decodedSections.isEmpty ? [.main()] : decodedSections
        defaultTempoBPM = try c.decodeIfPresent(Double.self, forKey: .defaultTempoBPM)
        if let meter = try c.decodeIfPresent(ShowMusicalMeter.self, forKey: .defaultMeter) {
            defaultMeter = meter
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .defaultMeterNumerator),
                  let d = try c.decodeIfPresent(Int.self, forKey: .defaultMeterDenominator) {
            defaultMeter = ShowMusicalMeter.migrating(numerator: n, denominator: d)
        } else {
            defaultMeter = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(notes, forKey: .notes)
        try c.encode(entries, forKey: .entries)
        try c.encode(annotations, forKey: .annotations)
        try c.encode(sections, forKey: .sections)
        try c.encodeIfPresent(defaultTempoBPM, forKey: .defaultTempoBPM)
        try c.encodeIfPresent(defaultMeter, forKey: .defaultMeter)
    }
}
