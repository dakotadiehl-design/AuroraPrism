import AuroraMIDI
import XCTest

final class MIDIStreamParserTests: XCTestCase {
    func testRunningStatusSurvivesAcrossParseCalls() {
        let parser = MIDIStreamParser()
        // Full note-on establishes running status
        let first = parser.parse(bytes: [0x90, 60, 100], sourceID: "t")
        XCTAssertEqual(first.count, 1)
        // Second packet uses running status (no status byte)
        let second = parser.parse(bytes: [61, 80], sourceID: "t")
        XCTAssertEqual(second.count, 1)
        if case .noteOn(_, let n, let v, _) = second[0] {
            XCTAssertEqual(n, 61)
            XCTAssertEqual(v, 80)
        } else {
            XCTFail("expected noteOn via running status")
        }
    }

    /// UI-GATE-5: status + first data byte in packet A, final data in packet B.
    func testIncompleteMessageAcrossPacketBoundary() {
        let parser = MIDIStreamParser()
        let first = parser.parse(bytes: [0x90, 0x3C], sourceID: "t")
        XCTAssertTrue(first.isEmpty)
        let second = parser.parse(bytes: [0x64], sourceID: "t")
        XCTAssertEqual(second.count, 1)
        if case .noteOn(_, let note, let vel, _) = second[0] {
            XCTAssertEqual(note, 0x3C)
            XCTAssertEqual(vel, 0x64)
        } else {
            XCTFail("expected reconstructed noteOn")
        }
    }

    /// UI-GATE-5: running-status message split after first data byte.
    func testRunningStatusSplitAfterFirstDataByte() {
        let parser = MIDIStreamParser()
        _ = parser.parse(bytes: [0x90, 60, 100], sourceID: "t")
        let partial = parser.parse(bytes: [61], sourceID: "t")
        XCTAssertTrue(partial.isEmpty)
        let complete = parser.parse(bytes: [80], sourceID: "t")
        XCTAssertEqual(complete.count, 1)
        if case .noteOn(_, let n, let v, _) = complete[0] {
            XCTAssertEqual(n, 61)
            XCTAssertEqual(v, 80)
        } else {
            XCTFail("expected noteOn via running status split")
        }
    }

    /// UI-GATE-5: realtime clock interleaved inside incomplete channel message.
    func testRealtimeInterleavedInsideIncompleteMessage() {
        let parser = MIDIStreamParser()
        // Note-on status + note, then clock (0xF8), then velocity
        let events = parser.parse(bytes: [0x90, 60, 0xF8, 100], sourceID: "t")
        XCTAssertEqual(events.count, 1)
        if case .noteOn(_, let n, let v, _) = events[0] {
            XCTAssertEqual(n, 60)
            XCTAssertEqual(v, 100)
        } else {
            XCTFail("expected noteOn with interleaved clock")
        }
    }

    /// UI-GATE-5: clock between incomplete packets does not destroy pending.
    func testRealtimeBetweenPacketsPreservesPending() {
        let parser = MIDIStreamParser()
        _ = parser.parse(bytes: [0xB0, 7], sourceID: "t") // CC status + controller
        _ = parser.parse(bytes: [0xF8], sourceID: "t") // clock alone
        let done = parser.parse(bytes: [64], sourceID: "t") // value
        XCTAssertEqual(done.count, 1)
        if case .controlChange(_, let cc, let val, _) = done[0] {
            XCTAssertEqual(cc, 7)
            XCTAssertEqual(val, 64)
        } else {
            XCTFail("expected CC after interleaved clock packets")
        }
    }

    func testArbitraryChunkBoundariesMultipleMessages() {
        let parser = MIDIStreamParser()
        // Two note-ons: 90 3C 64  90 3E 40 — feed one byte at a time
        let stream: [UInt8] = [0x90, 0x3C, 0x64, 0x90, 0x3E, 0x40]
        var events: [MIDIEvent] = []
        for b in stream {
            events.append(contentsOf: parser.parse(bytes: [b], sourceID: "t"))
        }
        XCTAssertEqual(events.count, 2)
    }
}
