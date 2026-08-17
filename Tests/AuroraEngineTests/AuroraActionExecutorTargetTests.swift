import AuroraEngine
import AuroraModel
import AuroraMusical
import AuroraOutput
import XCTest

/// P0-3: invalid targets must not report `.executed`.
final class AuroraActionExecutorTargetTests: XCTestCase {
    // AuroraActionExecutor lives in the app target — re-test runtime APIs that feed it.

    func testPlaybackFireMissingCueReturnsFalse() {
        let pb = PlaybackController()
        let list = CueList(name: "L", cues: [Cue(number: 1, name: "A")])
        pb.load(list: list, project: .empty())
        XCTAssertFalse(pb.fire(cueID: UUID(), at: 0))
        XCTAssertTrue(pb.fire(cueID: list.cues[0].id, at: 0))
    }

    func testResetSequenceMissingReturnsFalse() {
        let runtime = AMERuntime()
        XCTAssertFalse(runtime.resetSequence(id: UUID()))
        let seq = AMETriggeredSequence(
            name: "S",
            steps: [AMESequenceStep(name: "0", actions: [.go])],
            stateScope: .sequenceGlobal
        )
        _ = runtime.updateDocument(AMEProjectDocument(sequences: [seq]))
        XCTAssertTrue(runtime.resetSequence(id: seq.id))
    }

    func testFireSequenceStepMissingReturnsNil() {
        let runtime = AMERuntime()
        XCTAssertNil(runtime.fireSequenceStepActions(sequenceID: UUID(), stepIndex: 0))
    }
}
