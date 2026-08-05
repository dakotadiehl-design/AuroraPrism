import AuroraEngine
import AuroraModel
import XCTest

final class CueResolverTests: XCTestCase {
    private func cue(
        number: String,
        tracking: TrackingMode = .track,
        levels: [UUID: [String: Double]]
    ) -> Cue {
        let fixtures = levels.map { FixtureCueLevels(fixtureId: $0.key, attributes: $0.value) }
        return Cue(
            number: Decimal(string: number)!,
            name: number,
            tracking: tracking,
            levels: CueLevelData(fixtures: fixtures)
        )
    }

    func testTrackAccumulates() {
        let f = UUID()
        let cues = [
            cue(number: "1", levels: [f: ["intensity": 0.5]]),
            cue(number: "2", levels: [f: ["colorR": 1.0]]),
        ]
        let look = CueResolver.resolveLook(cues: cues, index: 1)
        XCTAssertEqual(look.fixtureAttributes[f]?["intensity"], 0.5)
        XCTAssertEqual(look.fixtureAttributes[f]?["colorR"], 1.0)
    }

    func testCueOnlyTargetPreservesPriorLook() {
        let f = UUID()
        let cues = [
            cue(number: "1", levels: [f: ["intensity": 0.5]]),
            cue(number: "2", tracking: .cueOnly, levels: [f: ["colorR": 1.0]]),
        ]
        // Without priorLook: base is tracked look before cue → intensity kept (P0-6).
        let look = CueResolver.resolveLook(cues: cues, index: 1)
        XCTAssertEqual(look.fixtureAttributes[f]?["intensity"], 0.5)
        XCTAssertEqual(look.fixtureAttributes[f]?["colorR"], 1.0)
    }

    func testCueOnlyUsesExplicitPriorLook() {
        let f = UUID()
        let cues = [
            cue(number: "1", levels: [f: ["intensity": 0.1]]),
            cue(number: "2", tracking: .cueOnly, levels: [f: ["colorR": 1.0]]),
        ]
        var prior = ActiveLook()
        prior.set(fixtureID: f, attribute: "intensity", value: 0.9)
        prior.set(fixtureID: f, attribute: "pan", value: 0.25)
        let look = CueResolver.resolveLook(cues: cues, index: 1, project: .empty(), priorLook: prior)
        XCTAssertEqual(look.fixtureAttributes[f]?["intensity"], 0.9)
        XCTAssertEqual(look.fixtureAttributes[f]?["pan"], 0.25)
        XCTAssertEqual(look.fixtureAttributes[f]?["colorR"], 1.0)
    }

    func testGoldenSequenceTrackCueOnlyTrack() {
        let f = UUID()
        let cues = [
            cue(number: "1", tracking: .track, levels: [f: ["intensity": 0.5]]),
            cue(number: "2", tracking: .cueOnly, levels: [f: ["colorR": 1.0]]),
            cue(number: "3", tracking: .track, levels: [f: ["pan": 0.5]]),
        ]
        let after1 = CueResolver.resolveLook(cues: cues, index: 0)
        XCTAssertEqual(after1.fixtureAttributes[f]?["intensity"], 0.5)

        let after2 = CueResolver.resolveLook(cues: cues, index: 1, project: .empty(), priorLook: after1)
        XCTAssertEqual(after2.fixtureAttributes[f]?["intensity"], 0.5)
        XCTAssertEqual(after2.fixtureAttributes[f]?["colorR"], 1.0)

        // Intermediate cue-only does not enter tracked history for C3.
        let after3 = CueResolver.resolveLook(cues: cues, index: 2)
        XCTAssertEqual(after3.fixtureAttributes[f]?["intensity"], 0.5)
        XCTAssertEqual(after3.fixtureAttributes[f]?["pan"], 0.5)
        XCTAssertNil(after3.fixtureAttributes[f]?["colorR"])
    }

    func testIntermediateCueOnlySkippedInTrack() {
        let f = UUID()
        let cues = [
            cue(number: "1", levels: [f: ["intensity": 0.2]]),
            cue(number: "1.5", tracking: .cueOnly, levels: [f: ["intensity": 1.0]]),
            cue(number: "2", levels: [f: ["colorR": 0.5]]),
        ]
        let look = CueResolver.resolveLook(cues: cues, index: 2)
        XCTAssertEqual(look.fixtureAttributes[f]?["intensity"], 0.2)
        XCTAssertEqual(look.fixtureAttributes[f]?["colorR"], 0.5)
    }
}
