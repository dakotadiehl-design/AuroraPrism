import AuroraEngine
import XCTest

final class ProgrammerGeometryFanAlignTests: XCTestCase {
    func testFanCenterSpreadPhases() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
        let map = ProgrammerGeometry.fan(fixtureIDs: [a, b, c, d, e], center: 0.5, spread: 0.5)
        XCTAssertEqual(map[a]!, 0.0, accuracy: 1e-9)
        XCTAssertEqual(map[c]!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(map[e]!, 1.0, accuracy: 1e-9)
    }

    func testFanReverseOrderReversesResult() {
        let a = UUID(), b = UUID(), c = UUID()
        let forward = ProgrammerGeometry.fan(fixtureIDs: [a, b, c], center: 0.5, spread: 0.5)
        let reverse = ProgrammerGeometry.fan(fixtureIDs: [c, b, a], center: 0.5, spread: 0.5)
        XCTAssertEqual(forward[a]!, reverse[c]!, accuracy: 1e-9)
        XCTAssertEqual(forward[c]!, reverse[a]!, accuracy: 1e-9)
    }

    func testFanSingleFixtureUsesCenter() {
        let id = UUID()
        let map = ProgrammerGeometry.fan(fixtureIDs: [id], center: 0.42, spread: 0.9)
        XCTAssertEqual(map[id]!, 0.42, accuracy: 1e-9)
    }

    func testAlignToFirstOwned() {
        let a = UUID(), b = UUID(), c = UUID()
        let values = [a: 0.4, b: 0.72, c: 0.1]
        let map = ProgrammerGeometry.alignToFirst(fixtureIDs: [a, b, c], values: values)
        XCTAssertNotNil(map)
        XCTAssertEqual(map![a]!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(map![b]!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(map![c]!, 0.4, accuracy: 1e-9)
    }

    func testAlignToFirstUntouchedReturnsNil() {
        let a = UUID(), b = UUID()
        // first capable has no programmer value — do not invent 0
        let values = [b: 0.72]
        let map = ProgrammerGeometry.alignToFirst(fixtureIDs: [a, b], values: values)
        XCTAssertNil(map)
    }

    func testLegacyStartEndStillWorks() {
        let a = UUID(), b = UUID()
        let map = ProgrammerGeometry.fan(fixtureIDs: [a, b], start: 0, end: 1)
        XCTAssertEqual(map[a]!, 0, accuracy: 1e-9)
        XCTAssertEqual(map[b]!, 1, accuracy: 1e-9)
    }
}
