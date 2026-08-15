import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class BulkRepatchCommandTests: XCTestCase {
    private func projectWithTwoFixtures() -> (ShowProject, UUID, UUID, UUID) {
        var project = ShowProject.empty(name: "Patch")
        let u = Universe(number: 1, name: "U1")
        let def = FixtureDefinition(
            id: UUID(),
            manufacturer: "G",
            model: "Dim",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "Int", attribute: "intensity")]
        )
        let a = UUID()
        let b = UUID()
        project.universes = [u]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: a, name: "A", definitionId: def.id, universeId: u.id, address: 1),
            PatchedFixture(id: b, name: "B", definitionId: def.id, universeId: u.id, address: 10),
        ]
        return (project, u.id, a, b)
    }

    func testSwapAddressesAtomic() throws {
        let (project, uid, a, b) = projectWithTwoFixtures()
        let session = DocumentSession(project: project)
        try session.perform(BulkRepatchCommand(changes: [
            PatchAddressChange(fixtureID: a, universeID: uid, address: 10),
            PatchAddressChange(fixtureID: b, universeID: uid, address: 1),
        ]))
        let fa = session.project.fixtures.first { $0.id == a }!
        let fb = session.project.fixtures.first { $0.id == b }!
        XCTAssertEqual(fa.address, 10)
        XCTAssertEqual(fb.address, 1)
        try session.undo()
        XCTAssertEqual(session.project.fixtures.first { $0.id == a }!.address, 1)
        XCTAssertEqual(session.project.fixtures.first { $0.id == b }!.address, 10)
    }

    func testFinalOverlapRejectedNoMutation() throws {
        let (project, uid, a, b) = projectWithTwoFixtures()
        let session = DocumentSession(project: project)
        // Both to address 1 → final overlap.
        XCTAssertThrowsError(try session.perform(BulkRepatchCommand(changes: [
            PatchAddressChange(fixtureID: a, universeID: uid, address: 1),
            PatchAddressChange(fixtureID: b, universeID: uid, address: 1),
        ])))
        XCTAssertEqual(session.project.fixtures.first { $0.id == a }!.address, 1)
        XCTAssertEqual(session.project.fixtures.first { $0.id == b }!.address, 10)
        XCTAssertFalse(session.canUndo)
    }

    /// PATCH-02: unrelated invalid fixture on another universe does not block repair.
    func testUnrelatedInvalidFixtureDoesNotBlockBulkOnOtherUniverse() throws {
        var project = ShowProject.empty(name: "Legacy")
        let u1 = Universe(number: 1, name: "U1")
        let u2 = Universe(number: 2, name: "U2")
        let def = FixtureDefinition(
            id: UUID(),
            manufacturer: "G",
            model: "Dim",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "Int", attribute: "intensity")]
        )
        let good = UUID()
        let broken = UUID()
        let missingDef = UUID()
        project.universes = [u1, u2]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: good, name: "Good", definitionId: def.id, universeId: u1.id, address: 1),
            // Missing definition on U2 — pre-existing invalid.
            PatchedFixture(id: broken, name: "Broken", definitionId: missingDef, universeId: u2.id, address: 1),
        ]
        let session = DocumentSession(project: project)
        try session.perform(BulkRepatchCommand(changes: [
            PatchAddressChange(fixtureID: good, universeID: u1.id, address: 5),
        ]))
        XCTAssertEqual(session.project.fixtures.first { $0.id == good }!.address, 5)
        // Broken fixture untouched and still present.
        XCTAssertEqual(session.project.fixtures.first { $0.id == broken }!.address, 1)
    }
}
