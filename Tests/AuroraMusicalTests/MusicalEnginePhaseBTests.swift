import AuroraMusical
import XCTest

final class MusicalEnginePhaseBTests: XCTestCase {
    func testInternalTransportAdvancesAtBPM() {
        let clock = VirtualHostClock(start: HostTime(nanoseconds: 0))
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.startTransport()
        // 120 BPM → 2 quarters/sec → 0.5s = 1 quarter
        clock.advance(seconds: 0.5)
        engine.tick(now: clock.now())
        let pos = engine.state.timing.quarterNotePosition?.quarters ?? -1
        XCTAssertEqual(pos, 1.0, accuracy: 0.02)
        XCTAssertEqual(engine.state.timing.transport, .running)
        XCTAssertEqual(engine.state.timing.sync, .internalRunning)
    }

    func testStopDoesNotAdvance() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.startTransport()
        engine.stopTransport()
        clock.advance(seconds: 1)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(engine.state.timing.transport, .stopped)
    }

    func testTapTempoUpdatesInternalBPM() {
        let clock = VirtualHostClock(start: HostTime(nanoseconds: 0))
        let engine = MusicalEngine(clock: clock)
        _ = engine.tapTempo(at: HostTime(nanoseconds: 0))
        clock.advance(seconds: 0.5)
        let bpm = engine.tapTempo(at: clock.now())
        XCTAssertNotNil(bpm)
        XCTAssertEqual(bpm!, 120, accuracy: 1)
        XCTAssertEqual(engine.state.timing.tempoProvenance, .tapTempo)
    }

    func testShowContextDoesNotComeFromTimingProvider() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        let song = UUID()
        let section = UUID()
        engine.setShowContext(ShowMusicalContext(
            activeSongID: song,
            activeSectionID: section,
            songDefaultTempoBPM: 96,
            songDefaultMeter: .sixEight
        ))
        XCTAssertEqual(engine.state.context.activeSongID, song)
        XCTAssertEqual(engine.state.context.activeSectionID, section)
        // Soft-applied song defaults when provenance was project default
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 96, accuracy: 0.01)
        XCTAssertEqual(engine.state.timing.meter, .sixEight)
        XCTAssertEqual(engine.state.timing.meterProvenance, .songMetadata)
    }

    func testScheduleNextMetricalBeatFiresInSixEight() throws {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock, schedulerConfig: .init(capacity: 32, safetyReserved: 4))
        engine.setTempoBPM(120)
        engine.setMeter(.sixEight)
        engine.startTransport()

        let fired = LockedBox<[ScheduledMusicalAction]>([])
        engine.setScheduleFireHandler { action in
            fired.mutate { $0.append(action) }
        }

        let action = try ScheduledMusicalAction.actionToken(
            token: UUID(),
            isSafetyCritical: false,
            targetBoundary: .nextMetricalBeat
        )
        let result = engine.schedule(action)
        XCTAssertEqual(result, .accepted(action.id))
        XCTAssertTrue(fired.value.isEmpty)

        // 120 BPM, need 1.5 quarters for first 6/8 beat → 0.75 seconds
        clock.advance(seconds: 0.76)
        engine.tick(now: clock.now())
        XCTAssertEqual(fired.value.count, 1)
        XCTAssertEqual(fired.value.first?.id, action.id)
    }

    func testSchedulerRejectsNewestWhenFull() throws {
        let scheduler = MusicalScheduler(config: .init(capacity: 4, safetyReserved: 1))
        for _ in 0..<3 {
            let a = try ScheduledMusicalAction.actionToken(
                token: UUID(),
                isSafetyCritical: false,
                targetBoundary: .nextBar
            )
            XCTAssertEqual(scheduler.enqueue(a, targetPosition: .must(4)), .accepted(a.id))
        }
        // decorative capacity = 3; 4th decorative rejects
        let extra = try ScheduledMusicalAction.actionToken(
            token: UUID(),
            isSafetyCritical: false,
            targetBoundary: .nextBar
        )
        XCTAssertEqual(scheduler.enqueue(extra, targetPosition: .must(4)), .rejectedQueueFull)
        // safety must never be queued (engine path only)
        let panic = ScheduledMusicalAction.panicBypass()
        XCTAssertEqual(scheduler.enqueue(panic, targetPosition: .must(0)), .rejectedInvalid)
        XCTAssertEqual(scheduler.pendingCount, 3)
    }

    func testPanicFiresImmediatelyEvenWhenStopped() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        let fired = LockedBox<[ScheduledMusicalAction]>([])
        engine.setScheduleFireHandler { a in fired.mutate { $0.append(a) } }
        let panic = ScheduledMusicalAction.panicBypass()
        let r = engine.schedule(panic)
        XCTAssertEqual(r, .accepted(panic.id))
        XCTAssertEqual(fired.value.count, 1)
        XCTAssertTrue(fired.value[0].isSafetyCritical)
    }

    func testTimelineStartStopContinue() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        var events: [MusicalTimelineEvent] = []
        _ = engine.addTimelineObserver { events.append($0) }
        engine.startTransport()
        engine.stopTransport()
        engine.continueTransport()
        XCTAssertTrue(events.contains(.started))
        XCTAssertTrue(events.contains(.stopped))
        XCTAssertTrue(events.contains(.continued))
    }

    func testSeekEmitsPositionJumped() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        var jumped = false
        _ = engine.addTimelineObserver { ev in
            if case .positionJumped = ev { jumped = true }
        }
        engine.seek(to: .must(8))
        XCTAssertTrue(jumped)
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? 0, 8, accuracy: 1e-9)
    }

    func testEffectsConsumerContract() {
        // Generic consumer: tempo, phase, next boundary, transport, sync, discontinuities, schedule
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(100)
        engine.setMeter(.fourFour)
        engine.startTransport()

        let s = engine.state
        XCTAssertNotNil(s.timing.tempoBPM)
        XCTAssertNotNil(s.timing.quarterNotePhase)
        XCTAssertEqual(s.timing.transport, .running)
        XCTAssertNotNil(s.timing.sync)
        XCTAssertNotNil(s.timing.activeSourceID)

        let next = engine.nextBoundary(.nextMetricalBeat)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!.quarters, 0)

        var sawTimeline = false
        _ = engine.addTimelineObserver { _ in sawTimeline = true }
        engine.seek(to: .must(4))
        XCTAssertTrue(sawTimeline)

        // Under internal source, tick advances identically regardless of MIDI
        clock.advance(seconds: 0.1)
        engine.tick(now: clock.now())
        XCTAssertGreaterThan(engine.state.timing.quarterNotePosition?.quarters ?? 0, 4)
    }

    func testHeldScheduleReleasesOnStartAndFiresAtBoundary() throws {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.setMeter(.fourFour)
        let fired = LockedBox<[UUID]>([])
        engine.setScheduleFireHandler { a in fired.mutate { $0.append(a.id) } }

        let action = try ScheduledMusicalAction.actionToken(
            token: UUID(),
            isSafetyCritical: false,
            targetBoundary: .nextBar,
            failurePolicy: .holdUntilTimingAvailable
        )
        // transport stopped → hold
        XCTAssertEqual(engine.schedule(action), .accepted(action.id))
        XCTAssertTrue(fired.value.isEmpty)
        engine.startTransport()
        // held re-resolved to next bar (4.0); not due yet
        XCTAssertTrue(fired.value.isEmpty)
        // 4 quarters at 120 BPM = 2 seconds
        clock.advance(seconds: 2.02)
        engine.tick(now: clock.now())
        XCTAssertEqual(fired.value, [action.id])
    }

    func testCompoundMeterBarBeatDuringRun() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.setMeter(.sixEight)
        engine.startTransport()
        // 0.25s = 0.5 quarter → still beat 1
        clock.advance(seconds: 0.25)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.state.timing.barBeat?.beatIndexInBar, 1)
        // 0.8s total ≈ 1.6 quarters → beat 2 in 6/8
        clock.advance(seconds: 0.55)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.state.timing.barBeat?.beatIndexInBar, 2)
    }
}

/// Tiny mutex box for fire-handler tests.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        body(&_value)
        lock.unlock()
    }
}
