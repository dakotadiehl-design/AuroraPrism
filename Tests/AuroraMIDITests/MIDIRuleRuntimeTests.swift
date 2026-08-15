import AuroraMIDI
import AuroraModel
import XCTest

final class MIDIRuleRuntimeTests: XCTestCase {
    func testRuleMatchByPriorityAndSection() {
        let low = MIDIRule(
            name: "low",
            priority: 1,
            messageType: "noteOn",
            data1Min: 36,
            data1Max: 36,
            actionKeys: ["go"],
            songSectionContext: "Verse"
        )
        let high = MIDIRule(
            name: "high",
            priority: 10,
            messageType: "noteOn",
            data1Min: 36,
            data1Max: 36,
            actionKeys: ["stop"],
            songSectionContext: "Verse"
        )
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "t", timestamp: 0)
        let verse = MIDIActionResolver.matchRules(event: event, rules: [low, high], songSection: "Verse")
        XCTAssertEqual(verse.first, .stop)
        XCTAssertEqual(verse.count, 2) // both match; priority order

        let chorus = MIDIActionResolver.matchRules(event: event, rules: [low, high], songSection: "Chorus")
        XCTAssertTrue(chorus.isEmpty)
    }

    func testRuleCCRange() {
        let rule = MIDIRule(
            channel: 0,
            messageType: "cc",
            data1Min: 1,
            data1Max: 8,
            data2Min: 0,
            data2Max: 127,
            actionKeys: ["masterIntensity"]
        )
        let hit = MIDIEvent.controlChange(channel: 0, controller: 7, value: 64, sourceID: "t", timestamp: 0)
        let miss = MIDIEvent.controlChange(channel: 0, controller: 20, value: 64, sourceID: "t", timestamp: 0)
        XCTAssertEqual(MIDIActionResolver.matchRules(event: hit, rules: [rule]), [.masterIntensity])
        XCTAssertTrue(MIDIActionResolver.matchRules(event: miss, rules: [rule]).isEmpty)
    }

    func testSafetyLimiterRateLimit() {
        let limiter = MIDISafetyLimiter(maxEventsPerSecond: 5, debounceSeconds: 0)
        var allowed = 0
        for i in 0..<20 {
            let e = MIDIEvent.noteOn(channel: 0, note: UInt8(i), velocity: 100, sourceID: "t", timestamp: Double(i) * 0.001)
            if limiter.allow(event: e) { allowed += 1 }
        }
        XCTAssertLessThanOrEqual(allowed, 6)
        XCTAssertGreaterThan(allowed, 0)
    }

    func testExpressiveEventTypesParse() {
        let bend = MIDIMessageParser.parse(bytes: [0xE0, 0x00, 0x40], sourceID: "t")
        XCTAssertEqual(bend.count, 1)
        if case .pitchBend(_, let v, _, _) = bend[0] {
            XCTAssertEqual(v, 0x2000)
        } else {
            XCTFail("expected pitch bend")
        }
        let at = MIDIMessageParser.parse(bytes: [0xD0, 90], sourceID: "t")
        guard case .channelPressure(_, let p, _, _) = at[0] else {
            return XCTFail("expected channel pressure")
        }
        XCTAssertEqual(p, 90)
    }
}
