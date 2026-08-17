import Foundation

/// First-class song section for AME context (not a cue-list entry label).
///
/// Section transition order (serialized control plane):
/// 1. old section onExit actions (immediate by default)
/// 2. update active section context
/// 3. resolve mapping inheritance
/// 4. apply sequence reset/arm per each sequence's `resetPolicy`
/// 5. new section onEnter actions
/// 6. publish snapshot
///
/// `associatedSequenceIDs` only associates sequences with the section; it does **not**
/// independently force reset — `AMETriggeredSequence.resetPolicy` is the source of truth.
public struct SongSection: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var order: Int
    public var mappingSetIDs: [UUID]
    public var localMappingIDs: [UUID]
    public var onEnterActions: [AuroraAction]
    public var onExitActions: [AuroraAction]
    /// Sequences associated with this section (arm/membership). Reset uses sequence.resetPolicy.
    public var associatedSequenceIDs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        order: Int = 0,
        mappingSetIDs: [UUID] = [],
        localMappingIDs: [UUID] = [],
        onEnterActions: [AuroraAction] = [],
        onExitActions: [AuroraAction] = [],
        associatedSequenceIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.mappingSetIDs = mappingSetIDs
        self.localMappingIDs = localMappingIDs
        self.onEnterActions = onEnterActions
        self.onExitActions = onExitActions
        self.associatedSequenceIDs = associatedSequenceIDs
    }

    public static func main(id: UUID = UUID()) -> SongSection {
        SongSection(id: id, name: "Main", order: 0)
    }
}

public enum SongSectionMigrationHelper {
    public static func proposeSections(from entries: [SongEntry]) -> [SongSection] {
        var seen = Set<String>()
        var result: [SongSection] = []
        var order = 0
        for entry in entries {
            let name = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(SongSection(name: name, order: order))
            order += 1
        }
        return result
    }

    public static func ensureDefaultMainSection(_ song: inout Song) {
        if song.sections.isEmpty {
            song.sections = [.main()]
        }
    }
}
