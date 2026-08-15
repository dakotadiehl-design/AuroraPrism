import AuroraMIDI
import XCTest

final class MIDIOutputEncoderTests: XCTestCase {
    func testNoteOnEncoding() {
        XCTAssertEqual(MIDIMessageEncoder.noteOn(channel: 0, note: 60, velocity: 100), [0x90, 60, 100])
        XCTAssertEqual(MIDIMessageEncoder.noteOn(channel: 9, note: 36, velocity: 127), [0x99, 36, 127])
    }

    func testCCEncoding() {
        XCTAssertEqual(MIDIMessageEncoder.controlChange(channel: 0, controller: 7, value: 64), [0xB0, 7, 64])
    }
}
