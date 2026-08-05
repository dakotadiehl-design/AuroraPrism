import Foundation

/// Group membership helpers. **`Group.fixtureIds` is authoritative** (P1-13).
/// `PatchedFixture.groupIds` is a derived index rebuilt from groups.
public enum GroupMembership {
    /// Rebuild every fixture's `groupIds` from `Group.fixtureIds`.
    public static func syncFixtureGroupIds(_ project: inout ShowProject) {
        var fixtureToGroups: [UUID: [UUID]] = [:]
        for group in project.groups {
            for fixtureID in group.fixtureIds {
                fixtureToGroups[fixtureID, default: []].append(group.id)
            }
        }
        for i in project.fixtures.indices {
            let id = project.fixtures[i].id
            project.fixtures[i].groupIds = fixtureToGroups[id] ?? []
        }
    }

    /// True when any fixture.groupIds disagrees with groups.
    public static func hasDivergence(_ project: ShowProject) -> Bool {
        var expected: [UUID: Set<UUID>] = [:]
        for group in project.groups {
            for fid in group.fixtureIds {
                expected[fid, default: []].insert(group.id)
            }
        }
        for fixture in project.fixtures {
            let actual = Set(fixture.groupIds)
            let want = expected[fixture.id] ?? []
            if actual != want { return true }
        }
        return false
    }
}
