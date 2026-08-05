import AuroraEngine
import AuroraModel
import XCTest

final class ProgrammerTests: XCTestCase {
    private func projectWithDimmer() -> (ShowProject, UUID) {
        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "D",
                channelCount: 1,
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        return (project, f)
    }

    func testProgrammerOverridesPlayback() {
        let (project, f) = projectWithDimmer()
        var playback = ActiveLook()
        playback.set(fixtureID: f, attribute: "intensity", value: 0.2)
        let prog = Programmer()
        prog.set(fixtureID: f, attribute: "intensity", value: 0.9)
        let out = prog.apply(onPlayback: playback, project: project)
        XCTAssertEqual(out.fixtureAttributes[f]?["intensity"], 0.9)
    }

    func testBlindBlocksProgrammerOutput() {
        let (project, f) = projectWithDimmer()
        var playback = ActiveLook()
        playback.set(fixtureID: f, attribute: "intensity", value: 0.2)
        let prog = Programmer()
        prog.set(fixtureID: f, attribute: "intensity", value: 0.9)
        prog.setBlind(true)
        let out = prog.apply(onPlayback: playback, project: project)
        XCTAssertEqual(out.fixtureAttributes[f]?["intensity"], 0.2)
    }

    func testHighlightForcesIntensity() {
        let (project, f) = projectWithDimmer()
        let prog = Programmer()
        prog.setHighlight(true)
        prog.setHighlightSelection([f])
        let out = prog.apply(onPlayback: .empty, project: project)
        XCTAssertEqual(out.fixtureAttributes[f]?["intensity"], 1)
    }

    func testHighlightUsesPersonalityValues() {
        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "Special",
                channelCount: 1,
                channels: [
                    ChannelDef(
                        offset: 1,
                        name: "I",
                        attribute: "intensity",
                        defaultValue: 10,
                        highlightValue: 64
                    )
                ]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        let prog = Programmer()
        prog.setHighlight(true)
        prog.setHighlightSelection([f])
        let out = prog.apply(onPlayback: .empty, project: project)
        // highlightValue 64 / 255
        XCTAssertEqual(out.fixtureAttributes[f]?["intensity"] ?? -1, 64.0 / 255.0, accuracy: 0.001)
    }

    func testLocateAndHomeUsePersonality() {
        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "MH",
                channelCount: 3,
                channels: [
                    ChannelDef(offset: 1, name: "I", attribute: "intensity", defaultValue: 0, highlightValue: 255),
                    ChannelDef(offset: 2, name: "Pan", attribute: "pan", resolution: .coarse, defaultValue: 128),
                    ChannelDef(offset: 3, name: "Tilt", attribute: "tilt", resolution: .coarse, defaultValue: 64),
                ],
                hasPanTilt: true
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        let prog = Programmer()
        prog.locate(fixtureIDs: [f], project: project)
        XCTAssertEqual(prog.snapshot().values[f]?["intensity"] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(prog.snapshot().values[f]?["pan"], 0.5)
        XCTAssertEqual(prog.snapshot().values[f]?["tilt"], 0.5)

        prog.home(fixtureIDs: [f], project: project)
        XCTAssertEqual(prog.snapshot().values[f]?["intensity"] ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(prog.snapshot().values[f]?["pan"] ?? -1, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(prog.snapshot().values[f]?["tilt"] ?? -1, 64.0 / 255.0, accuracy: 0.001)
    }

    func testLocateAndHome() {
        let (project, f) = projectWithDimmer()
        let prog = Programmer()
        prog.locate(fixtureIDs: [f], project: project)
        XCTAssertEqual(prog.snapshot().values[f]?["intensity"], 1)
        prog.home(fixtureIDs: [f], project: project)
        // Dimmer default is 0 → home intensity 0, not cleared.
        XCTAssertEqual(prog.snapshot().values[f]?["intensity"] ?? -1, 0, accuracy: 0.001)
    }

    func testWheelSlotSetsNormalizedDMX() {
        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "Wheeler",
                channelCount: 1,
                channels: [
                    ChannelDef(offset: 1, name: "Color Wheel", attribute: "colorWheel", defaultValue: 0)
                ],
                wheels: [
                    WheelDef(
                        name: "Colors",
                        kind: .color,
                        slots: [
                            WheelSlot(index: 0, name: "Open", dmxValue: 0),
                            WheelSlot(index: 1, name: "Red", dmxValue: 128),
                        ]
                    )
                ]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        let prog = Programmer()
        XCTAssertTrue(prog.setWheelSlot(fixtureID: f, wheelKind: .color, slotIndex: 1, project: project))
        XCTAssertEqual(prog.snapshot().values[f]?["colorWheel"] ?? -1, 128.0 / 255.0, accuracy: 0.001)
    }

    func testPanInvertInCompiledMerge() {
        var project = ShowProject.empty()
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "MH",
                channelCount: 2,
                channels: [
                    ChannelDef(offset: 1, name: "Pan", attribute: "pan", resolution: .coarse, defaultValue: 0),
                    ChannelDef(offset: 2, name: "Pan Fine", attribute: "pan", resolution: .fine, defaultValue: 0),
                ],
                hasPanTilt: true,
                panInvert: true
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        var look = ActiveLook()
        look.set(fixtureID: f, attribute: "pan", value: 0.25)
        let levels = MergeStub.merge(project: project, look: look)
        let expected = MergeStub.split16(MergeStub.dmx16Value(normalized: 0.75))
        XCTAssertEqual(levels[1]?[0], expected.coarse)
        XCTAssertEqual(levels[1]?[1], expected.fine)
    }

    func testCaptureLevels() {
        let f = UUID()
        let prog = Programmer()
        prog.set(fixtureID: f, attribute: "intensity", value: 0.5)
        let levels = prog.captureLevels()
        XCTAssertEqual(levels.fixtures.first?.attributes["intensity"], 0.5)
    }
}
