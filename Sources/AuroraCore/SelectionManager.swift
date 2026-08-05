import AuroraModel
import Foundation

/// Immutable multi-select snapshot for one moment in time.
///
/// Fixture selection is ordered (P1-5): `orderedFixtureIDs` is the source of truth
/// for phase-sensitive operations (chase, fan, wave). `fixtureIDs` is membership.
public struct SelectionSnapshot: Equatable, Sendable, Hashable {
    /// Selection order (click / multi-select order). Duplicates are not allowed.
    public var orderedFixtureIDs: [UUID]
    /// Membership set — always matches `Set(orderedFixtureIDs)`.
    public var fixtureIDs: Set<UUID>
    public var cueIDs: Set<UUID>
    public var cueListIDs: Set<UUID>
    public var songIDs: Set<UUID>
    public var groupIDs: Set<UUID>

    public init(
        orderedFixtureIDs: [UUID] = [],
        fixtureIDs: Set<UUID>? = nil,
        cueIDs: Set<UUID> = [],
        cueListIDs: Set<UUID> = [],
        songIDs: Set<UUID> = [],
        groupIDs: Set<UUID> = []
    ) {
        let ordered = Self.dedupePreservingOrder(orderedFixtureIDs)
        self.orderedFixtureIDs = ordered
        self.fixtureIDs = fixtureIDs ?? Set(ordered)
        // Keep membership in sync if caller passed both inconsistently.
        if self.fixtureIDs != Set(ordered) {
            self.orderedFixtureIDs = ordered
            self.fixtureIDs = Set(ordered)
        }
        self.cueIDs = cueIDs
        self.cueListIDs = cueListIDs
        self.songIDs = songIDs
        self.groupIDs = groupIDs
    }

    /// Convenience: build from a membership set (stable UUID-string order).
    public init(
        fixtureIDs: Set<UUID>,
        cueIDs: Set<UUID> = [],
        cueListIDs: Set<UUID> = [],
        songIDs: Set<UUID> = [],
        groupIDs: Set<UUID> = []
    ) {
        let ordered = fixtureIDs.sorted { $0.uuidString < $1.uuidString }
        self.orderedFixtureIDs = ordered
        self.fixtureIDs = fixtureIDs
        self.cueIDs = cueIDs
        self.cueListIDs = cueListIDs
        self.songIDs = songIDs
        self.groupIDs = groupIDs
    }

    public static let empty = SelectionSnapshot()

    public var isEmpty: Bool {
        orderedFixtureIDs.isEmpty
            && cueIDs.isEmpty
            && cueListIDs.isEmpty
            && songIDs.isEmpty
            && groupIDs.isEmpty
    }

    fileprivate static func dedupePreservingOrder(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        result.reserveCapacity(ids.count)
        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }
        return result
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

    /// Select fixtures with explicit order (preferred for phase-sensitive tools).
    public func selectFixturesOrdered(_ ids: [UUID], extending: Bool = false) {
        if extending {
            var ordered = snapshot.orderedFixtureIDs
            var membership = snapshot.fixtureIDs
            for id in ids where membership.insert(id).inserted {
                ordered.append(id)
            }
            snapshot.orderedFixtureIDs = ordered
            snapshot.fixtureIDs = membership
        } else {
            let ordered = SelectionSnapshot.dedupePreservingOrder(ids)
            snapshot.orderedFixtureIDs = ordered
            snapshot.fixtureIDs = Set(ordered)
        }
    }

    /// Select fixtures from a set. New members append in stable UUID order when extending;
    /// full replace uses stable UUID-string order (call `selectFixturesOrdered` when order matters).
    public func selectFixtures(_ ids: Set<UUID>, extending: Bool = false) {
        if extending {
            let newcomers = ids.subtracting(snapshot.fixtureIDs).sorted { $0.uuidString < $1.uuidString }
            selectFixturesOrdered(newcomers, extending: true)
        } else {
            selectFixturesOrdered(ids.sorted { $0.uuidString < $1.uuidString }, extending: false)
        }
    }

    public func deselectFixtures(_ ids: Set<UUID>) {
        snapshot.orderedFixtureIDs.removeAll { ids.contains($0) }
        snapshot.fixtureIDs.subtract(ids)
    }

    public func toggleFixture(_ id: UUID) {
        if snapshot.fixtureIDs.contains(id) {
            snapshot.fixtureIDs.remove(id)
            snapshot.orderedFixtureIDs.removeAll { $0 == id }
        } else {
            snapshot.fixtureIDs.insert(id)
            snapshot.orderedFixtureIDs.append(id)
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
        snapshot.orderedFixtureIDs = snapshot.orderedFixtureIDs.filter { validFixtures.contains($0) }
        snapshot.fixtureIDs = Set(snapshot.orderedFixtureIDs)
        snapshot.groupIDs = snapshot.groupIDs.intersection(validGroups)
        snapshot.cueListIDs = snapshot.cueListIDs.intersection(validCueLists)
        snapshot.cueIDs = snapshot.cueIDs.intersection(validCues)
        snapshot.songIDs = snapshot.songIDs.intersection(validSongs)
        return snapshot != before
    }
}
