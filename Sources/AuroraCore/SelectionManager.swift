import AuroraModel
import Foundation

/// Immutable multi-select snapshot for one moment in time.
public struct SelectionSnapshot: Equatable, Sendable, Hashable {
    public var fixtureIDs: Set<UUID>
    public var cueIDs: Set<UUID>
    public var cueListIDs: Set<UUID>
    public var songIDs: Set<UUID>
    public var groupIDs: Set<UUID>

    public init(
        fixtureIDs: Set<UUID> = [],
        cueIDs: Set<UUID> = [],
        cueListIDs: Set<UUID> = [],
        songIDs: Set<UUID> = [],
        groupIDs: Set<UUID> = []
    ) {
        self.fixtureIDs = fixtureIDs
        self.cueIDs = cueIDs
        self.cueListIDs = cueListIDs
        self.songIDs = songIDs
        self.groupIDs = groupIDs
    }

    public static let empty = SelectionSnapshot()

    public var isEmpty: Bool {
        fixtureIDs.isEmpty
            && cueIDs.isEmpty
            && cueListIDs.isEmpty
            && songIDs.isEmpty
            && groupIDs.isEmpty
    }
}

/// Single source of truth for selected show entities (multi-select first-class).
@MainActor
public final class SelectionManager {
    public private(set) var snapshot: SelectionSnapshot = .empty

    public init() {}

    public func clear() {
        snapshot = .empty
    }

    public func selectFixtures(_ ids: Set<UUID>, extending: Bool = false) {
        if extending {
            snapshot.fixtureIDs.formUnion(ids)
        } else {
            snapshot.fixtureIDs = ids
        }
    }

    public func deselectFixtures(_ ids: Set<UUID>) {
        snapshot.fixtureIDs.subtract(ids)
    }

    public func toggleFixture(_ id: UUID) {
        if snapshot.fixtureIDs.contains(id) {
            snapshot.fixtureIDs.remove(id)
        } else {
            snapshot.fixtureIDs.insert(id)
        }
    }

    public func selectCues(_ ids: Set<UUID>, extending: Bool = false) {
        if extending {
            snapshot.cueIDs.formUnion(ids)
        } else {
            snapshot.cueIDs = ids
        }
    }

    public func selectCueLists(_ ids: Set<UUID>, extending: Bool = false) {
        if extending {
            snapshot.cueListIDs.formUnion(ids)
        } else {
            snapshot.cueListIDs = ids
        }
    }

    public func selectSongs(_ ids: Set<UUID>, extending: Bool = false) {
        if extending {
            snapshot.songIDs.formUnion(ids)
        } else {
            snapshot.songIDs = ids
        }
    }

    public func selectGroups(_ ids: Set<UUID>, extending: Bool = false) {
        if extending {
            snapshot.groupIDs.formUnion(ids)
        } else {
            snapshot.groupIDs = ids
        }
    }

    /// Drops IDs that no longer exist in the project. Returns whether anything changed.
    @discardableResult
    public func prune(against project: ShowProject) -> Bool {
        let validFixtures = Set(project.fixtures.map(\.id))
        let validGroups = Set(project.groups.map(\.id))
        let validCueLists = Set(project.cueLists.map(\.id))
        var validCues = Set<UUID>()
        for list in project.cueLists {
            validCues.formUnion(list.cues.map(\.id))
        }
        let validSongs = Set(project.songs.map(\.id))

        let before = snapshot
        snapshot.fixtureIDs = snapshot.fixtureIDs.intersection(validFixtures)
        snapshot.groupIDs = snapshot.groupIDs.intersection(validGroups)
        snapshot.cueListIDs = snapshot.cueListIDs.intersection(validCueLists)
        snapshot.cueIDs = snapshot.cueIDs.intersection(validCues)
        snapshot.songIDs = snapshot.songIDs.intersection(validSongs)
        return snapshot != before
    }
}
