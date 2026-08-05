import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

/// P0-3: ordinary project edits must not reset active playback / stage look.
final class PlaybackPreserveOnEditTests: XCTestCase {
    private func makeShowWithCue() -> (ShowProject, UUID, UUID) {
        var project = ShowProject.empty(name: "Live")
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
        let listID = UUID()
        project.cueLists = [
            CueList(
                id: listID,
                name: "Main",
                cues: [
                    Cue(
                        number: 1,
                        name: "Full",
                        fadeIn: 0,
                        levels: CueLevelData(fixtures: [
                            FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
                        ])
                    ),
                    Cue(
                        number: 2,
                        name: "Other",
                        fadeIn: 0,
                        levels: CueLevelData(fixtures: [
                            FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.25])
                        ])
                    )
                ]
            )
        ]
        return (project, fixtureID, listID)
    }

    private func liveEngine(project: ShowProject) throws -> (LightingEngine, MockOutputDriver, ManualEngineClock) {
        let output = OutputManager()
        let mock = MockOutputDriver()
        output.register(mock)
        try output.startAll()
        let clock = ManualEngineClock()
        let engine = LightingEngine(output: output, clock: clock)
        engine.load(project: project)
        engine.setLook(nil)
        engine.go()
        engine.stepForTesting()
        return (engine, mock, clock)
    }

    func testRenameProjectDoesNotResetActiveCueOrDMX() throws {
        var (project, _, _) = makeShowWithCue()
        let (engine, mock, _) = try liveEngine(project: project)
        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)

        project.metadata.name = "Renamed Live Show"
        engine.updateProject(project)
        engine.stepForTesting()

        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)
    }

    func testMIDIMappingEditDoesNotResetActiveCue() throws {
        var (project, _, _) = makeShowWithCue()
        let (engine, mock, _) = try liveEngine(project: project)

        project.midiMappings = [
            MIDIMapping(
                name: "GO",
                deviceID: "uid:1",
                messageType: "noteOn",
                data1: 60,
                action: "go"
            )
        ]
        engine.updateProject(project)
        engine.stepForTesting()

        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)
    }

    func testUnrelatedCueEditDoesNotResetActiveLook() throws {
        var (project, fixtureID, listID) = makeShowWithCue()
        let (engine, mock, _) = try liveEngine(project: project)

        // Edit cue 2 only (not the active cue 1).
        guard var list = project.cueLists.first(where: { $0.id == listID }) else {
            return XCTFail("missing list")
        }
        list.cues[1].name = "Other Renamed"
        list.cues[1].levels = CueLevelData(fixtures: [
            FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.1])
        ])
        project.cueLists = [list]

        engine.updateProject(project)
        engine.stepForTesting()

        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)
    }

    func testPaletteRenameDoesNotResetActiveCue() throws {
        var (project, _, _) = makeShowWithCue()
        let (engine, mock, _) = try liveEngine(project: project)

        project.palettes = [
            Palette(name: "Warm", type: .color, values: ["red": 1, "green": 0.4, "blue": 0.1])
        ]
        engine.updateProject(project)
        engine.stepForTesting()

        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 255)
    }

    func testDestructiveLoadResetsPlayback() throws {
        var (project, _, _) = makeShowWithCue()
        let (engine, mock, _) = try liveEngine(project: project)
        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, 0)

        project.metadata.name = "New Open"
        engine.load(project: project)
        engine.stepForTesting()

        // Destructive load returns to idle (no auto-GO).
        XCTAssertEqual(engine.currentSnapshot().playback.cueIndex, -1)
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 0)
    }

    func testOpenDifferentProjectBlackoutsRemovedUniverses() throws {
        let output = OutputManager()
        let mock = MockOutputDriver()
        output.register(mock)
        try output.startAll()
        let engine = LightingEngine(output: output, clock: ManualEngineClock())

        var projectA = ShowProject.empty(name: "A")
        let u1 = UUID()
        let def = UUID()
        let fix = UUID()
        projectA.universes = [
            Universe(id: u1, number: 1, channelCount: 512),
            Universe(id: UUID(), number: 2, channelCount: 512)
        ]
        projectA.fixtureDefinitions = [
            FixtureDefinition(
                id: def,
                manufacturer: "G",
                model: "D",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        projectA.fixtures = [
            PatchedFixture(id: fix, name: "F", definitionId: def, universeId: u1, address: 1)
        ]
        engine.load(project: projectA)
        var look = ActiveLook()
        look.set(fixtureID: fix, attribute: "intensity", value: 1)
        engine.setLook(look)
        engine.stepForTesting()
        XCTAssertEqual(mock.frames(for: 2).last?.data[0], 0)

        var projectB = ShowProject.empty(name: "B")
        projectB.universes = [Universe(id: UUID(), number: 1, channelCount: 512)]
        engine.load(project: projectB)
        engine.stepForTesting()

        // Universe 2 removed — reconcile blackout then drop.
        let u2Frames = mock.frames(for: 2)
        XCTAssertFalse(u2Frames.isEmpty)
        XCTAssertEqual(u2Frames.last?.data[0], 0)
    }
}
