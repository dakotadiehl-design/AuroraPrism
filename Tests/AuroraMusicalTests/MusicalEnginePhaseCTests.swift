import AuroraMusical
import XCTest

/// Phase C: external MIDI Clock lock, freewheel, fallback, Effects consumer under external.
final class MusicalEnginePhaseCTests: XCTestCase {
    /// 24 PPQN at `bpm` → pulse interval seconds.
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

    func testClockEstimatorLocksAt120BPM() {
        var est = ClockEstimator(config: .init(lockPulseCount: 12, freewheelSeconds: 2))
        let interval = pulseInterval(bpm: 120)
        var t: UInt64 = 0
        for _ in 0..<20 {
            t += UInt64(interval * 1_000_000_000)
            est.receivePulse(at: HostTime(nanoseconds: t))
        }
        XCTAssertEqual(est.sync, .locked)
        XCTAssertEqual(est.tempoBPM ?? 0, 120, accuracy: 2)
    }

    func testExternalMIDILocksAndAdvancesPosition() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 8, freewheelSeconds: 2)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("drum")
        // Start transport via MIDI Start
        engine.receiveTransportStart(from: "drum", at: clock.now())
        XCTAssertEqual(engine.state.timing.transport, .running)

        // Acquire lock (~8 pulses) then advance a full quarter (24 pulses while locked)
        feedPulses(engine: engine, clock: clock, source: "drum", count: 40, bpm: 120)
        XCTAssertEqual(engine.state.timing.activeSourceID, "drum")
        XCTAssertEqual(engine.state.timing.sync, .locked)
        // Position advances only while locked; expect roughly ≥ 1 quarter after 40 pulses
        XCTAssertGreaterThanOrEqual(engine.state.timing.quarterNotePosition?.quarters ?? 0, 0.9)
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 120, accuracy: 5)
        XCTAssertEqual(engine.state.timing.tempoProvenance, .midiClock)
    }

    func testUnselectedSourcePulsesIgnored() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock, clockEstimatorConfig: .init(lockPulseCount: 4))
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("a")
        engine.receiveTransportStart(from: "a", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "b", count: 30, bpm: 120)
        XCTAssertNotEqual(engine.state.timing.activeSourceID, "b")
        // Position should not advance from b
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? -1, 0, accuracy: 1e-9)
    }

    func testFreewheelThenPreferredFallback() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(
                lockPulseCount: 6,
                dropoutIntervalMultiplier: 3,
                freewheelSeconds: 0.5
            )
        )
        engine.setTimingPolicy(.externalPreferredFallback)
        engine.selectExternalTimingSource("drum")
        engine.receiveTransportStart(from: "drum", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "drum", count: 24, bpm: 120)
        XCTAssertEqual(engine.state.timing.sync, .locked)
        XCTAssertEqual(engine.state.timing.activeSourceID, "drum")

        let posAfterLock = engine.state.timing.quarterNotePosition?.quarters ?? 0

        // Stop pulses; advance past dropout + freewheel
        // At 120 BPM pulse interval ~20.8ms; 3x ≈ 62ms to freewheel; freewheel 0.5s to lost
        clock.advance(seconds: 0.15)
        engine.tick(now: clock.now())
        // May be freewheeling
        clock.advance(seconds: 0.6)
        engine.tick(now: clock.now())

        // Lost → fallback to internal
        XCTAssertEqual(engine.state.timing.activeSourceID, MusicalEngine.internalSourceID)
        XCTAssertEqual(engine.state.timing.fallback, .active)
        XCTAssertEqual(engine.state.timing.sync, .fallback)
        // Freewheel should have advanced position somewhat
        XCTAssertGreaterThan(engine.state.timing.quarterNotePosition?.quarters ?? 0, posAfterLock)
    }

    func testStrictExternalLostClearsAuthority() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 6, freewheelSeconds: 0.3)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("drum")
        engine.receiveTransportStart(from: "drum", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "drum", count: 20, bpm: 120)
        XCTAssertEqual(engine.state.timing.sync, .locked)

        // dropout + freewheel 0.3s — 1s is plenty at 120 BPM
        clock.advance(seconds: 1.0)
        engine.tick(now: clock.now())
        XCTAssertNil(engine.state.timing.activeSourceID)
        XCTAssertTrue(
            engine.state.timing.sync == .lost || engine.state.timing.activeSourceID == nil
        )
    }

    func testEffectsConsumerWorksUnderExternalClock() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(
            clock: clock,
            clockEstimatorConfig: .init(lockPulseCount: 8)
        )
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("clk")
        engine.setMeter(.fourFour)
        engine.receiveTransportStart(from: "clk", at: clock.now())
        feedPulses(engine: engine, clock: clock, source: "clk", count: 48, bpm: 100)

        let s = engine.state
        XCTAssertNotNil(s.timing.tempoBPM)
        XCTAssertEqual(s.timing.activeSourceID, "clk")
        XCTAssertEqual(s.timing.sync, .locked)
        XCTAssertNotNil(s.timing.quarterNotePosition)
        let next = engine.nextBoundary(.nextMetricalBeat)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!.quarters, s.timing.quarterNotePosition!.quarters - 1e-9)
    }

    func testSPPSeekUnderExternal() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("clk")
        // 16 sixteenths = 4 quarters
        engine.receiveSongPosition(
            QuarterNotePosition.fromMIDISongPositionSixteenths(16),
            from: "clk",
            at: clock.now()
        )
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(engine.state.timing.positionProvenance, .midiSongPosition)
    }

    func testStartStopContinueFromSelectedSource() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("clk")
        engine.receiveTransportStart(from: "clk", at: clock.now())
        XCTAssertEqual(engine.state.timing.transport, .running)
        engine.receiveTransportStop(from: "clk", at: clock.now())
        XCTAssertEqual(engine.state.timing.transport, .stopped)
        engine.receiveTransportContinue(from: "clk", at: clock.now())
        XCTAssertEqual(engine.state.timing.transport, .running)
    }
}
