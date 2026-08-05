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

    func testLocateAndHome() {
        let (project, f) = projectWithDimmer()
        let prog = Programmer()
        prog.locate(fixtureIDs: [f], project: project)
        XCTAssertEqual(prog.snapshot().values[f]?["intensity"], 1)
        prog.home(fixtureIDs: [f])
        XCTAssertNil(prog.snapshot().values[f])
    }

    func testCaptureLevels() {
        let f = UUID()
        let prog = Programmer()
        prog.set(fixtureID: f, attribute: "intensity", value: 0.5)
        let levels = prog.captureLevels()
        XCTAssertEqual(levels.fixtures.first?.attributes["intensity"], 0.5)
    }
}
