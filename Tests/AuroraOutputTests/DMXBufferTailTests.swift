import AuroraOutput
import XCTest

final class DMXBufferTailTests: XCTestCase {
    func testShortFrameClearsStaleTail() {
        var buf = DMXBuffer(channelCount: 8)
        buf.setLevels([1, 2, 3, 4, 5, 6, 7, 8])
        buf.setLevels([9, 10])
        XCTAssertEqual(buf.channels[0], 9)
        XCTAssertEqual(buf.channels[1], 10)
        XCTAssertEqual(buf.channels[2], 0)
        XCTAssertEqual(buf.channels[7], 0)
    }

    func testResizeGrowsAndShrinks() {
        var buf = DMXBuffer(channelCount: 4)
        buf.setLevels([1, 2, 3, 4])
        buf.resize(to: 6)
        XCTAssertEqual(buf.channelCount, 6)
        XCTAssertEqual(buf.channels[3], 4)
        XCTAssertEqual(buf.channels[5], 0)
        buf.resize(to: 2)
        XCTAssertEqual(buf.channels, [1, 2])
    }
}
