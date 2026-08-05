import AuroraMIDI
import XCTest

final class MIDIMessageParserTests: XCTestCase {
    func testNoteOn() {
        let events = MIDIMessageParser.parse(bytes: [0x90, 60, 100], sourceID: "t")
        XCTAssertEqual(events.count, 1)
        guard case .noteOn(let ch, let n, let v, let s) = events[0] else {
            return XCTFail("expected noteOn")
        }
        XCTAssertEqual(ch, 0)
        XCTAssertEqual(n, 60)
        XCTAssertEqual(v, 100)
        XCTAssertEqual(s, "t")
    }

    func testNoteOnZeroVelocityIsNoteOff() {
        let events = MIDIMessageParser.parse(bytes: [0x90, 60, 0], sourceID: "t")
        guard case .noteOff = events[0] else {
            return XCTFail("expected noteOff")
        }
    }

    func testControlChange() {
        let events = MIDIMessageParser.parse(bytes: [0xB0, 7, 64], sourceID: "t")
        guard case .controlChange(let ch, let c, let v, _) = events[0] else {
            return XCTFail("expected CC")
        }
        XCTAssertEqual(ch, 0)
        XCTAssertEqual(c, 7)
        XCTAssertEqual(v, 64)
    }

    func testProgramChange() {
        let events = MIDIMessageParser.parse(bytes: [0xC0, 12], sourceID: "t")
        guard case .programChange(_, let p, _) = events[0] else {
            return XCTFail("expected PC")
        }
        XCTAssertEqual(p, 12)
    }

    func testRunningStatus() {
        let events = MIDIMessageParser.parse(bytes: [0x90, 60, 100, 61, 90], sourceID: "t")
        XCTAssertEqual(events.count, 2)
    }
}
