import AuroraMIDI
import AuroraMusical
import XCTest

final class HostTimeLegacySecondsTests: XCTestCase {
    func testFromLegacyMonotonicSecondsRoundTrip() {
        let seconds: TimeInterval = 12.5
        let ht = HostTime.fromLegacyMonotonicSeconds(seconds)
        XCTAssertNotNil(ht)
        XCTAssertEqual(ht!.nanoseconds, 12_500_000_000)
        XCTAssertEqual(ht!.seconds, seconds, accuracy: 1e-9)
    }

    func testFromLegacyRejectsInvalid() {
        XCTAssertNil(HostTime.fromLegacyMonotonicSeconds(-1))
        XCTAssertNil(HostTime.fromLegacyMonotonicSeconds(.nan))
        XCTAssertNil(HostTime.fromLegacyMonotonicSeconds(.infinity))
    }

    func testMIDIEventTimestampPreservedIntoHostTime() {
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "pad", timestamp: 3.25)
        let ht = HostTime.fromLegacyMonotonicSeconds(event.timestamp)
        XCTAssertEqual(ht?.nanoseconds, 3_250_000_000)
        // Distinct batch timestamps remain distinct
        let e2 = MIDIEvent.noteOff(channel: 0, note: 36, velocity: 0, sourceID: "pad", timestamp: 3.30)
        let ht2 = HostTime.fromLegacyMonotonicSeconds(e2.timestamp)
        XCTAssertNotEqual(ht?.nanoseconds, ht2?.nanoseconds)
    }
}
