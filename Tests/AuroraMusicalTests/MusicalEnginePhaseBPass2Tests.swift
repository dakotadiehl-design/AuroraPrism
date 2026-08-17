import AuroraMusical
import XCTest

final class MusicalEnginePhaseBPass2Tests: XCTestCase {
    func testSchedulerRejectsSafetyEnqueue() {
        let scheduler = MusicalScheduler(config: .init(capacity: 8, safetyReserved: 2))
        let panic = ScheduledMusicalAction.panicBypass()
        XCTAssertEqual(
            scheduler.enqueue(panic, targetPosition: .must(128)),
            .rejectedInvalid
        )
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testSchedulerRejectsDuplicateIDs() throws {
        let scheduler = MusicalScheduler()
        let id = UUID()
        let a = try ScheduledMusicalAction.actionToken(
            id: id, token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar
        )
        let b = try ScheduledMusicalAction.actionToken(
            id: id, token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar
        )
        XCTAssertEqual(scheduler.enqueue(a, targetPosition: .must(4)), .accepted(id))
        XCTAssertEqual(scheduler.enqueue(b, targetPosition: .must(8)), .rejectedInvalid)
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testImmediateFiresWhenStoppedDefaultCancelPolicy() throws {
        let engine = MusicalEngine(clock: VirtualHostClock())
        XCTAssertEqual(engine.state.timing.transport, .stopped)
        let fired = LockedBox<Int>(0)
        engine.setScheduleFireHandler { _ in fired.mutate { $0 += 1 } }
        let action = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .immediate
        )
        // default failurePolicy is .cancel — must still fire for immediate
        XCTAssertEqual(engine.schedule(action), .accepted(action.id))
        XCTAssertEqual(fired.value, 1)
        XCTAssertEqual(engine.pendingScheduledCount, 0)
    }

    func testImmediateFiresUnderStrictExternalNoSource() throws {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.setTimingPolicy(.externalMIDI)
        let fired = LockedBox<Int>(0)
        engine.setScheduleFireHandler { _ in fired.mutate { $0 += 1 } }
        let action = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .immediate
        )
        XCTAssertEqual(engine.schedule(action), .accepted(action.id))
        XCTAssertEqual(fired.value, 1)
    }

    func testPolicySwitchToExternalAppliesFailurePolicies() throws {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.setTempoBPM(120)
        engine.startTransport()
        let fired = LockedBox<[UUID]>([])
        let canceled = LockedBox<[UUID]>([])
        engine.setScheduleFireHandler { a in fired.mutate { $0.append(a.id) } }
        engine.setScheduleCancelHandler { list in canceled.mutate { $0.append(contentsOf: list.map(\.id)) } }

        let a = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar, failurePolicy: .cancel
        )
        let b = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar, failurePolicy: .executeImmediately
        )
        let c = try ScheduledMusicalAction.actionToken(
            token: UUID(), isSafetyCritical: false, targetBoundary: .nextBar, failurePolicy: .holdUntilTimingAvailable
        )
        _ = engine.schedule(a)
        _ = engine.schedule(b)
        _ = engine.schedule(c)
        XCTAssertEqual(engine.pendingScheduledCount, 3)

        engine.setTimingPolicy(.externalMIDI)
        XCTAssertEqual(fired.value, [b.id])
        XCTAssertEqual(canceled.value, [a.id])
        XCTAssertEqual(engine.pendingScheduledCount, 1)
        XCTAssertTrue(engine.pendingScheduleSnapshotForDiagnostics()[0].isHeld)
        XCTAssertEqual(engine.pendingScheduleSnapshotForDiagnostics()[0].id, c.id)

        // Restore internal — hold re-resolves
        engine.setTimingPolicy(.internalOnly)
        XCTAssertEqual(engine.pendingScheduledCount, 1)
        XCTAssertFalse(engine.pendingScheduleSnapshotForDiagnostics()[0].isHeld)
    }

    func testInternalOnlyRejectsExternalTransportAndSPP() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.startTransport()
        let pos = engine.state.timing.quarterNotePosition?.quarters ?? 0
        engine.receiveTransportStop(from: "rogue-midi", at: HostTime(nanoseconds: 1))
        XCTAssertEqual(engine.state.timing.transport, .running)
        engine.receiveSongPosition(.must(99), from: "rogue-midi", at: HostTime(nanoseconds: 2))
        XCTAssertEqual(engine.state.timing.quarterNotePosition?.quarters ?? -1, pos, accuracy: 1e-9)
    }

    func testSelectedSourceAdmission() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.setTimingPolicy(.externalMIDI)
        engine.selectExternalTimingSource("midi-a")
        // Not running yet; stop should no-op if already stopped — use start from A
        engine.receiveTransportStart(from: "midi-b", at: HostTime(nanoseconds: 1))
        XCTAssertEqual(engine.state.timing.transport, .stopped)
        engine.receiveTransportStart(from: "midi-a", at: HostTime(nanoseconds: 2))
        XCTAssertEqual(engine.state.timing.transport, .running)
    }

    func testProjectDefaultTempoReanchorsWhileRunning() {
        let clock = VirtualHostClock()
        let engine = MusicalEngine(clock: clock, projectDefaultTempoBPM: 120, projectDefaultMeter: .fourFour)
        engine.startTransport()
        // Still projectDefault provenance
        engine.setProjectDefaults(tempoBPM: 60, meter: .fourFour)
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 60, accuracy: 0.01)
        let atChange = engine.state.timing.quarterNotePosition?.quarters ?? 0
        clock.advance(seconds: 1.0)
        engine.tick(now: clock.now())
        let advanced = (engine.state.timing.quarterNotePosition?.quarters ?? 0) - atChange
        // 60 BPM => 1 quarter per second
        XCTAssertEqual(advanced, 1.0, accuracy: 0.05)
    }

    func testProjectDefaultDoesNotOverrideUserTempo() {
        let engine = MusicalEngine(clock: VirtualHostClock())
        engine.setTempoBPM(140, provenance: .user)
        engine.setProjectDefaults(tempoBPM: 60, meter: .fourFour)
        XCTAssertEqual(engine.state.timing.tempoBPM ?? 0, 140, accuracy: 0.01)
        XCTAssertEqual(engine.state.timing.tempoProvenance, .user)
    }
}
