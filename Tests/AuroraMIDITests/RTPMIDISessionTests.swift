import AuroraMIDI
import XCTest

final class RTPMIDISessionTests: XCTestCase {
    func testConfigRoundTrip() {
        let defaults = UserDefaults(suiteName: "aurora.tests.rtp.\(UUID().uuidString)")!
        var config = RTPMIDIConfig(enabled: true, allowAnyone: false)
        config.save(to: defaults)
        let loaded = RTPMIDIConfig.load(from: defaults)
        XCTAssertEqual(loaded.enabled, true)
        XCTAssertEqual(loaded.allowAnyone, false)
    }

    func testApplyUpdatesConfigSnapshot() {
        let session = RTPMIDISession(config: .default)
        session.apply(RTPMIDIConfig(enabled: true, allowAnyone: true))
        XCTAssertTrue(session.configSnapshot.enabled)
        XCTAssertTrue(session.configSnapshot.allowAnyone)
        session.apply(RTPMIDIConfig(enabled: false, allowAnyone: false))
        XCTAssertFalse(session.configSnapshot.enabled)
        XCTAssertFalse(session.configSnapshot.allowAnyone)
        // Touch system session APIs without asserting host-specific enable success.
        XCTAssertNotNil(session.statusLine())
        _ = session.localName
        _ = session.isNetworkEnabled
    }
}
