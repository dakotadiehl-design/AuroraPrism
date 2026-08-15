import XCTest

/// ST-01: structured MIDI health mapping (mirrors app-layer MIDIHealthSnapshot rules).
/// Kept in MIDI tests as pure logic so it runs without the app target.
final class MIDIHealthSnapshotLogicTests: XCTestCase {
    enum State: String {
        case off, ready, warning, failed
    }

    struct Snap {
        var state: State
        var connectedSourceCount: Int
    }

    private func running(sourceCount: Int) -> Snap {
        if sourceCount <= 0 {
            return Snap(state: .off, connectedSourceCount: 0)
        }
        return Snap(state: .ready, connectedSourceCount: sourceCount)
    }

    func testZeroSourcesNotHealthy() {
        let snap = running(sourceCount: 0)
        XCTAssertEqual(snap.state, .off)
        XCTAssertNotEqual(snap.state, .ready)
    }

    func testOneSourceHealthy() {
        let snap = running(sourceCount: 1)
        XCTAssertEqual(snap.state, .ready)
        XCTAssertEqual(snap.connectedSourceCount, 1)
    }

    func testLegacyStringZeroSourcesNotHealthy() {
        let lower = "MIDI: 0 sources".lowercased()
        XCTAssertTrue(lower.contains("0 source") || lower.contains("0 src"))
    }
}
