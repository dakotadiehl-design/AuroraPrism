import AuroraOutput
import XCTest

/// Quit hang with ENTTEC connected: blocking serial write/close held the transport
/// lock (or blocked the main thread) until the USB device was unplugged.
final class ENTTECSerialTransportConcurrencyTests: XCTestCase {

    /// Concurrent engine `send` + `stop` must not deadlock. Blackout on stop is required.
    private final class RecordingTransport: ENTTECSerialTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _isOpen = false
        private(set) var closeCount = 0
        private(set) var written: [Data] = []

        var isOpen: Bool {
            lock.lock(); defer { lock.unlock() }
            return _isOpen
        }

        func open() throws {
            lock.lock()
            _isOpen = true
            lock.unlock()
        }

        func close() {
            lock.lock()
            _isOpen = false
            closeCount += 1
            lock.unlock()
        }

        func write(_ data: Data) throws {
            lock.lock()
            guard _isOpen else {
                lock.unlock()
                throw ENTTECError.notOpen
            }
            written.append(data)
            lock.unlock()
        }
    }

    func testDriverStopWhileSendInFlightCompletesWithBlackoutAndClose() throws {
        let transport = RecordingTransport()
        let driver = ENTTECUSBDMXProDriver(name: "Race", transport: transport, universeFilter: [1])
        try driver.start()

        let stopFinished = expectation(description: "stop returned")
        let group = DispatchGroup()

        // Hammer send while stop runs — must not hang and must end closed.
        for _ in 0..<32 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                var dmx = [UInt8](repeating: 0, count: 512)
                dmx[0] = 42
                dmx.withUnsafeBufferPointer { ptr in
                    driver.send(universe: 1, dmx: ptr)
                }
                group.leave()
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Overlap with sends
            Thread.sleep(forTimeInterval: 0.005)
            driver.stop()
            stopFinished.fulfill()
        }

        wait(for: [stopFinished], timeout: 2.0)
        _ = group.wait(timeout: .now() + 2.0)

        XCTAssertFalse(driver.isRunning)
        XCTAssertEqual(transport.closeCount, 1)
        XCTAssertFalse(transport.isOpen)
        // At least the blackout frame (all-zero channels) must have been written.
        let hasBlackout = transport.written.contains { frame in
            guard frame.count == 518 else { return false }
            return frame.dropFirst(5).dropLast().allSatisfy { $0 == 0 }
        }
        XCTAssertTrue(hasBlackout, "stop must send a zero universe before close")
    }

    func testPOSIXWriteTimesOutOnNonblockingPipe() throws {
        #if os(macOS)
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        let readEnd = fds[0]
        let writeEnd = fds[1]
        defer {
            Darwin.close(readEnd)
            Darwin.close(writeEnd)
        }
        // Make write end non-blocking and fill the pipe so further writes EAGAIN.
        let flags = fcntl(writeEnd, F_GETFL)
        _ = fcntl(writeEnd, F_SETFL, flags | O_NONBLOCK)
        let chunk = Data(repeating: 0xAB, count: 64 * 1024)
        // Fill until EAGAIN
        while true {
            let n = chunk.withUnsafeBytes { buf -> Int in
                guard let base = buf.baseAddress else { return -1 }
                return Darwin.write(writeEnd, base, buf.count)
            }
            if n < 0 { break }
            if n == 0 { break }
        }
        // A large write should time out rather than hang.
        let payload = Data(repeating: 0xCD, count: 64 * 1024)
        let start = Date()
        XCTAssertThrowsError(
            try POSIXWrite.completeWrite(fd: writeEnd, data: payload, timeout: 0.03)
        ) { error in
            guard let enttec = error as? ENTTECError,
                  case .writeFailed(let msg) = enttec else {
                return XCTFail("expected writeFailed, got \(error)")
            }
            XCTAssertTrue(msg.contains("timeout"), msg)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        #else
        throw XCTSkip("macOS only")
        #endif
    }

    func testMockTransportCloseIsIdempotent() {
        let t = MockENTTECTransport()
        try? t.open()
        t.close()
        t.close()
        XCTAssertEqual(t.closeCount, 1)
        XCTAssertFalse(t.isOpen)
    }

    /// Documents the OS guarantee the transport relies on: a `dup`'d write fd remains
    /// valid after the original fd number is closed (so concurrent close cannot redirect
    /// a pending write onto a recycled descriptor).
    func testDupWriteSurvivesOriginalFdClose() throws {
        #if os(macOS)
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        let readEnd = fds[0]
        let writeEnd = fds[1]
        defer { Darwin.close(readEnd) }

        let dupWrite = Darwin.dup(writeEnd)
        XCTAssertGreaterThanOrEqual(dupWrite, 0)
        defer { Darwin.close(dupWrite) }

        // Close the canonical fd (transport.close equivalent). The integer may be reused,
        // but the open-file description behind `dupWrite` must still accept the frame.
        Darwin.close(writeEnd)

        let payload = Data([0x7E, 0x06, 0x01])
        try POSIXWrite.completeWrite(fd: dupWrite, data: payload, timeout: 0.1)

        var buf = [UInt8](repeating: 0, count: payload.count)
        let n = Darwin.read(readEnd, &buf, buf.count)
        XCTAssertEqual(n, payload.count)
        XCTAssertEqual(Data(buf), payload)
        #else
        throw XCTSkip("macOS only")
        #endif
    }
}
