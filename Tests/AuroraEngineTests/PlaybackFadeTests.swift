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

    /// Outgoing fadeOut lengthens the crossfade when greater than incoming fadeIn.
    func testFadeOutExtendsCrossfade() {
        let list = CueList(name: "M", cues: [
            Cue(
                number: 1,
                name: "A",
                fadeIn: 0,
                fadeOut: 2.0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0])
                ])
            ),
            Cue(
                number: 2,
                name: "B",
                fadeIn: 0.5,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
                ])
            ),
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        _ = pb.look(at: 0)
        pb.go(at: 1) // start A→B, duration max(2.0, 0.5) = 2.0
        let mid = pb.look(at: 2.0) // 1s into 2s fade
        XCTAssertEqual(pb.snapshot().phase, .fade)
        XCTAssertEqual(mid.fixtureAttributes[fixtureID]?["intensity"] ?? -1, 0.5, accuracy: 0.05)
        let end = pb.look(at: 3.0)
        XCTAssertEqual(end.fixtureAttributes[fixtureID]?["intensity"] ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(pb.snapshot().phase, .active)
    }

    func testFiniteLoopReentersBeforeAdvance() {
        let list = CueList(name: "M", cues: [
            Cue(
                number: 1,
                name: "Loop",
                fadeIn: 0,
                follow: .afterTime,
                followTime: 1.0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.5])
                ]),
                loop: LoopSpec(count: 2, infinite: false)
            ),
            Cue(
                number: 2,
                name: "Next",
                fadeIn: 0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 1])
                ])
            ),
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        _ = pb.look(at: 0)
        XCTAssertEqual(pb.snapshot().cueIndex, 0)
        // First follow at t=1: re-enter cue 0 (count 2 → one reentry).
        _ = pb.look(at: 1.0)
        XCTAssertEqual(pb.snapshot().cueIndex, 0)
        // Second follow: advance to cue 1.
        _ = pb.look(at: 2.0)
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        XCTAssertEqual(pb.look(at: 2.0).fixtureAttributes[fixtureID]?["intensity"], 1)
    }

    func testManualGoBreaksLoop() {
        let list = CueList(name: "M", cues: [
            Cue(
                number: 1,
                name: "Loop",
                fadeIn: 0,
                follow: .afterTime,
                followTime: 10.0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.3])
                ]),
                loop: .infiniteLoop
            ),
            Cue(
                number: 2,
                name: "Next",
                fadeIn: 0,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.9])
                ])
            ),
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        _ = pb.look(at: 0)
        pb.go(at: 0.5) // break infinite loop
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        XCTAssertEqual(pb.look(at: 0.5).fixtureAttributes[fixtureID]?["intensity"], 0.9)
    }

    func testBackClearsLoopAndMovesPrevious() {
        let list = CueList(name: "M", cues: [
            Cue(number: 1, name: "A", fadeIn: 0, levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.1])
            ])),
            Cue(
                number: 2,
                name: "B",
                fadeIn: 0,
                follow: .afterTime,
                followTime: 5,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: fixtureID, attributes: ["intensity": 0.5])
                ]),
                loop: .infiniteLoop
            ),
        ])
        let pb = PlaybackController()
        pb.load(list: list)
        pb.go(at: 0)
        pb.go(at: 1)
        XCTAssertEqual(pb.snapshot().cueIndex, 1)
        pb.back(at: 1.5)
        XCTAssertEqual(pb.snapshot().cueIndex, 0)
        XCTAssertEqual(pb.look(at: 1.5).fixtureAttributes[fixtureID]?["intensity"], 0.1)
    }
}
