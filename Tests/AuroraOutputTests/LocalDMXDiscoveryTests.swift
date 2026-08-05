import AuroraOutput
import XCTest

final class LocalDMXDiscoveryTests: XCTestCase {
    func testMockEnumeratorReturnsInjectedDevices() {
        let dev = LocalDMXDeviceDescriptor(
            id: "mock-1",
            displayName: "Mock USB Pro",
            serialPath: "/dev/cu.mock",
            connectionState: .available
        )
        let enumr = MockLocalDMXDeviceEnumerator(devices: [dev])
        XCTAssertEqual(enumr.enumerate().count, 1)
        XCTAssertEqual(enumr.enumerate().first?.id, "mock-1")
    }

    func testDriverStartOpensTransportExactlyOnce() throws {
        let t = MockENTTECTransport()
        t.failOnSecondOpen = true
        let driver = ENTTECUSBDMXProDriver(name: "Test Pro", transport: t)
        try driver.start()
        XCTAssertEqual(t.openCount, 1)
        XCTAssertTrue(t.isOpen)
        XCTAssertTrue(driver.isRunning)
        driver.stop()
        XCTAssertEqual(t.closeCount, 1)
        XCTAssertFalse(t.isOpen)
    }

    func testDriverStartFailureDoesNotLeaveRunning() {
        let t = MockENTTECTransport()
        t.failOpen = true
        let driver = ENTTECUSBDMXProDriver(name: "Fail", transport: t)
        XCTAssertThrowsError(try driver.start())
        XCTAssertFalse(driver.isRunning)
        XCTAssertEqual(t.openCount, 0)
    }

    func testDriverLocalProtocolAndUniverseFilterDefault() throws {
        let t = MockENTTECTransport()
        let driver = ENTTECUSBDMXProDriver(name: "Test Pro", transport: t)
        XCTAssertEqual(driver.outputProtocol, .local)
        try driver.start()
        // Default filter is universe 1 only (HW-06).
        XCTAssertTrue(driver.universeFilter.contains(1))
        driver.stop()
    }

    func testRepeatedStartAfterStop() throws {
        let t = MockENTTECTransport()
        let driver = ENTTECUSBDMXProDriver(name: "Test Pro", transport: t)
        try driver.start()
        driver.stop()
        try driver.start()
        XCTAssertEqual(t.openCount, 2)
        XCTAssertEqual(t.closeCount, 1)
        driver.stop()
        XCTAssertEqual(t.closeCount, 2)
    }
}
