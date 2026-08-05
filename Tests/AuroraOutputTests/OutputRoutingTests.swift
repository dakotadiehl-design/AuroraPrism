import AuroraModel
import AuroraOutput
import XCTest

final class OutputRoutingTests: XCTestCase {
    func testArtNetRouteOnlyHitsArtNetDriver() throws {
        let output = OutputManager()
        let art = MockOutputDriver(name: "Art", outputProtocol: .artNet)
        let sacn = MockOutputDriver(name: "sACN", outputProtocol: .sACN)
        let null = NullOutputDriver()
        output.register(art)
        output.register(sacn)
        output.register(null)
        try output.startAll()

        output.setUniverseRoutes([1: .artNet, 2: .sACN, 3: .local])
        output.ensureUniverse(1, channelCount: 8)
        output.ensureUniverse(2, channelCount: 8)
        output.ensureUniverse(3, channelCount: 8)
        output.setLevels(universe: 1, values: [1, 0, 0, 0, 0, 0, 0, 0])
        output.setLevels(universe: 2, values: [2, 0, 0, 0, 0, 0, 0, 0])
        output.setLevels(universe: 3, values: [3, 0, 0, 0, 0, 0, 0, 0])
        output.flushAll()

        XCTAssertEqual(art.frames.map(\.universe), [1])
        XCTAssertEqual(sacn.frames.map(\.universe), [2])
        // Null is .local → universe 3 only
    }

    func testNoneRouteFansToAllDrivers() throws {
        let output = OutputManager()
        let a = MockOutputDriver(name: "A", outputProtocol: .artNet)
        let b = MockOutputDriver(name: "B", outputProtocol: .sACN)
        output.register(a)
        output.register(b)
        try output.startAll()
        output.setUniverseRoutes([1: .none])
        output.ensureUniverse(1, channelCount: 4)
        output.setLevels(universe: 1, values: [9, 0, 0, 0])
        output.flush(universe: 1)
        XCTAssertEqual(a.frames.count, 1)
        XCTAssertEqual(b.frames.count, 1)
    }

    func testMockNoneAcceptsAnyRoute() throws {
        let output = OutputManager()
        let mock = MockOutputDriver(outputProtocol: .none)
        output.register(mock)
        try output.startAll()
        output.setUniverseRoutes([5: .artNet])
        output.ensureUniverse(5, channelCount: 2)
        output.setLevels(universe: 5, values: [1, 2])
        output.flush(universe: 5)
        XCTAssertEqual(mock.frames.count, 1)
    }
}
