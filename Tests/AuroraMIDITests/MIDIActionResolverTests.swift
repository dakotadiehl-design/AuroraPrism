import AuroraMIDI
import AuroraModel
import XCTest

final class MIDIActionResolverTests: XCTestCase {
    func testMatchGoNote() {
        let mapping = MIDIMapping(messageType: "noteOn", data1: 36, action: "go")
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "t", timestamp: 0)
        XCTAssertEqual(MIDIActionResolver.match(event: event, mappings: [mapping]), .go)
    }

    func testNoMatchWrongNote() {
        let mapping = MIDIMapping(messageType: "noteOn", data1: 36, action: "go")
        let event = MIDIEvent.noteOn(channel: 0, note: 37, velocity: 100, sourceID: "t", timestamp: 0)
        XCTAssertNil(MIDIActionResolver.match(event: event, mappings: [mapping]))
    }

    func testChannelFilter() {
        let mapping = MIDIMapping(channel: 1, messageType: "cc", data1: 7, action: "programmerAttr", actionParameter: "intensity")
        let wrong = MIDIEvent.controlChange(channel: 0, controller: 7, value: 64, sourceID: "t", timestamp: 0)
        let right = MIDIEvent.controlChange(channel: 1, controller: 7, value: 64, sourceID: "t", timestamp: 0)
        XCTAssertNil(MIDIActionResolver.match(event: wrong, mappings: [mapping]))
        XCTAssertEqual(
            MIDIActionResolver.match(event: right, mappings: [mapping]),
            .programmerAttribute("intensity")
        )
    }

    func testLearnBuildsMapping() {
        let session = MIDILearnSession()
        session.arm(.stop)
        let event = MIDIEvent.noteOn(channel: 0, note: 40, velocity: 10, sourceID: "t", timestamp: 0)
        let result = session.completeIfArmed(event: event)
        XCTAssertEqual(result?.action, .stop)
        XCTAssertEqual(result?.mapping.data1, 40)
        XCTAssertFalse(session.isLearning)
    }
}

// MARK: - Device ID filter (P1-2)
extension MIDIActionResolverTests {
    func testDeviceIDFilter() {
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "uid:1", timestamp: 0)
        let any = MIDIMapping(deviceID: nil, messageType: "noteOn", data1: 36, action: "go")
        let match = MIDIMapping(deviceID: "uid:1", messageType: "noteOn", data1: 36, action: "go")
        let other = MIDIMapping(deviceID: "uid:2", messageType: "noteOn", data1: 36, action: "go")
        XCTAssertTrue(MIDIActionResolver.matches(event: event, mapping: any))
        XCTAssertTrue(MIDIActionResolver.matches(event: event, mapping: match))
        XCTAssertFalse(MIDIActionResolver.matches(event: event, mapping: other))
    }

    func testNoteVelocityControlValue() {
        let v1 = MIDIActionResolver.controlValue(for: .noteOn(channel: 0, note: 36, velocity: 1, sourceID: "t", timestamp: 0))
        let v64 = MIDIActionResolver.controlValue(for: .noteOn(channel: 0, note: 36, velocity: 64, sourceID: "t", timestamp: 0))
        let v127 = MIDIActionResolver.controlValue(for: .noteOn(channel: 0, note: 36, velocity: 127, sourceID: "t", timestamp: 0))
        let off = MIDIActionResolver.controlValue(for: .noteOff(channel: 0, note: 36, velocity: 0, sourceID: "t", timestamp: 0))
        XCTAssertEqual(v1.normalized, 1.0 / 127.0, accuracy: 1e-9)
        XCTAssertEqual(v64.normalized, 64.0 / 127.0, accuracy: 1e-9)
        XCTAssertEqual(v127.normalized, 1.0, accuracy: 1e-9)
        XCTAssertEqual(off.normalized, 0)
        XCTAssertTrue(v64.isTrigger)
    }

    func testCCControlValue() {
        let v = MIDIActionResolver.controlValue(for: .controlChange(channel: 0, controller: 7, value: 64, sourceID: "t", timestamp: 0))
        XCTAssertEqual(v.normalized, 64.0 / 127.0, accuracy: 1e-9)
        XCTAssertFalse(v.isTrigger)
    }

    func testMatchAllReturnsMultipleActions() {
        let mappings = [
            MIDIMapping(messageType: "noteOn", data1: 36, action: "go"),
            MIDIMapping(messageType: "noteOn", data1: 36, action: "programmerAttr", actionParameter: "intensity"),
        ]
        let event = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "t", timestamp: 0)
        let actions = MIDIActionResolver.matchAll(event: event, mappings: mappings)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[0], .go)
        XCTAssertEqual(actions[1], .programmerAttribute("intensity"))
    }

    func testData2VelocityFilter() {
        let mapping = MIDIMapping(messageType: "noteOn", data1: 36, data2: 100, action: "go")
        let match = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 100, sourceID: "t", timestamp: 0)
        let miss = MIDIEvent.noteOn(channel: 0, note: 36, velocity: 50, sourceID: "t", timestamp: 0)
        XCTAssertEqual(MIDIActionResolver.match(event: match, mappings: [mapping]), .go)
        XCTAssertNil(MIDIActionResolver.match(event: miss, mappings: [mapping]))
    }

    func testShowActionCatalogIncludesProgrammerScalar() {
        let desc = ShowActionCatalog.descriptor(for: "programmerAttr")
        XCTAssertEqual(desc?.acceptsScalar, true)
        XCTAssertFalse(ShowActionCatalog.all.isEmpty)
    }
}
