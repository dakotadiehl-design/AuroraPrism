import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class EffectRunnerTests: XCTestCase {
    private let f1 = UUID(uuidString: "00000000-0000-4000-8000-0000000000f1")!
    private let f2 = UUID(uuidString: "00000000-0000-4000-8000-0000000000f2")!
    private let f3 = UUID(uuidString: "00000000-0000-4000-8000-0000000000f3")!

    // MARK: - Pure generators

    func testPulseAtQuarterCycleIsPeak() {
        // sin(2π * 0.25) = 1 → base 0 + size 0.5 → 0.5
        let effect = EffectInstance(
            kind: .pulse,
            rateHz: 1,
            size: 0.5,
            phase: 0,
            attribute: "intensity",
            fixtureIDs: [f1]
        )
        let out = EffectRunner.apply(look: .empty, time: 0.25, effects: [effect])
        XCTAssertEqual(out.fixtureAttributes[f1]?["intensity"] ?? -1, 0.5, accuracy: 1e-9)
    }

    func testPulseAddsToBaseAndClamps() {
        var look = ActiveLook()
        look.set(fixtureID: f1, attribute: "intensity", value: 0.8)
        let effect = EffectInstance(
            kind: .pulse,
            rateHz: 1,
            size: 0.5,
            phase: 0,
            fixtureIDs: [f1]
        )
        // t=0.25 → sin = 1 → 0.8 + 0.5 = 1.3 → clamp 1
        let out = EffectRunner.apply(look: look, time: 0.25, effects: [effect])
        XCTAssertEqual(out.fixtureAttributes[f1]?["intensity"] ?? -1, 1.0, accuracy: 1e-9)
    }

    func testWaveSpreadsPhaseAcrossFixtures() {
        // At t=0, phase_i = spread * i/(n-1). With size 1:
        // f1 phase 0 → sin(0)=0; f3 phase 0.5 → sin(π)=0 wait sin(2π*0.5)=0
        // Use phase 0, spread 1, t=0: offset = 0 for all if spread only...
        // At t=0, phase 0.25 on f1 alone would peak; with spread=0.5 and n=3:
        // i=0 phase=0 → 0; i=1 phase=0.25 → sin(π/2)=1; i=2 phase=0.5 → 0
        let effect = EffectInstance(
            kind: .wave,
            rateHz: 0,
            size: 1,
            phase: 0,
            spread: 0.5,
            attribute: "intensity",
            fixtureIDs: [f1, f2, f3]
        )
        let out = EffectRunner.apply(look: .empty, time: 0, effects: [effect])
        XCTAssertEqual(out.fixtureAttributes[f1]?["intensity"] ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(out.fixtureAttributes[f2]?["intensity"] ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(out.fixtureAttributes[f3]?["intensity"] ?? -1, 0, accuracy: 1e-9)
    }

    func testChaseAdvancesWithTime() {
        let effect = EffectInstance(
            kind: .chase,
            rateHz: 1,
            size: 1,
            phase: 0,
            attribute: "intensity",
            fixtureIDs: [f1, f2, f3]
        )
        // t=0 → index 0; t=1/3 ≈ first third still index 0; t just under 2/3 → index 1
        let t0 = EffectRunner.apply(look: .empty, time: 0, effects: [effect])
        XCTAssertEqual(t0.fixtureAttributes[f1]?["intensity"], 1)
        XCTAssertEqual(t0.fixtureAttributes[f2]?["intensity"], 0)
        XCTAssertEqual(t0.fixtureAttributes[f3]?["intensity"], 0)

        let t1 = EffectRunner.apply(look: .empty, time: 0.4, effects: [effect])
        // step = 0.4 * 3 = 1.2 → floor 1 → f2
        XCTAssertEqual(t1.fixtureAttributes[f1]?["intensity"], 0)
        XCTAssertEqual(t1.fixtureAttributes[f2]?["intensity"], 1)
        XCTAssertEqual(t1.fixtureAttributes[f3]?["intensity"], 0)
    }

    func testRainbowSetsRGB() {
        let effect = EffectInstance(
            kind: .rainbow,
            rateHz: 0,
            size: 1,
            phase: 0,
            fixtureIDs: [f1]
        )
        // hue 0 → red
        let out = EffectRunner.apply(look: .empty, time: 0, effects: [effect])
        XCTAssertEqual(out.fixtureAttributes[f1]?["colorR"] ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(out.fixtureAttributes[f1]?["colorG"] ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(out.fixtureAttributes[f1]?["colorB"] ?? -1, 0, accuracy: 1e-9)
    }

    func testDisabledAndEmptyFixturesAreNoOps() {
        let disabled = EffectInstance(
            kind: .chase,
            size: 1,
            fixtureIDs: [f1],
            enabled: false
        )
        let empty = EffectInstance(kind: .chase, size: 1, fixtureIDs: [], enabled: true)
        var look = ActiveLook()
        look.set(fixtureID: f1, attribute: "intensity", value: 0.3)
        let out = EffectRunner.apply(look: look, time: 1, effects: [disabled, empty])
        XCTAssertEqual(out.fixtureAttributes[f1]?["intensity"], 0.3)
    }

    // MARK: - Runner registry

    func testUpsertRemoveAndRunningCount() {
        let runner = EffectRunner()
        let a = EffectInstance(id: f1, name: "A", kind: .pulse, fixtureIDs: [f1])
        let b = EffectInstance(id: f2, name: "B", kind: .chase, fixtureIDs: [f1], enabled: false)
        runner.upsert(a)
        runner.upsert(b)
        XCTAssertEqual(runner.snapshot().count, 2)
        XCTAssertEqual(runner.runningCount, 1)
        runner.setEnabled(id: f2, enabled: true)
        XCTAssertEqual(runner.runningCount, 2)
        runner.remove(id: f1)
        XCTAssertEqual(runner.snapshot().count, 1)
        runner.clear()
        XCTAssertEqual(runner.snapshot().count, 0)
    }

    func testExplicitOrderNotUUIDOrder() {
        let lowID = UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
        let highID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let later = EffectInstance(id: lowID, name: "Later", fixtureIDs: [f1], order: 10)
        let earlier = EffectInstance(id: highID, name: "Earlier", fixtureIDs: [f1], order: 1)
        let runner = EffectRunner()
        runner.upsert(later)
        runner.upsert(earlier)
        XCTAssertEqual(runner.snapshot().map(\.name), ["Earlier", "Later"])
    }

    func testLoadExportDefinitionsRoundTrip() {
        let defs = [
            EffectDefinition(name: "P", kind: "pulse", fixtureIDs: [f1], order: 0),
            EffectDefinition(name: "C", kind: "chase", fixtureIDs: [f2, f1], order: 1, enabled: false),
        ]
        let runner = EffectRunner()
        runner.load(definitions: defs)
        let exported = runner.exportDefinitions()
        XCTAssertEqual(exported.map(\.name), ["P", "C"])
        XCTAssertEqual(exported[1].fixtureIDs, [f2, f1])
        XCTAssertFalse(exported[1].enabled)
    }

    func testApplyRespectsOrderNotUUID() {
        // Two chases: lower order writes first, higher order overwrites on same fixture.
        let a = EffectInstance(
            id: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!,
            kind: .chase,
            rateHz: 0,
            size: 0.25,
            attribute: "intensity",
            fixtureIDs: [f1],
            order: 0
        )
        let b = EffectInstance(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000099")!,
            kind: .chase,
            rateHz: 0,
            size: 0.75,
            attribute: "intensity",
            fixtureIDs: [f1],
            order: 1
        )
        let out = EffectRunner.apply(look: .empty, time: 0, effects: [a, b])
        XCTAssertEqual(out.fixtureAttributes[f1]?["intensity"], 0.75)
    }

    // MARK: - Engine layer order: effects under programmer

    func testEngineEffectsUnderProgrammer() {
        let output = OutputManager()
        output.register(NullOutputDriver())
        let clock = ManualEngineClock(time: 0)
        let engine = LightingEngine(output: output, clock: clock)

        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "D",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f1, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        engine.load(project: project)

        // Base look via manual override (playback layer).
        var base = ActiveLook()
        base.set(fixtureID: f1, attribute: "intensity", value: 0)
        engine.setLook(base)

        // Chase would set intensity to 1, but programmer wins at 0.25.
        engine.effects.upsert(
            EffectInstance(kind: .chase, rateHz: 0, size: 1, attribute: "intensity", fixtureIDs: [f1])
        )
        engine.programmer.set(fixtureID: f1, attribute: "intensity", value: 0.25)

        engine.stepForTesting()
        let levels = engine.currentSnapshot().universeLevels[1] ?? []
        // 0.25 * 255 ≈ 63–64
        XCTAssertEqual(Double(levels[0]), 63.75, accuracy: 1.0)
    }

    func testEngineEffectsModulateWithoutProgrammer() {
        let output = OutputManager()
        output.register(NullOutputDriver())
        let clock = ManualEngineClock(time: 0)
        let engine = LightingEngine(output: output, clock: clock)

        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "D",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f1, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        engine.load(project: project)
        engine.setLook(.empty)

        engine.effects.upsert(
            EffectInstance(kind: .chase, rateHz: 0, size: 1, attribute: "intensity", fixtureIDs: [f1])
        )
        engine.stepForTesting()
        let levels = engine.currentSnapshot().universeLevels[1] ?? []
        XCTAssertEqual(levels[0], 255)
    }
}
