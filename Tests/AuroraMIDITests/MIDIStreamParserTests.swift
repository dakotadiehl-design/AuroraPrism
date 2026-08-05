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
}
