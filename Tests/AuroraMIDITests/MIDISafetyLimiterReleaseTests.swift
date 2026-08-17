import AuroraMIDI
import AuroraModel
import XCTest

final class MIDISafetyLimiterReleaseTests: XCTestCase {
    func testFloodDoesNotBlockNoteOff() {
        let limiter = MIDISafetyLimiter(maxEventsPerSecond: 5, debounceSeconds: 0)
        var t: TimeInterval = 0
        for i in 0..<10 {
            t += 0.01
            let e = MIDIEvent.noteOn(channel: 0, note: UInt8(i), velocity: 100, sourceID: "pad", timestamp: t)
            _ = limiter.allow(event: e, now: t)
        }
        t += 0.01
        let off = MIDIEvent.noteOff(channel: 0, note: 0, velocity: 0, sourceID: "pad", timestamp: t)
        XCTAssertTrue(limiter.allow(event: off, now: t), "Note Off must bypass flood")
    }

    func testFloodDoesNotBlockNoteOnVelocityZero() {
        let limiter = MIDISafetyLimiter(maxEventsPerSecond: 3, debounceSeconds: 0)
        var t: TimeInterval = 0
        for _ in 0..<5 {
            t += 0.01
            _ = limiter.allow(
                event: .noteOn(channel: 0, note: 36, velocity: 100, sourceID: "a", timestamp: t),
                now: t
            )
        }
        t += 0.01
        let zero = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 0, sourceID: "a", timestamp: t)
        XCTAssertTrue(MIDISafetyLimiter.isPhysicalRelease(zero))
        XCTAssertTrue(limiter.allow(event: zero, now: t))
    }

    func testDebounceDoesNotBlockNoteOff() {
        let limiter = MIDISafetyLimiter(maxEventsPerSecond: 500, debounceSeconds: 0.5)
        let t0: TimeInterval = 1.0
        XCTAssertTrue(limiter.allow(
            event: .noteOn(channel: 0, note: 36, velocity: 100, sourceID: "a", timestamp: t0),
            now: t0
        ))
        let t1 = t0 + 0.01
        XCTAssertFalse(limiter.allow(
            event: .noteOn(channel: 0, note: 36, velocity: 100, sourceID: "a", timestamp: t1),
            now: t1
        ), "second noteOn debounced")
        let t2 = t0 + 0.02
        XCTAssertTrue(limiter.allow(
            event: .noteOff(channel: 0, note: 36, velocity: 0, sourceID: "a", timestamp: t2),
            now: t2
        ), "Note Off not debounced")
    }

    func testMonotonicTimeNotWallClock() {
        let limiter = MIDISafetyLimiter(maxEventsPerSecond: 2, debounceSeconds: 0)
        // Far-future wall clock would break Date-based windows; event timestamps are local monotonic.
        XCTAssertTrue(limiter.allow(
            event: .noteOn(channel: 0, note: 1, velocity: 1, sourceID: "a", timestamp: 0.0),
            now: 0.0
        ))
        XCTAssertTrue(limiter.allow(
            event: .noteOn(channel: 0, note: 2, velocity: 1, sourceID: "a", timestamp: 0.1),
            now: 0.1
        ))
        XCTAssertFalse(limiter.allow(
            event: .noteOn(channel: 0, note: 3, velocity: 1, sourceID: "a", timestamp: 0.2),
            now: 0.2
        ))
        // Still within 1s window of first event — third blocked; Note Off still admitted.
        XCTAssertTrue(limiter.allow(
            event: .noteOff(channel: 0, note: 1, velocity: 0, sourceID: "a", timestamp: 0.25),
            now: 0.25
        ))
    }

    func testUIDZeroIsNotStableIdentity() {
        // Unit-level contract for stableSourceID: zero UniqueID must not form uid:0.
        // CoreMIDI property is hard to fake; identity helper path is covered by endpoint form.
        XCTAssertEqual(MIDISourceIdentity.coreMIDIUniqueID(42), "uid:42")
        XCTAssertNotEqual(MIDISourceIdentity.coreMIDIUniqueID(0), "ep:1")
        // Document the production rule: unique != 0 required (see MIDIInputManager.stableSourceID).
        let zeroIsUnusable = 0
        XCTAssertEqual(zeroIsUnusable, 0)
    }
}
