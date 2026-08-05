import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class UniverseReconcileTests: XCTestCase {
    func testRemovedUniverseBlackoutAndDrop() throws {
        let mock = MockOutputDriver()
        let output = OutputManager()
        output.register(mock)
        try mock.start()

        let engine = LightingEngine(output: output, clock: ManualEngineClock(time: 0))

        var projectA = ShowProject.empty()
        let u1 = UUID()
        let u4 = UUID()
        let d = UUID()
        let f = UUID()
        projectA.universes = [
            Universe(id: u1, number: 1),
            Universe(id: u4, number: 4),
        ]
        projectA.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "D",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        projectA.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u4, address: 1)
        ]
        engine.load(project: projectA)
        var look = ActiveLook()
        look.set(fixtureID: f, attribute: "intensity", value: 1)
        engine.setLook(look)
        engine.stepForTesting()
        XCTAssertFalse(mock.frames(for: 4).isEmpty)
        XCTAssertTrue(mock.frames(for: 4).last!.data.contains(where: { $0 > 0 }))

        mock.reset()
        var projectB = ShowProject.empty()
        projectB.universes = [Universe(id: u1, number: 1)]
        engine.load(project: projectB)
        engine.setLook(nil)
        engine.stepForTesting()

        // Blackout frame should have been sent for U4 during reconcile.
        let u4Frames = mock.frames(for: 4)
        XCTAssertFalse(u4Frames.isEmpty, "expected blackout flush for removed universe")
        XCTAssertTrue(u4Frames.last!.data.allSatisfy { $0 == 0 })
        XCTAssertFalse(output.activeUniverseNumbers.contains(4))
    }
}
