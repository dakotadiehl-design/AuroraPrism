import AuroraOutput
import XCTest

final class SACNPacketTests: XCTestCase {
    func testDataPacketPreambleAndVectors() {
        let cid = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
        let dmx = [UInt8](repeating: 0x40, count: 4)
        let data = SACNPacket.dataPacket(
            universe: 1,
            sequence: 7,
            priority: 100,
            cid: cid,
            sourceName: "Aurora",
            dmx: dmx
        )

        // Preamble
        XCTAssertEqual(data[0], 0x00)
        XCTAssertEqual(data[1], 0x10)
        // ACN identifier starts at offset 4
        XCTAssertEqual(Array(data[4..<13]), Array("ASC-E1.17".utf8))

        // Root vector at offset 18 (after 16-byte preamble header + 2 flags/length)
        // 0-1 pre, 2-3 post, 4-15 id (12), 16-17 flags, 18-21 vector
        let rootVector = u32be(data, 18)
        XCTAssertEqual(rootVector, SACNPacket.vectorRootE131Data)

        // Framing vector follows root: flags(2) + vector(4) after 22-byte root body from flags
        // Root PDU starts at 16: flags(2)+vector(4)+cid(16)=22 → framing at 16+22=38
        let framingVector = u32be(data, 40) // 38 flags, 40 vector
        XCTAssertEqual(framingVector, SACNPacket.vectorE131DataPacket)

        // Sequence is after source name (64) + priority(1) + sync(2) from framing start+6
        // framing @38: flags2 + vec4 + name64 + pri1 + sync2 + seq1
        let seqOffset = 38 + 2 + 4 + 64 + 1 + 2
        XCTAssertEqual(data[seqOffset], 7)

        // Universe BE at seq+1(options)+1
        let uniOffset = seqOffset + 2
        XCTAssertEqual(data[uniOffset], 0)
        XCTAssertEqual(data[uniOffset + 1], 1)

        // Property count = 5 (start code + 4), DMX payload includes start code 0
        // DMP starts after framing 77 bytes from framing PDU start
        // Framing length includes DMP; start code after DMP header 10 bytes
        let dmpStart = 38 + 77
        XCTAssertEqual(data[dmpStart + 2], 0x02) // wait flags at dmpStart, vector at +2
        // Actually: dmpStart: flags(2) vector(1)=0x02
        XCTAssertEqual(data[dmpStart + 2], SACNPacket.vectorDMPSetProperty)
        let startCodeOffset = dmpStart + 10
        XCTAssertEqual(data[startCodeOffset], 0x00)
        XCTAssertEqual(data[startCodeOffset + 1], 0x40)
    }

    func testConfigUniverseAndMulticast() {
        var config = SACNConfig(universeOffset: 0)
        XCTAssertEqual(config.sacnUniverse(forShowUniverse: 1), 1)
        config.universeOffset = 10
        XCTAssertEqual(config.sacnUniverse(forShowUniverse: 1), 11)
        XCTAssertEqual(SACNConfig.multicastHost(forSACNUniverse: 1), "239.255.0.1")
        XCTAssertEqual(SACNConfig.multicastHost(forSACNUniverse: 0x0100), "239.255.1.0")
        config.destinationHost = nil
        XCTAssertEqual(config.destinationHost(forSACNUniverse: 1), "239.255.0.1")
        config.destinationHost = "192.168.1.10"
        XCTAssertEqual(config.destinationHost(forSACNUniverse: 1), "192.168.1.10")
    }

    func testPropertyCountIncludesStartCode() {
        let cid = UUID()
        let data = SACNPacket.dataPacket(universe: 2, sequence: 0, cid: cid, dmx: [1, 2, 3])
        // Find DMP property count: after DMP flags, vector, addr type, first addr, increment
        // Framing starts 38; DMP at 38+77=115
        let propCountOffset = 115 + 8
        let count = (Int(data[propCountOffset]) << 8) | Int(data[propCountOffset + 1])
        XCTAssertEqual(count, 4) // start code + 3
        XCTAssertEqual(data.count, 115 + 10 + 4)
    }

    private func u32be(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}
