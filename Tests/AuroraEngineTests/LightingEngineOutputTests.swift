import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

final class LightingEngineOutputTests: XCTestCase {
    private func makeShow() -> (ShowProject, UUID) {
        var project = ShowProject.empty(name: "E")
        let universeID = UUID()
        let definitionID = UUID()
        let fixtureID = UUID()
        project.universes = [Universe(id: universeID, number: 1, channelCount: 512)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: definitionID,
                manufacturer: "G",
                model: "Dimmer",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(
                id: fixtureID,
                name: "F1",
                definitionId: definitionID,
                universeId: universeID,
                address: 1
            )
        ]
        return (project, fixtureID)
    }

    func testStepIncrementsFrameAndFlushesMock() throws {
        let output = OutputManager()
        let mock = MockOutputDriver()
        output.register(mock)
        try output.startAll()

        let clock = ManualEngineClock()
        let engine = LightingEngine(output: output, clock: clock)
        let (project, fixtureID) = makeShow()
        engine.load(project: project)

        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "intensity", value: 1.0)
        engine.setLook(look) // manual override for unit test

        engine.stepForTesting()
        XCTAssertEqual(engine.currentSnapshot().frameIndex, 1)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)

        clock.advance(by: 0.025)
        engine.stepForTesting()
        XCTAssertEqual(engine.currentSnapshot().frameIndex, 2)
        XCTAssertEqual(mock.frames(for: 1).count, 2)
    }

    func testSnapshotMatchesMergedLevels() {
        let output = OutputManager()
        let engine = LightingEngine(output: output, clock: ManualEngineClock())
        let (project, fixtureID) = makeShow()
        engine.load(project: project)
        var look = ActiveLook()
        look.set(fixtureID: fixtureID, attribute: "intensity", value: 0.5)
        engine.setLook(look)
        engine.stepForTesting()
        XCTAssertEqual(engine.currentSnapshot().universeLevels[1]?[0], 128)
    }

    func testPlaybackGoDrivesOutput() throws {
        let output = OutputManager()
        let mock = MockOutputDriver()
        output.register(mock)
        try output.startAll()
        let clock = ManualEngineClock()
        let engine = LightingEngine(output: output, clock: clock)
        var (project, fixtureID) = makeShow()
        project.cueLists = [
            CueList(name: "Main", cues: [
                Cue(
                    number: 1,
                    name: "Full",
                    fadeIn: 0,
                    levels: CueLevelData(fixtures: [
                        FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
                    ])
                )
            ])
        ]
        engine.load(project: project)
        engine.setLook(nil)
        engine.go()
        engine.stepForTesting()
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)
        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)
    }

    func testStartAndStopScheduler() throws {
        let output = OutputManager()
        let null = NullOutputDriver()
        output.register(null)
        let engine = LightingEngine(
            output: output,
            configuration: EngineConfiguration(frameRateHz: 40),
            clock: ContinuousEngineClock()
        )
        engine.load(project: makeShow().0)
        try engine.start()
        XCTAssertTrue(engine.isRunning)
        // Allow a couple ticks.
        Thread.sleep(forTimeInterval: 0.08)
        let frames = engine.currentSnapshot().frameIndex
        engine.stop()
        XCTAssertFalse(engine.isRunning)
        XCTAssertGreaterThan(frames, 0)
    }
}
