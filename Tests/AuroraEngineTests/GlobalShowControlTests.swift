import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

@MainActor
final class GlobalShowControlTests: XCTestCase {
    private func dimmerProject() -> (ShowProject, UUID, UUID) {
        var project = ShowProject.empty(name: "GSC")
        let u = Universe(number: 1, name: "U1")
        let def = FixtureDefinition(
            id: UUID(),
            manufacturer: "G",
            model: "Dim",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "Int", attribute: "intensity")]
        )
        let fx = UUID()
        project.universes = [u]
        project.fixtureDefinitions = [def]
        project.fixtures = [
            PatchedFixture(id: fx, name: "D1", definitionId: def.id, universeId: u.id, address: 1),
        ]
        return (project, u.id, fx)
    }

    func testMasterScalesIntensityWithoutClearingProgrammer() throws {
        let (project, _, fx) = dimmerProject()
        let out = OutputManager()
        let eng = LightingEngine(output: out)
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.stepForTesting()
        let full = eng.currentSnapshot().universeLevels[1]?[0] ?? 0
        XCTAssertGreaterThan(full, 200)

        eng.setMasterIntensity(0.5)
        eng.stepForTesting()
        let half = eng.currentSnapshot().universeLevels[1]?[0] ?? 0
        XCTAssertLessThan(half, full)
        XCTAssertGreaterThan(half, 50)
        // Programmer store unchanged.
        XCTAssertEqual(eng.programmer.snapshot().values[fx]?["intensity"] ?? 0, 1.0, accuracy: 0.001)
        eng.stop()
    }

    func testBlackoutZerosOutputAndIsReversible() throws {
        let (project, _, fx) = dimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.stepForTesting()
        eng.setBlackout(true)
        eng.stepForTesting()
        XCTAssertEqual(eng.currentSnapshot().universeLevels[1]?[0] ?? 1, 0)
        eng.setBlackout(false)
        eng.stepForTesting()
        XCTAssertGreaterThan(eng.currentSnapshot().universeLevels[1]?[0] ?? 0, 200)
        eng.stop()
    }

    func testFreezeHoldsOutputWhilePlaybackMayAdvance() throws {
        let (project, _, fx) = dimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.stepForTesting()
        eng.setFreeze(true)
        eng.stepForTesting() // capture held frame at full intensity
        let held = eng.currentSnapshot().universeLevels[1]?[0] ?? 0
        XCTAssertGreaterThan(held, 200)
        // Change programmer under freeze — presentation should stay held.
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 0.1)
        eng.stepForTesting()
        XCTAssertEqual(eng.currentSnapshot().universeLevels[1]?[0] ?? 0, held)
        // Unfreeze snaps to current resolved state.
        eng.setFreeze(false)
        eng.stepForTesting()
        let after = eng.currentSnapshot().universeLevels[1]?[0] ?? 255
        XCTAssertLessThan(after, held)
        eng.stop()
    }

    func testBlindSuppressesProgrammerOnOutput() throws {
        let (project, _, fx) = dimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.setBlind(true)
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.stepForTesting()
        XCTAssertEqual(eng.currentSnapshot().universeLevels[1]?[0] ?? 1, 0)
        eng.setBlind(false)
        eng.stepForTesting()
        XCTAssertGreaterThan(eng.currentSnapshot().universeLevels[1]?[0] ?? 0, 200)
        eng.stop()
    }

    func testPanicClearsTemporaryState() throws {
        let (project, _, fx) = dimmerProject()
        let eng = LightingEngine(output: OutputManager())
        eng.load(project: project)
        try eng.start()
        eng.programmer.set(fixtureID: fx, attribute: "intensity", value: 1.0)
        eng.setBlackout(true)
        eng.setFreeze(true)
        eng.panic()
        eng.stepForTesting()
        XCTAssertFalse(eng.globalShowControl.blackout)
        XCTAssertFalse(eng.globalShowControl.freeze)
        XCTAssertFalse(eng.globalShowControl.blind)
        XCTAssertEqual(eng.globalShowControl.masterIntensity, 1, accuracy: 0.001)
        eng.stop()
    }

    /// Master scales only dimmer when both RGB emitters and intensity exist (no double attenuation).
    func testMasterRGBPlusDimmerDoesNotDoubleScale() {
        var look = ActiveLook()
        let fx = UUID()
        look.fixtureAttributes[fx] = [
            "intensity": 1.0,
            "colorR": 1.0,
            "colorG": 0.5,
            "colorB": 0.25,
        ]
        let scaled = GlobalShowControl.applyToLook(look, state: GlobalShowControlState(masterIntensity: 0.5))
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["intensity"] ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["colorR"] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["colorG"] ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["colorB"] ?? 0, 0.25, accuracy: 0.001)
    }

    /// Color-only fixtures still respond to Master via emitters.
    func testMasterScalesColorOnlyFixture() {
        var look = ActiveLook()
        let fx = UUID()
        look.fixtureAttributes[fx] = [
            "colorR": 1.0,
            "colorG": 0.5,
            "colorB": 0.0,
        ]
        let scaled = GlobalShowControl.applyToLook(look, state: GlobalShowControlState(masterIntensity: 0.5))
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["colorR"] ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["colorG"] ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(scaled.fixtureAttributes[fx]?["colorB"] ?? 0, 0.0, accuracy: 0.001)
    }

    func testBlackoutZerosDimmerPreservesChromaticWhenHasDimmer() {
        var look = ActiveLook()
        let fx = UUID()
        look.fixtureAttributes[fx] = [
            "intensity": 1.0,
            "colorR": 1.0,
            "colorG": 0.5,
            "colorB": 0.25,
        ]
        let bo = GlobalShowControl.applyToLook(look, state: GlobalShowControlState(blackout: true))
        XCTAssertEqual(bo.fixtureAttributes[fx]?["intensity"] ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(bo.fixtureAttributes[fx]?["colorR"] ?? 0, 1.0, accuracy: 0.001)
    }
}
