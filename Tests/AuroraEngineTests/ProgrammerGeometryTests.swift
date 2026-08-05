import AuroraEngine
import XCTest

final class ProgrammerGeometryTests: XCTestCase {
    func testAlign() {
        let ids = [UUID(), UUID(), UUID()]
        let map = ProgrammerGeometry.align(fixtureIDs: ids, value: 0.4)
        XCTAssertEqual(map.count, 3)
        XCTAssertTrue(map.values.allSatisfy { abs($0 - 0.4) < 0.0001 })
    }

    func testFanEndpoints() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let map = ProgrammerGeometry.fan(fixtureIDs: [a, b, c], start: 0, end: 1)
        XCTAssertEqual(map[a]!, 0, accuracy: 0.001)
        XCTAssertEqual(map[b]!, 0.5, accuracy: 0.001)
        XCTAssertEqual(map[c]!, 1, accuracy: 0.001)
    }

    func testFanSingle() {
        let id = UUID()
        let map = ProgrammerGeometry.fan(fixtureIDs: [id], start: 0.3, end: 0.9)
        XCTAssertEqual(map[id]!, 0.3, accuracy: 0.001)
    }
}
