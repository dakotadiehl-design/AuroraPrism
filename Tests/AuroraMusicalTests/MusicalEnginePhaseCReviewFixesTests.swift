import AuroraMusical
import XCTest

final class MusicalEnginePhaseCReviewFixesTests: XCTestCase {
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

    func testPreferredFallbackOnePulseDoesNotStealAuthority() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            projectDefaultTempoBPM: 120,
            clockEstimatorConfig: .init(lockPulseCount: 12, acquisitionTimeoutSeconds: 0.5)
        )
        engine.setTimingPolicy(.externalPreferredFallback)
        engine.selectExternalTimingSource("drum")
        engine.startTransport()
        let pos0 = engine.state.timing.quarterNotePosition?.quarters ?? 0

        // Exactly one F8
        clock.advance(seconds: pulseInterval(bpm: 120))
        engine.receiveClockPulse(from: "drum", at: clock.now())
        XCTAssertEqual(engine.state.timing.activeSourceID, MusicalEngine.internalSourceID)
        XCTAssertNotEqual(engine.state.timing.sync, .locked)

        // Internal still advances
        clock.advance(seconds: 0.5)
        engine.tick(now: clock.now())
        XCTAssertGreaterThan(engine.state.timing.quarterNotePosition?.quarters ?? 0, pos0)
    }

    func testPreferredFallbackHandoffOnlyOnLock() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 8)
        )
        engine.setTimingPolicy(.externalPreferredFallback)
        engine.selectExternalTimingSource("drum")
        engine.receiveTransportStart(from: "drum", at: clock.now())
        // Not enough for lock
        feedPulses(engine: engine, clock: clock, source: "drum", count: 4, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, MusicalEngine.internalSourceID)

        feedPulses(engine: engine, clock: clock, source: "drum", count: 20, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, "drum")
        XCTAssertEqual(engine.state.timing.sync, .locked)
    }

    func testFirstPulseAfterLossDoesNotInstantRelock() {
        var est = ClockEstimator(config: .init(lockPulseCount: 8, freewheelSeconds: 0.2))
        let dt = pulseInterval(bpm: 120)
        var t: UInt64 = 0
        for _ in 0..<20 {
            t += UInt64(dt * 1e9)
            est.receivePulse(at: HostTime(nanoseconds: t))
        }
        XCTAssertEqual(est.sync, .locked)
        // Long silence past dropout + freewheel
        t += UInt64(2.0 * 1e9)
        est.evaluateDropout(at: HostTime(nanoseconds: t))
        XCTAssertEqual(est.sync, .lost)
        // First return pulse after huge gap must not instant-relock
        t += UInt64(dt * 1e9)
        est.receivePulse(at: HostTime(nanoseconds: t))
        XCTAssertNotEqual(est.sync, .locked)
    }

    func testSourceReplacementResetsEstimator() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 6)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("a")
        engine.receiveTransportStart(from: "a", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "a", count: 30, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, "a")
        XCTAssertEqual(engine.state.timing.sync, .locked)

        engine.selectExternalTimingSource("b")
        XCTAssertNil(engine.state.timing.activeSourceID)
        // A pulses ignored
        feedPulses(engine: engine, clock: clock, source: "a", count: 10, bpm: 120)
        XCTAssertNil(engine.state.timing.activeSourceID)
        // B must acquire independently at 90 BPM
        feedPulses(engine: engine, clock: clock, source: "b", count: 30, bpm: 90)
        XCTAssertEqual(engine.state.timing.activeSourceID, "b")
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 90, accuracy: 8)
    }

    func testStartAlignsPhaseWithPosition() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 6)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("clk")
        // Pollute estimator with prior clock
        feedPulses(engine: engine, clock: clock, source: "clk", count: 17, bpm: 120)
        engine.receiveTransportStart(from: "clk", at: clock.now())
        // Need re-lock after start
        feedPulses(engine: engine, clock: clock, source: "clk", count: 20, bpm: 120)
        let pos = engine.state.timing.quarterNotePosition?.quarters ?? 0
        let phase = engine.state.timing.quarterNotePhase ?? -1
        let expectedPhase = pos - floor(pos)
        XCTAssertEqual(phase, expectedPhase, accuracy: 0.02)
    }

    func testSPPAlignsPhase() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 6)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("clk")
        engine.receiveTransportStart(from: "clk", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "clk", count: 20, bpm: 120)
        // SPP to sixteenth 1 → 0.25 quarters
        engine.receiveSongPosition(
            QuarterNotePosition.fromMIDISongPositionSixteenths(1),
            from: "clk",
            at: clock.now()
        )
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertEqual(engine.state.timing.quarterNotePhase ?? 0, 0.25, accuracy: 0.02)
        XCTAssertTrue(engine.state.timing.activeSourceCapabilities.suppliesSongPosition)
    }

    func testPreferredFallbackRestoresSongTempo() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            projectDefaultTempoBPM: 120,
            clockEstimatorConfig: .init(lockPulseCount: 6, freewheelSeconds: 0.25)
        )
        engine.setShowContext(ShowMusicalContext(songDefaultTempoBPM: 96))
        engine.setTimingPolicy(.externalPreferredFallback)
        engine.selectExternalTimingSource("drum")
        engine.receiveTransportStart(from: "drum", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "drum", count: 30, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, "drum")
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 120, accuracy: 8)

        // Force loss: dropout + freewheel 0.25s
        clock.advance(seconds: 2.0)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.state.timing.activeSourceID, MusicalEngine.internalSourceID)
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 96, accuracy: 0.5)
        XCTAssertEqual(engine.state.timing.tempoProvenance, .fallback)
    }

    func testHeldWorkReleasesOnFirstExternalLock() throws {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 6)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("clk")
        // Transport not required for hold schedule when no authority
        let action = try ScheduledMusicalAction.actionToken(
            token: UUID(),
            isSafetyCritical: false,
            targetBoundary: .nextBar,
            failurePolicy: .holdUntilTimingAvailable
        )
        XCTAssertEqual(engine.schedule(action), .accepted(action.id))
        XCTAssertTrue(engine.pendingScheduleSnapshotForDiagnostics()[0].isHeld)

        engine.receiveTransportStart(from: "clk", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "clk", count: 30, bpm: 120)
        XCTAssertEqual(engine.state.timing.sync, .locked)
        let pending = engine.pendingScheduleSnapshotForDiagnostics()
        XCTAssertEqual(pending.count, 1)
        XCTAssertFalse(pending[0].isHeld)
        XCTAssertNotNil(pending[0].targetPosition)
    }

    func testFreewheelDurationMeasuredAfterDropout() {
        var est = ClockEstimator(config: .init(
            lockPulseCount: 6,
            dropoutIntervalMultiplier: 3,
            freewheelSeconds: 0.4
        ))
        let dt = pulseInterval(bpm: 120)
        var t: UInt64 = 0
        for _ in 0..<15 {
            t += UInt64(dt * 1e9)
            est.receivePulse(at: HostTime(nanoseconds: t))
        }
        XCTAssertEqual(est.sync, .locked)
        // Just past dropout (~3 intervals ≈ 62ms) → freewheel
        t += UInt64(0.08 * 1e9)
        est.evaluateDropout(at: HostTime(nanoseconds: t))
        XCTAssertEqual(est.sync, .freewheeling)
        // Mid freewheel window (0.2s of freewheelSeconds 0.4)
        t += UInt64(0.2 * 1e9)
        est.evaluateDropout(at: HostTime(nanoseconds: t))
        XCTAssertEqual(est.sync, .freewheeling)
        // Past freewheelSeconds after dropout threshold
        t += UInt64(0.3 * 1e9)
        est.evaluateDropout(at: HostTime(nanoseconds: t))
        XCTAssertEqual(est.sync, .lost)
    }
}
