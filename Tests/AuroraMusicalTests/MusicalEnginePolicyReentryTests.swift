import AuroraMusical
import XCTest

/// Legacy engine-behavior notes; production host rules live in
/// `MusicalTimingConfigReconcilerTests` (shared with ShowControlController).
final class MusicalEnginePolicyReentryTests: XCTestCase {
    func testWithoutReselectBugLeavesInternalSelected() {
        // Documents the engine failure mode the host reconciler must prevent.
        let engine = MusicalEngine()
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("uid:A")
        engine.setTimingPolicy(.internalOnly)
        XCTAssertEqual(engine.state.timing.selectedSourceID, MusicalEngine.internalSourceID)
        engine.setTimingPolicy(.externalMIDI)
        XCTAssertEqual(
            engine.state.timing.selectedSourceID,
            MusicalEngine.internalSourceID,
            "without re-select, engine keeps internal as selected"
        )
    }

    func testIdempotentSamePolicyReapplyDoesNotDropSource() {
        let engine = MusicalEngine()
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("uid:A")
        engine.setTimingPolicy(.externalMIDI) // no-op
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
    }
}
