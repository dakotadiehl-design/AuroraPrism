import AuroraOutput
import XCTest

final class ENTTECDriverTests: XCTestCase {
    func testProtocolFrameShape() {
        let levels = [UInt8](repeating: 0, count: 512)
        levels.withUnsafeBufferPointer { ptr in
            let packet = ENTTECUSBDMXProProtocol.sendDMXPacket(dmx: ptr)
            XCTAssertEqual(packet.first, 0x7E)
            XCTAssertEqual(packet[1], 6)
            XCTAssertEqual(packet.last, 0xE7)
            // 4 header + 1 start + 512 + 1 end = 518
            XCTAssertEqual(packet.count, 518)
        }
    }

    func testDriverWritesWhenOpen() throws {
        let transport = MockENTTECTransport()
        let driver = ENTTECUSBDMXProDriver(transport: transport, universeFilter: [1])
        try driver.start()
        var dmx = [UInt8](repeating: 0, count: 512)
        dmx[0] = 255
        dmx.withUnsafeBufferPointer { ptr in
            driver.send(universe: 1, dmx: ptr)
        }
        XCTAssertEqual(transport.written.count, 1)
        XCTAssertEqual(driver.healthSnapshot().packetsSent, 1)
        driver.stop()
        XCTAssertFalse(transport.isOpen)
    }

    func testMissingDeviceFailsStart() {
        let transport = MockENTTECTransport()
        transport.failOpen = true
        let driver = ENTTECUSBDMXProDriver(transport: transport)
        XCTAssertThrowsError(try driver.start())
        XCTAssertEqual(driver.healthSnapshot().state, .failed)
    }

    /// Stop must push a zero universe before closing so the Pro stops retransmitting.
    func testStopSendsBlackoutBeforeClose() throws {
        let transport = MockENTTECTransport()
        let driver = ENTTECUSBDMXProDriver(transport: transport, universeFilter: [1])
        try driver.start()
        var dmx = [UInt8](repeating: 0, count: 512)
        dmx[0] = 200
        dmx.withUnsafeBufferPointer { ptr in
            driver.send(universe: 1, dmx: ptr)
        }
        XCTAssertEqual(transport.written.count, 1)
        driver.stop()
        XCTAssertFalse(transport.isOpen)
        // Live frame + blackout frame.
        XCTAssertEqual(transport.written.count, 2)
        let blackout = transport.written.last!
        // Payload after header: start code + 512 channels — all zeros.
        XCTAssertEqual(blackout.count, 518)
        // DMX channel data begins at index 5 (after 0x7E, label, lenL, lenH, startCode).
        let channels = blackout.dropFirst(5).dropLast() // drop end code
        XCTAssertTrue(channels.allSatisfy { $0 == 0 }, "blackout frame must be all zeros")
    }
}
