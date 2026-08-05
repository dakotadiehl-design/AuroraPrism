import AuroraModel
import AuroraOutput
import XCTest

/// Automated multi-universe continuous output soak (P3-2) using mock drivers.
/// Not a substitute for real nodes, but validates multi-universe routing + sustained send.
final class HardwareSoakTests: XCTestCase {
    func testMultiUniverseContinuousSend() throws {
        let output = OutputManager()
        let art = MockOutputDriver(name: "Art", outputProtocol: .artNet)
        let sacn = MockOutputDriver(name: "sACN", outputProtocol: .sACN)
        output.register(art)
        output.register(sacn)
        try output.startAll()
        output.setUniverseRoutes([1: .artNet, 2: .sACN, 3: .artNet])
        for u: UInt16 in 1...3 {
            output.ensureUniverse(u, channelCount: 512)
        }

        let frames = 200
        for i in 0..<frames {
            for u: UInt16 in 1...3 {
                var levels = [UInt8](repeating: 0, count: 512)
                levels[0] = UInt8(i % 256)
                output.setLevels(universe: u, values: levels)
            }
            output.flushAll()
        }

        XCTAssertEqual(art.frames.count, frames * 2) // U1 + U3
        XCTAssertEqual(sacn.frames.count, frames) // U2
        XCTAssertEqual(art.frames.last?.data[0], UInt8((frames - 1) % 256))
    }
}
