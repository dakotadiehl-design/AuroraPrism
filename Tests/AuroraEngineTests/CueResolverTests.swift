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

    func testCueOnlyTargetIgnoresPrior() {
        let f = UUID()
        let cues = [
            cue(number: "1", levels: [f: ["intensity": 0.5]]),
            cue(number: "2", tracking: .cueOnly, levels: [f: ["colorR": 1.0]]),
        ]
        let look = CueResolver.resolveLook(cues: cues, index: 1)
        XCTAssertNil(look.fixtureAttributes[f]?["intensity"])
        XCTAssertEqual(look.fixtureAttributes[f]?["colorR"], 1.0)
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
