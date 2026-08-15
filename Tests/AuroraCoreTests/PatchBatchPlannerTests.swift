import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class PatchBatchPlannerTests: XCTestCase {
    private func projectWithDef() -> (ShowProject, UUID, UUID, UUID) {
        var p = ShowProject.empty(name: "P")
        let u = Universe(number: 1)
        let def = FixtureDefinition(
            manufacturer: "G",
            model: "RGB",
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ]
        )
        p.universes = [u]
        p.fixtureDefinitions = [def]
        return (p, u.id, def.id, u.id)
    }

    func testBatchPlanValid() {
        let (p, uni, def, _) = projectWithDef()
        let plan = PatchBatchPlanner.plan(
            project: p,
            definitionID: def,
            universeID: uni,
            startAddress: 101,
            quantity: 4,
            namePrefix: "LP"
        )
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.starts, [101, 104, 107, 110])
        XCTAssertEqual(plan.footprint, 3)
    }

    func testBatchPlanOverlapRejected() {
        var (p, uni, def, _) = projectWithDef()
        p.fixtures = [
            PatchedFixture(name: "X", definitionId: def, universeId: uni, address: 100),
        ]
        let plan = PatchBatchPlanner.plan(
            project: p,
            definitionID: def,
            universeID: uni,
            startAddress: 101,
            quantity: 1,
            namePrefix: "Y"
        )
        // 101-103 overlaps 100-102
        XCTAssertFalse(plan.isValid)
    }

    func testNextFreeSkipsOccupied() {
        var (p, uni, def, _) = projectWithDef()
        p.fixtures = [
            PatchedFixture(name: "A", definitionId: def, universeId: uni, address: 1),
        ]
        let plan = PatchBatchPlanner.planNextFree(
            project: p,
            definitionID: def,
            universeID: uni,
            quantity: 2,
            namePrefix: "B"
        )
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.startAddress, 4)
        XCTAssertEqual(plan.starts.count, 2)
    }

    func testGridSegmentsWrap() {
        let segs = DMXUniverseGridLayout.segments(start: 30, footprint: 6, channelsPerRow: 32)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].addressStart, 30)
        XCTAssertEqual(segs[0].addressEnd, 32)
        XCTAssertEqual(segs[1].addressStart, 33)
        XCTAssertEqual(segs[1].addressEnd, 35)
    }

    func testBatchCommandUndo() throws {
        var (p, uni, def, _) = projectWithDef()
        let session = DocumentSession(project: p)
        let plan = PatchBatchPlanner.plan(
            project: session.project,
            definitionID: def,
            universeID: uni,
            startAddress: 10,
            quantity: 3,
            namePrefix: "T"
        )
        let cmd = BatchPatchCommand(plan: plan)
        try session.perform(cmd)
        XCTAssertEqual(session.project.fixtures.count, 3)
        try session.undo()
        XCTAssertEqual(session.project.fixtures.count, 0)
    }
}
