import AuroraMusical
import XCTest

/// P1-2: exercise the **production** reconciler (same path as ShowControlController).
final class MusicalTimingConfigReconcilerTests: XCTestCase {
    private func cfg(
        policy: TimingSourcePolicy,
        source: String?,
        tempo: Double = 120,
        freewheel: Double = 2
    ) -> MusicalAppliedProjectConfig {
        MusicalAppliedProjectConfig(
            tempo: tempo,
            meter: .fourFour,
            freewheelSeconds: freewheel,
            timingPolicy: policy,
            selectedSourceID: source
        )
    }

    private func pulseInterval(bpm: Double) -> TimeInterval {
        60.0 / (bpm * 24.0)
    }

    private func feedPulses(
        engine: MusicalEngine,
        clock: VirtualHostClock,
        source: String,
        count: Int,
        bpm: Double
    ) {
        let dt = pulseInterval(bpm: bpm)
        for _ in 0..<count {
            clock.advance(seconds: dt)
            engine.receiveClockPulse(from: source, at: clock.now())
        }
    }

    // MARK: - Decision matrix

    func testDecideExternalToInternalToExternalResyncsSource() {
        let a = cfg(policy: .externalMIDI, source: "uid:A")
        let internalCfg = cfg(policy: .internalOnly, source: "uid:A")
        let back = cfg(policy: .externalMIDI, source: "uid:A")

        let d1 = MusicalTimingConfigReconciler.decide(previous: a, desired: internalCfg)
        XCTAssertEqual(d1.applyTimingPolicy, .internalOnly)
        // Source identity unchanged and desired is internal — no engine external select required.
        // sourceChanged is false; policyChanged && desired != internal is false.
        XCTAssertFalse(d1.syncExternalSource)

        let d2 = MusicalTimingConfigReconciler.decide(previous: internalCfg, desired: back)
        XCTAssertEqual(d2.applyTimingPolicy, .externalMIDI)
        XCTAssertTrue(d2.syncExternalSource, "re-entry must re-sync configured source")
        XCTAssertEqual(d2.externalSourceID, "uid:A")
    }

    func testDecideSourceChangeWhileInternalThenExternalSelectsB() {
        let internalA = cfg(policy: .internalOnly, source: "uid:A")
        let internalB = cfg(policy: .internalOnly, source: "uid:B")
        let externalB = cfg(policy: .externalMIDI, source: "uid:B")

        let dSrc = MusicalTimingConfigReconciler.decide(previous: internalA, desired: internalB)
        XCTAssertTrue(dSrc.syncExternalSource)
        XCTAssertEqual(dSrc.externalSourceID, "uid:B")
        // applyTransition must NOT selectExternal while desired is internalOnly.

        let dExt = MusicalTimingConfigReconciler.decide(previous: internalB, desired: externalB)
        XCTAssertTrue(dExt.syncExternalSource)
        XCTAssertEqual(dExt.externalSourceID, "uid:B")
        XCTAssertEqual(dExt.applyTimingPolicy, .externalMIDI)
    }

    func testDecideExternalAToExternalB() {
        let a = cfg(policy: .externalMIDI, source: "uid:A")
        let b = cfg(policy: .externalMIDI, source: "uid:B")
        let d = MusicalTimingConfigReconciler.decide(previous: a, desired: b)
        XCTAssertNil(d.applyTimingPolicy)
        XCTAssertTrue(d.syncExternalSource)
        XCTAssertEqual(d.externalSourceID, "uid:B")
    }

    func testDecideIdempotentNoOp() {
        let a = cfg(policy: .externalMIDI, source: "uid:A")
        let d = MusicalTimingConfigReconciler.decide(previous: a, desired: a)
        XCTAssertFalse(d.applyProjectDefaults)
        XCTAssertNil(d.applyFreewheelSeconds)
        XCTAssertNil(d.applyTimingPolicy)
        XCTAssertFalse(d.syncExternalSource)
    }

    // MARK: - Apply transition on real MusicalEngine

