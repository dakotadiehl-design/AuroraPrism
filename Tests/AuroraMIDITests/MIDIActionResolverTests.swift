import AuroraMIDI
import AuroraModel
import XCTest

final class MIDIActionResolverTests: XCTestCase {
    func testMatchGoNote() {
        let mapping = MIDIMapping(messageType: "noteOn", data1: 36, action: "go")
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "t")
        XCTAssertEqual(MIDIActionResolver.match(event: event, mappings: [mapping]), .go)
    }

    func testNoMatchWrongNote() {
        let mapping = MIDIMapping(messageType: "noteOn", data1: 36, action: "go")
        let event = MIDIEvent.noteOn(channel: 0, note: 37, velocity: 100, sourceID: "t")
        XCTAssertNil(MIDIActionResolver.match(event: event, mappings: [mapping]))
    }

    func testChannelFilter() {
        let mapping = MIDIMapping(channel: 1, messageType: "cc", data1: 7, action: "programmerAttr", actionParameter: "intensity")
        let wrong = MIDIEvent.controlChange(channel: 0, controller: 7, value: 64, sourceID: "t")
        let right = MIDIEvent.controlChange(channel: 1, controller: 7, value: 64, sourceID: "t")
        XCTAssertNil(MIDIActionResolver.match(event: wrong, mappings: [mapping]))
        XCTAssertEqual(
            MIDIActionResolver.match(event: right, mappings: [mapping]),
            .programmerAttribute("intensity")
        )
    }

    func testLearnBuildsMapping() {
        let session = MIDILearnSession()
        session.arm(.stop)
        let event = MIDIEvent.noteOn(channel: 0, note: 40, velocity: 10, sourceID: "t")
        let result = session.completeIfArmed(event: event)
        XCTAssertEqual(result?.action, .stop)
        XCTAssertEqual(result?.mapping.data1, 40)
        XCTAssertFalse(session.isLearning)
    }
}

// MARK: - Device ID filter (P1-2)
extension MIDIActionResolverTests {
    func testDeviceIDFilter() {
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "uid:1")
        let any = MIDIMapping(deviceID: nil, messageType: "noteOn", data1: 36, action: "go")
        let match = MIDIMapping(deviceID: "uid:1", messageType: "noteOn", data1: 36, action: "go")
        let other = MIDIMapping(deviceID: "uid:2", messageType: "noteOn", data1: 36, action: "go")
        XCTAssertTrue(MIDIActionResolver.matches(event: event, mapping: any))
        XCTAssertTrue(MIDIActionResolver.matches(event: event, mapping: match))
        XCTAssertFalse(MIDIActionResolver.matches(event: event, mapping: other))
    }
}
