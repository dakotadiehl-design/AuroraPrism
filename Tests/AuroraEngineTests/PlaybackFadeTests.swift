import AuroraEngine
import AuroraModel
import XCTest

final class PlaybackFadeTests: XCTestCase {
    private let fixtureID = UUID()

    private func listWithFade() -> CueList {
        let c1 = Cue(
            number: 1,
            name: "A",
            fadeIn: 0,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0])
            ])
        )
        let c2 = Cue(
            number: 2,
            name: "B",
            fadeIn: 1.0,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
            ])
        )
        return CueList(name: "Main", cues: [c1, c2])
    }

    func testFadeZeroSnapsImmediately() {
        let list = CueList(name: "M", cues: [
            Cue(number: 1, name: "A", fadeIn: 0, levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
            ]))
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        let look = pb.look(at: 0)
        XCTAssertEqual(look.fixtureAttributes[fixtureID]?["intensity"], 1)
        XCTAssertEqual(pb.snapshot().phase, .active)
    }

    func testFadeMidpoint() {
        let pb = PlaybackController()
        pb.load(list: listWithFade())
        pb.go(at: 0) // cue 1
        _ = pb.look(at: 0)
        pb.go(at: 1) // start fade to cue 2 over 1s
        let mid = pb.look(at: 1.5)
        let v = mid.fixtureAttributes[fixtureID]?["intensity"] ?? -1
        XCTAssertEqual(v, 0.5, accuracy: 0.05)
        XCTAssertEqual(pb.snapshot().phase, .fade)
        let end = pb.look(at: 2.0)
        XCTAssertEqual(end.fixtureAttributes[fixtureID]?["intensity"] ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(pb.snapshot().phase, .active)
    }

    func testDelayBeforeFade() {
        let list = CueList(name: "M", cues: [
            Cue(
                number: 1,
                name: "A",
                fadeIn: 0,
                delay: 1.0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
                ])
            )
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        XCTAssertEqual(pb.snapshot().phase, .delay)
        let during = pb.look(at: 0.5)
        XCTAssertTrue(during.fixtureAttributes.isEmpty || (during.fixtureAttributes[fixtureID]?["intensity"] ?? 0) == 0)
        let after = pb.look(at: 1.0)
        XCTAssertEqual(after.fixtureAttributes[fixtureID]?["intensity"], 1)
    }

    func testStopFreezesLook() {
        let pb = PlaybackController()
        pb.load(list: listWithFade())
        pb.go(at: 0)
        pb.go(at: 1)
        _ = pb.look(at: 1.5)
        pb.stop(at: 1.5)
        let frozen = pb.look(at: 1.5)
        let later = pb.look(at: 10)
        XCTAssertEqual(
            frozen.fixtureAttributes[fixtureID]?["intensity"] ?? -1,
            later.fixtureAttributes[fixtureID]?["intensity"] ?? -2,
            accuracy: 0.001
        )
    }

    func testFollowAfterTime() {
        let list = CueList(name: "M", cues: [
            Cue(
                number: 1,
                name: "A",
                fadeIn: 0,
                follow: .afterTime,
                followTime: 1.0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.2])
                ])
            ),
            Cue(
                number: 2,
                name: "B",
                fadeIn: 0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.8])
                ])
            ),
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        _ = pb.look(at: 0)
        XCTAssertEqual(pb.snapshot().cueIndex, 0)
        _ = pb.look(at: 1.0)
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        XCTAssertEqual(pb.look(at: 1.0).fixtureAttributes[fixtureID]?["intensity"], 0.8)
    }
}