    func testApplyExternalInternalExternalRestoresSelectedSource() {
        let engine = MusicalEngine()
        var preferred: String?
        let a = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(
            previous: nil, desired: a, to: engine,
            setPreferredSource: { preferred = $0 }
        )
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        XCTAssertEqual(preferred, "uid:A")

        let internalCfg = cfg(policy: .internalOnly, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(
            previous: a, desired: internalCfg, to: engine,
            setPreferredSource: { preferred = $0 }
        )
        XCTAssertEqual(engine.state.timing.selectedSourceID, MusicalEngine.internalSourceID)

        let back = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(
            previous: internalCfg, desired: back, to: engine,
            setPreferredSource: { preferred = $0 }
        )
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        XCTAssertEqual(preferred, "uid:A")
        XCTAssertEqual(engine.state.timing.timingPolicy, .externalMIDI)
    }

    func testApplyPreferredFallbackRoundTrip() {
        let engine = MusicalEngine()
        let a = cfg(policy: .externalPreferredFallback, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: nil, desired: a, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")

        let internalCfg = cfg(policy: .internalOnly, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: a, desired: internalCfg, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, MusicalEngine.internalSourceID)

        let back = cfg(policy: .externalPreferredFallback, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: internalCfg, desired: back, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
    }

    func testApplyInternalThenExternalA() {
        let engine = MusicalEngine()
        let internalCfg = cfg(policy: .internalOnly, source: nil)
        MusicalTimingConfigReconciler.applyTransition(previous: nil, desired: internalCfg, to: engine)
        let external = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: internalCfg, desired: external, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        XCTAssertEqual(engine.state.timing.timingPolicy, .externalMIDI)
    }

    func testApplyExternalToPreferredFallbackToExternal() {
        let engine = MusicalEngine()
        let ext = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: nil, desired: ext, to: engine)
        let pref = cfg(policy: .externalPreferredFallback, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: ext, desired: pref, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        let back = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: pref, desired: back, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
    }

    func testApplySourceChangeWhileInternalThenExternalSelectsB() {
        let engine = MusicalEngine()
        let extA = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: nil, desired: extA, to: engine)
        let intA = cfg(policy: .internalOnly, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(previous: extA, desired: intA, to: engine)
        let intB = cfg(policy: .internalOnly, source: "uid:B")
        MusicalTimingConfigReconciler.applyTransition(previous: intA, desired: intB, to: engine)
        // Still internal selection on engine.
        XCTAssertEqual(engine.state.timing.selectedSourceID, MusicalEngine.internalSourceID)
        let extB = cfg(policy: .externalMIDI, source: "uid:B")
        MusicalTimingConfigReconciler.applyTransition(previous: intB, desired: extB, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:B")
    }

    func testReentryRequiresReacquisitionNotStaleLock() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 8)
        )
        var preferred: String?
        let a = cfg(policy: .externalMIDI, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(
            previous: nil, desired: a, to: engine,
            setPreferredSource: { preferred = $0 }
        )
        engine.receiveTransportStart(from: "uid:A", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "uid:A", count: 24, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, "uid:A")
        XCTAssertEqual(engine.state.timing.sync, .locked)

        let internalCfg = cfg(policy: .internalOnly, source: "uid:A")
        MusicalTimingConfigReconciler.applyTransition(
            previous: a, desired: internalCfg, to: engine,
            setPreferredSource: { preferred = $0 }
        )
        MusicalTimingConfigReconciler.applyTransition(
            previous: internalCfg, desired: a, to: engine,
            setPreferredSource: { preferred = $0 }
        )
        XCTAssertEqual(preferred, "uid:A")
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        // Must reacquire — not inherit lock.
        XCTAssertNotEqual(engine.state.timing.activeSourceID, "uid:A")
        engine.receiveTransportStart(from: "uid:A", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "uid:A", count: 24, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, "uid:A")
        // Wrong source rejected after re-entry.
        let before = engine.state.timing.quarterNotePosition?.quarters
        engine.receiveClockPulse(from: "uid:WRONG", at: clock.now())
        // Active remains A (or nil if not advanced); selected stays A.
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        _ = before
    }

    func testUnrelatedDiffDoesNotChangePolicyOrSource() {
        let engine = MusicalEngine()
        let a = cfg(policy: .externalMIDI, source: "uid:A", tempo: 120)
        MusicalTimingConfigReconciler.applyTransition(previous: nil, desired: a, to: engine)
        // Tempo-only change — no policy/source sync.
        let a2 = cfg(policy: .externalMIDI, source: "uid:A", tempo: 110)
        let d = MusicalTimingConfigReconciler.decide(previous: a, desired: a2)
        XCTAssertTrue(d.applyProjectDefaults)
        XCTAssertNil(d.applyTimingPolicy)
        XCTAssertFalse(d.syncExternalSource)
        MusicalTimingConfigReconciler.applyTransition(previous: a, desired: a2, to: engine)
        XCTAssertEqual(engine.state.timing.selectedSourceID, "uid:A")
        XCTAssertEqual(engine.state.timing.timingPolicy, .externalMIDI)
    }
}
