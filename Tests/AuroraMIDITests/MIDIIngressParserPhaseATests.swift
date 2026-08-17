import AuroraMIDI
import AuroraMusical
import XCTest

final class MIDIIngressParserPhaseATests: XCTestCase {
    private let t0 = HostTime(nanoseconds: 1_000_000_000)
    private let t1 = HostTime(nanoseconds: 2_000_000_000)

    func testClockBetweenNoteOnDataBytesEmitsRealtimeAndNote() {
        let parser = MIDIStreamParser()
        let events = parser.parseIngress(bytes: [0x90, 60, 0xF8, 100], sourceID: "drum", hostTime: t0)
        XCTAssertEqual(events.count, 2)
        if case .systemRealtime(.timingClock, let src, let t) = events[0] {
            XCTAssertEqual(src, "drum")
            XCTAssertEqual(t, t0)
        } else {
            XCTFail("expected timing clock")
        }
        if case .channelVoice(let voice) = events[1] {
            if case .noteOn(_, let n, let v, _, _) = voice.event {
                XCTAssertEqual(n, 60)
                XCTAssertEqual(v, 100)
            } else {
                XCTFail("expected noteOn")
            }
            XCTAssertEqual(voice.hostTime, t0)
        } else {
            XCTFail("expected channel voice")
        }
    }

    func testClockDuringRunningStatusStream() {
        let parser = MIDIStreamParser()
        _ = parser.parseIngress(bytes: [0x90, 60, 100], sourceID: "t", hostTime: t0)
        let events = parser.parseIngress(bytes: [61, 0xF8, 80], sourceID: "t", hostTime: t0)
        let clocks = events.filter {
            if case .systemRealtime(.timingClock, _, _) = $0 { return true }
            return false
        }
        XCTAssertEqual(clocks.count, 1)
        XCTAssertEqual(events.compactMap(\.channelVoiceEvent).count, 1)
    }

    func testMultipleClocksInterspersedWithChannelVoice() {
        let parser = MIDIStreamParser()
        let bytes: [UInt8] = [0xF8, 0x90, 38, 0xF8, 100, 0xF8, 0x80, 38, 0xF8, 0]
        let events = parser.parseIngress(bytes: bytes, sourceID: "t", hostTime: t0)
        let clockCount = events.filter {
            if case .systemRealtime(.timingClock, _, _) = $0 { return true }
            return false
        }.count
        XCTAssertEqual(clockCount, 4)
        XCTAssertEqual(events.compactMap(\.channelVoiceEvent).count, 2)
    }

    func testStartStopContinueInterleaving() {
        let parser = MIDIStreamParser()
        let events = parser.parseIngress(
            bytes: [0xFA, 0x90, 36, 100, 0xFC, 0xFB],
            sourceID: "t",
            hostTime: t0
        )
        var kinds: [String] = []
        for e in events {
            switch e {
            case .systemRealtime(.start, _, _): kinds.append("start")
            case .systemRealtime(.stop, _, _): kinds.append("stop")
            case .systemRealtime(.continue, _, _): kinds.append("continue")
            case .channelVoice: kinds.append("voice")
            default: kinds.append("other")
            }
        }
        XCTAssertEqual(kinds, ["start", "voice", "stop", "continue"])
    }

    func testSPPIsSystemCommonNotRealtime() {
        let parser = MIDIStreamParser()
        let events = parser.parseIngress(bytes: [0xF2, 0x00, 0x01], sourceID: "t", hostTime: t0)
        XCTAssertEqual(events.count, 1)
        if case .systemCommon(.songPositionPointer(let sixteenths), _, _) = events[0] {
            XCTAssertEqual(sixteenths, 128)
        } else {
            XCTFail("SPP must be systemCommon")
        }
    }

    func testSPPWithInterleavedClock() {
        let parser = MIDIStreamParser()
        let events = parser.parseIngress(bytes: [0xF2, 0xF8, 0x04, 0xF8, 0x00], sourceID: "t", hostTime: t0)
        let clocks = events.filter {
            if case .systemRealtime(.timingClock, _, _) = $0 { return true }
            return false
        }
        XCTAssertEqual(clocks.count, 2)
        let spp = events.compactMap { e -> UInt16? in
            if case .systemCommon(.songPositionPointer(let s), _, _) = e { return s }
            return nil
        }
        XCTAssertEqual(spp, [4])
    }

    func testMalformedSPPDoesNotPoisonSubsequentNote() {
        let parser = MIDIStreamParser()
        let first = parser.parseIngress(bytes: [0xF2, 0x10], sourceID: "t", hostTime: t0)
        XCTAssertTrue(first.isEmpty)
        let second = parser.parseIngress(bytes: [0x90, 60, 100], sourceID: "t", hostTime: t1)
        XCTAssertEqual(second.compactMap(\.channelVoiceEvent).count, 1)
    }

    func testNoteOnVelocityZeroNormalizesToNoteOff() {
        let parser = MIDIStreamParser()
        let events = parser.parseIngress(bytes: [0x90, 42, 0], sourceID: "t", hostTime: t0)
        XCTAssertEqual(events.count, 1)
        if case .channelVoice(let voice) = events[0] {
            if case .noteOff(_, let n, let v, _, _) = voice.event {
                XCTAssertEqual(n, 42)
                XCTAssertEqual(v, 0)
            } else {
                XCTFail("expected noteOff")
            }
        } else {
            XCTFail("expected channel voice")
        }
    }

    func testLegacyParseStillReturnsOnlyChannelVoice() {
        let events = MIDIMessageParser.parse(bytes: [0xF8, 0x90, 60, 100, 0xFA], sourceID: "t")
        XCTAssertEqual(events.count, 1)
    }

    func testCompletionTimestampUsesFinalPacketHostTime() {
        let parser = MIDIStreamParser()
        // Status + note in packet 1 (t0); velocity in packet 2 (t1) → completion at t1
        let first = parser.parseIngress(bytes: [0x90, 60], sourceID: "t", hostTime: t0)
        XCTAssertTrue(first.isEmpty)
        let second = parser.parseIngress(bytes: [100], sourceID: "t", hostTime: t1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].hostTime, t1)
    }

    func testUndefinedRealtimeDoesNotPoison() {
        let parser = MIDIStreamParser()
        // F9 undefined realtime between note data
        let events = parser.parseIngress(bytes: [0x90, 60, 0xF9, 100], sourceID: "t", hostTime: t0)
        XCTAssertEqual(events.compactMap(\.channelVoiceEvent).count, 1)
    }

    func testSystemCommonClearsRunningStatus() {
        let parser = MIDIStreamParser()
        _ = parser.parseIngress(bytes: [0x90, 60, 100], sourceID: "t", hostTime: t0)
        // SPP is system common — clears running status
        _ = parser.parseIngress(bytes: [0xF2, 0x00, 0x00], sourceID: "t", hostTime: t0)
        // Data without status should not form a note
        let orphan = parser.parseIngress(bytes: [61, 80], sourceID: "t", hostTime: t0)
        XCTAssertTrue(orphan.compactMap(\.channelVoiceEvent).isEmpty)
    }

    func testRealtimeDoesNotClearRunningStatus() {
        let parser = MIDIStreamParser()
        _ = parser.parseIngress(bytes: [0x90, 60, 100], sourceID: "t", hostTime: t0)
        _ = parser.parseIngress(bytes: [0xF8], sourceID: "t", hostTime: t0)
        let events = parser.parseIngress(bytes: [61, 80], sourceID: "t", hostTime: t0)
        XCTAssertEqual(events.compactMap(\.channelVoiceEvent).count, 1)
    }
}
