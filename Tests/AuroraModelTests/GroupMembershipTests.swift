import AuroraModel
import XCTest

final class GroupMembershipTests: XCTestCase {
    func testSyncRebuildsFixtureGroupIds() {
        var project = ShowProject.empty()
        let f1 = UUID()
        let f2 = UUID()
        let g1 = UUID()
        let u = UUID()
        let d = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(id: d, manufacturer: "G", model: "D", channels: [
                ChannelDef(offset: 1, name: "I", attribute: "intensity")
            ])
        ]
        project.fixtures = [
            PatchedFixture(id: f1, name: "A", definitionId: d, universeId: u, address: 1, groupIds: []),
            PatchedFixture(id: f2, name: "B", definitionId: d, universeId: u, address: 2, groupIds: [UUID()]),
        ]
        project.groups = [Group(id: g1, name: "All", fixtureIds: [f1, f2])]

        GroupMembership.syncFixtureGroupIds(&project)
        XCTAssertEqual(Set(project.fixtures[0].groupIds), [g1])
        XCTAssertEqual(Set(project.fixtures[1].groupIds), [g1])
        XCTAssertFalse(GroupMembership.hasDivergence(project))
    }
}
