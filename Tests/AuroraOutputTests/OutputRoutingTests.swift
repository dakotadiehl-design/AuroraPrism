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
        // Null is .local (route 3) and discards frames — no assertion on captured data.
        _ = null
    }

    /// UI-GATE-3: `.none` means no physical output (not "send everywhere").
    func testNoneRouteSendsToNoPhysicalDrivers() throws {
        let output = OutputManager()
        let a = MockOutputDriver(name: "A", outputProtocol: .artNet)
        let b = MockOutputDriver(name: "B", outputProtocol: .sACN)
        let local = MockOutputDriver(name: "L", outputProtocol: .local)
        output.register(a)
        output.register(b)
        output.register(local)
        try output.startAll()
        output.setUniverseRoutes([1: .none])
        output.ensureUniverse(1, channelCount: 4)
        output.setLevels(universe: 1, values: [9, 0, 0, 0])
        output.flush(universe: 1)
        XCTAssertEqual(a.frames.count, 0)
        XCTAssertEqual(b.frames.count, 0)
        XCTAssertEqual(local.frames.count, 0)
    }

    /// UI-GATE-3: `.mirror` fans to all physical protocol drivers.
    func testMirrorRouteFansToAllPhysicalDrivers() throws {
        let output = OutputManager()
        let a = MockOutputDriver(name: "A", outputProtocol: .artNet)
        let b = MockOutputDriver(name: "B", outputProtocol: .sACN)
        let local = MockOutputDriver(name: "L", outputProtocol: .local)
        output.register(a)
        output.register(b)
        output.register(local)
        try output.startAll()
        output.setUniverseRoutes([1: .mirror])
        output.ensureUniverse(1, channelCount: 4)
        output.setLevels(universe: 1, values: [9, 0, 0, 0])
        output.flush(universe: 1)
        XCTAssertEqual(a.frames.count, 1)
        XCTAssertEqual(b.frames.count, 1)
        XCTAssertEqual(local.frames.count, 1)
    }

    func testLocalRouteOnlyHitsLocalDriver() throws {
        let output = OutputManager()
        let art = MockOutputDriver(name: "Art", outputProtocol: .artNet)
        let local = MockOutputDriver(name: "Local", outputProtocol: .local)
        output.register(art)
        output.register(local)
        try output.startAll()
        output.setUniverseRoutes([1: .local])
        output.ensureUniverse(1, channelCount: 2)
        output.setLevels(universe: 1, values: [1, 2])
        output.flush(universe: 1)
        XCTAssertEqual(art.frames.count, 0)
        XCTAssertEqual(local.frames.count, 1)
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

    /// Mock sink with `.none` still observes even when route is `.none` (test harness).
    func testMockNoneObservesNoneRoute() throws {
        let output = OutputManager()
        let mock = MockOutputDriver(outputProtocol: .none)
        let art = MockOutputDriver(name: "Art", outputProtocol: .artNet)
        output.register(mock)
        output.register(art)
        try output.startAll()
        output.setUniverseRoutes([1: .none])
        output.ensureUniverse(1, channelCount: 2)
        output.setLevels(universe: 1, values: [3, 4])
        output.flush(universe: 1)
        XCTAssertEqual(mock.frames.count, 1)
        XCTAssertEqual(art.frames.count, 0)
    }
}
