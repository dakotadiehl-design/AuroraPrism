import AuroraOutput
import XCTest

final class ArtNetPacketTests: XCTestCase {
    func testArtDmxHeader() {
        let dmx = [UInt8](repeating: 0, count: 4)
        let data = ArtNetPacket.artDmx(universe: 0, sequence: 1, dmx: dmx)
        XCTAssertEqual(Array(data.prefix(8)), [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00])
        // OpCode 0x5000 LE
        XCTAssertEqual(data[8], 0x00)
        XCTAssertEqual(data[9], 0x50)
        // ProtVer 14 BE
        XCTAssertEqual(data[10], 0x00)
        XCTAssertEqual(data[11], 14)
        XCTAssertEqual(data[12], 1) // sequence
        // Universe 0 LE
        XCTAssertEqual(data[14], 0)
        XCTAssertEqual(data[15], 0)
        // Length 4 BE
        XCTAssertEqual(data[16], 0)
        XCTAssertEqual(data[17], 4)
        XCTAssertEqual(data.count, 18 + 4)
    }

    func testOddLengthPaddedEven() {
        let dmx: [UInt8] = [1, 2, 3]
        let data = ArtNetPacket.artDmx(universe: 1, sequence: 0, dmx: dmx)
        let length = (Int(data[16]) << 8) | Int(data[17])
        XCTAssertEqual(length % 2, 0)
        XCTAssertEqual(length, 4)
    }

    func testUniverseLittleEndian() {
        let data = ArtNetPacket.artDmx(universe: 0x0201, sequence: 0, dmx: [0, 0])
        XCTAssertEqual(data[14], 0x01)
        XCTAssertEqual(data[15], 0x02)
    }

    func testConfigUniverseOffset() {
        var config = ArtNetConfig(universeOffset: -1)
        XCTAssertEqual(config.artNetUniverse(forShowUniverse: 1), 0)
        config.universeOffset = 0
        XCTAssertEqual(config.artNetUniverse(forShowUniverse: 1), 1)
    }
}
