import AuroraOutput
import XCTest

final class OutputManagerTests: XCTestCase {
    func testBufferDefaultSize() {
        let buffer = DMXBuffer()
        XCTAssertEqual(buffer.channelCount, 512)
    }

    func testSetLevelsAndMockFlush() throws {
        let manager = OutputManager()
        let mock = MockOutputDriver()
        manager.register(mock)
        try manager.startAll()

        var levels = Array(repeating: UInt8(0), count: 512)
        levels[0] = 128
        levels[1] = 255
        manager.setLevels(universe: 1, values: levels)
        manager.flush(universe: 1)

        let frames = mock.frames(for: 1)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data[0], 128)
        XCTAssertEqual(frames[0].data[1], 255)
    }

    func testNullDriverStartStop() throws {
        let null = NullOutputDriver()
        try null.start()
        XCTAssertTrue(null.isRunning)
        var bytes: [UInt8] = [1, 2, 3]
        bytes.withUnsafeBufferPointer { null.send(universe: 1, dmx: $0) }
        null.stop()
        XCTAssertFalse(null.isRunning)
    }

    func testMultiDriverFanOut() throws {
        let manager = OutputManager()
        let a = MockOutputDriver(name: "A")
        let b = MockOutputDriver(name: "B")
        manager.register(a)
        manager.register(b)
        try manager.startAll()
        manager.setLevels(universe: 2, values: Array(repeating: 10, count: 512))
        manager.flush(universe: 2)
        XCTAssertEqual(a.frames.count, 1)
        XCTAssertEqual(b.frames.count, 1)
    }

    func testUniverseIsolation() throws {
        let manager = OutputManager()
        let mock = MockOutputDriver()
        manager.register(mock)
        try manager.startAll()
        manager.setChannel(universe: 1, address: 1, value: 50)
        manager.setChannel(universe: 2, address: 1, value: 200)
        manager.flushAll()
        XCTAssertEqual(mock.frames(for: 1).last?.data[0], 50)
        XCTAssertEqual(mock.frames(for: 2).last?.data[0], 200)
    }
}
