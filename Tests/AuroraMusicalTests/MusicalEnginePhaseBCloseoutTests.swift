import AuroraMusical
import XCTest

/// Phase B deep-review closeout regressions.
final class MusicalEnginePhaseBCloseoutTests: XCTestCase {
    // MARK: P0 — external policy must stop internal advance

    func testExternalMIDIPolicyStopsInternalAdvance() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.startTransport()
        clock.advance(seconds: 0.5)
        engine.tick(now: clock.now())
        let mid = engine.state.timing.quarterNotePosition?.quarters ?? 0
        XCTAssertGreaterThan(mid, 0.4)

        var sourceChanges: [(String?, String?)] = []
        _ = engine.addTimelineObserver { ev in
            if case .sourceChanged(let from, let to) = ev {
                sourceChanges.append((from, to))
            }
        }

        engine.setTimingPolicy(.externalMIDI)
        XCTAssertNil(engine.state.timing.activeSourceID)
        XCTAssertNotEqual(engine.state.timing.activeSourceID, MusicalEngine.internalSourceID)
        XCTAssertTrue(sourceChanges.contains { $0.0 == MusicalEngine.internalSourceID && $0.1 == nil })

        let before = engine.state.timing.quarterNotePosition?.quarters ?? 0
        clock.advance(seconds: 1.0)
        engine.tick(now: clock.now())
        let after = engine.state.timing.quarterNotePosition?.quarters ?? 0
        XCTAssertEqual(before, after, accuracy: 1e-9)
    }

    func testExternalPreferredFallbackKeepsInternalActive() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.startTransport()
        engine.setTimingPolicy(.externalPreferredFallback)
        XCTAssertEqual(engine.state.timing.activeSourceID, MusicalEngine.internalSourceID)
        XCTAssertEqual(engine.state.timing.fallback, .active)
        XCTAssertEqual(engine.state.timing.sync, .fallback)

        let before = engine.state.timing.quarterNotePosition?.quarters ?? 0
        clock.advance(seconds: 0.5)
        engine.tick(now: clock.now())
        let after = engine.state.timing.quarterNotePosition?.quarters ?? 0
        XCTAssertGreaterThan(after, before)
    }

    // MARK: P0 — safety immediate while running

    func testPanicFiresSynchronouslyWhileRunningWithoutTick() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock, schedulerConfig: .init(capacity: 8, safetyReserved: 2))
        engine.setTempoBPM(120)
        engine.startTransport()

        let fired = LockedBox<Int>(0)
        engine.setScheduleFireHandler { _ in fired.mutate { $0 += 1 } }

        let beforePending = engine.pendingScheduledCount
        let panic = ScheduledMusicalAction.panicBypass()
        let r = engine.schedule(panic)
        XCTAssertEqual(r, .accepted(panic.id))
        // schedule returns with fire already delivered; no tick required
        XCTAssertEqual(fired.value, 1)
        XCTAssertEqual(engine.pendingScheduledCount, beforePending)
    }

    func testPanicFiresWhenDecorativeQueueFull() throws {
        let engine = MusicalEngine(
            clock: VirtualHostClock(),
            schedulerConfig: .init(capacity: 4, safetyReserved: 1)
        )
        engine.startTransport()
        // Fill decorative (capacity 3 decorative)
        for _ in 0..<3 {
            let a = try ScheduledMusicalAction.actionToken(
                token: UUID(),
                isSafetyCritical: false,
                targetBoundary: .nextBar
            )
            XCTAssertEqual(engine.schedule(a), .accepted(a.id))
        }
        let fired = LockedBox<Int>(0)
        engine.setScheduleFireHandler { a in
            if a.isSafetyCritical { fired.mutate { $0 += 1 } }
        }
        _ = engine.schedule(ScheduledMusicalAction.panicBypass())
        XCTAssertEqual(fired.value, 1)
    }

    func testSafetyTokenFiresImmediatelyLikePanic() throws {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.startTransport()
        let fired = LockedBox<Bool>(false)
        engine.setScheduleFireHandler { a in
            if a.isSafetyCritical { fired.mutate { $0 = true } }
        }
        let action = try ScheduledMusicalAction.actionToken(
            token: UUID(),
            isSafetyCritical: true,
            targetBoundary: .nextBar
        )
        XCTAssertTrue(action.targetBoundary.isImmediate)
        _ = engine.schedule(action)
        XCTAssertTrue(fired.value)
        XCTAssertEqual(engine.pendingScheduledCount, 0)
    }

    // MARK: P0 — per-action failure policies on stop

    func testStopAppliesPerActionFailurePolicies() throws {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.setMeter(.fourFour)
        engine.startTransport()

        let fired = LockedBox<[UUID]>([])
        engine.setScheduleFireHandler { a in fired.mutate { $0.append(a.id) } }

        let cancelA = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar, failurePolicy: .cancel
        )
        let execB = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar, failurePolicy: .executeImmediately
        )
        let holdC = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar, failurePolicy: .holdUntilTimingAvailable
        )
        XCTAssertEqual(engine.schedule(cancelA), .accepted(cancelA.id))
        XCTAssertEqual(engine.schedule(execB), .accepted(execB.id))
        XCTAssertEqual(engine.schedule(holdC), .accepted(holdC.id))
        XCTAssertEqual(engine.pendingScheduledCount, 3)

        engine.stopTransport()
        // B fires during stop
        XCTAssertEqual(fired.value, [execB.id])
        // C held
        XCTAssertEqual(engine.pendingScheduledCount, 1)
        XCTAssertTrue(engine.pendingScheduleSnapshotForDiagnostics()[0].isHeld)
        // A canceled
        XCTAssertFalse(engine.pendingScheduleSnapshotForDiagnostics().contains { $0.id == cancelA.id })

        // Continue + re-resolve holdC to next bar from current pos 0 → 4.0
        engine.continueTransport()
        XCTAssertEqual(engine.pendingScheduledCount, 1)
        XCTAssertFalse(engine.pendingScheduleSnapshotForDiagnostics()[0].isHeld)
        clock.advance(seconds: 2.02)
        engine.tick(now: clock.now())
        XCTAssertTrue(fired.value.contains(holdC.id))
    }

    // MARK: P1 — cancel returns payload

    func testCancelReturnsScheduledPayload() throws {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.startTransport()
        let token = UUID()
        let action = try ScheduledMusicalAction.actionToken(
            token: token, isSafetyCritical: false, targetBoundary: .nextBar
        )
        _ = engine.schedule(action)
        let removed = engine.cancelScheduled(id: action.id)
        XCTAssertEqual(removed?.id, action.id)
        if case .auroraActionToken(let t, _) = removed?.command {
            XCTAssertEqual(t, token)
        } else {
            XCTFail("expected token command")
        }
        XCTAssertEqual(engine.pendingScheduledCount, 0)
    }

    // MARK: P1 — song context restore

    func testSongContextDoesNotLeakPreviousSongTempo() {
        let engine = MusicalEngine(clock: VirtualHostClock(), projectDefaultTempoBPM: 120, projectDefaultMeter: .fourFour)
        engine.setShowContext(ShowMusicalContext(
            activeSongID: UUID(),
            songDefaultTempoBPM: 96,
            songDefaultMeter: .sixEight
        ))
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 96, accuracy: 0.01)
        XCTAssertEqual(engine.state.timing.meter, .sixEight)

        engine.setShowContext(ShowMusicalContext(activeSongID: UUID()))
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(engine.state.timing.tempoProvenance, .projectDefault)
        XCTAssertEqual(engine.state.timing.meter, .fourFour)
        XCTAssertEqual(engine.state.timing.meterProvenance, .projectDefault)
    }

    // MARK: P1 — SPP provenance atomic

    func testSPPSnapshotHasMidiProvenance() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("midi-a")
        var snapshots: [MusicalState] = []
        _ = engine.addStateObserver { snapshots.append($0) }
        snapshots.removeAll() // drop initial
        engine.receiveSongPosition(.must(8), from: "midi-a", at: HostTime(nanoseconds: 1_000))
        XCTAssertFalse(snapshots.isEmpty)
        for s in snapshots where (s.timing.quarterNotePosition?.quarters ?? 0) == 8 {
            XCTAssertEqual(s.timing.positionProvenance, .midiSongPosition)
        }
    }

    // MARK: P1 — large stall still advances (anchor)

    func testLargeStallStillAdvancesInternalTime() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock)
        engine.setTempoBPM(120)
        engine.startTransport()
        clock.advance(seconds: 10) // was previously discarded at >=5
        engine.tick(now: clock.now())
        // 10s * 2 q/s = 20 quarters
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? 0, 20, accuracy: 0.05)
    }

    // MARK: P1 — Codable rejects invalid meters

    func testInvalidMusicalMeterJSONFailsDecode() {
        let json = #"{"numerator":6,"denominator":8,"beatGrouping":[2,2,2]}"# // sum 6 ok actually
        // sum mismatch
        let bad = #"{"numerator":6,"denominator":8,"beatGrouping":[3,4]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(MusicalMeter.self, from: Data(bad.utf8)))
        let badDen = #"{"numerator":4,"denominator":3,"beatGrouping":[1,1,1,1]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(MusicalMeter.self, from: Data(badDen.utf8)))
        _ = json
    }

    func testInvalidDurationJSONFailsDecode() {
        let bad = #"{"unit":"quarter","count":-1,"dotted":false,"triplet":false}"#
        XCTAssertThrowsError(try JSONDecoder().decode(MusicalDuration.self, from: Data(bad.utf8)))
        let both = #"{"unit":"quarter","count":1,"dotted":true,"triplet":true}"#
        XCTAssertThrowsError(try JSONDecoder().decode(MusicalDuration.self, from: Data(both.utf8)))
    }

    // MARK: P2 — transport idempotency

    func testStopWhileStoppedIsIdempotent() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        var stops = 0
        _ = engine.addTimelineObserver { if case .stopped = $0 { stops += 1 } }
        engine.startTransport()
        engine.stopTransport()
        engine.stopTransport()
        XCTAssertEqual(stops, 1)
    }

    func testContinueWhileRunningIsIdempotent() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        var continues = 0
        _ = engine.addTimelineObserver { if case .continued = $0 { continues += 1 } }
        engine.startTransport()
        engine.continueTransport()
        XCTAssertEqual(continues, 0)
    }

    // MARK: P2 — VirtualHostClock

    func testVirtualClockRejectsNegativeAdvance() {
        let clock = VirtualHostClock(start: HostTime(nanoseconds: 1000))
        clock.advance(seconds: -1)
        XCTAssertEqual(clock.now().nanoseconds, 1000)
        clock.advance(seconds: .nan)
        XCTAssertEqual(clock.now().nanoseconds, 1000)
    }
}
