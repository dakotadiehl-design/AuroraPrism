@testable import AuroraOutput
import AuroraDiagnostics
import Foundation
import Network
import XCTest

final class OutputDiagnosticsRegressionTests: XCTestCase {
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() -> Int {
            lock.lock()
            value += 1
            let result = value
            lock.unlock()
            return result
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    override func setUp() {
        super.setUp()
        PrismLog.resetForTests()
    }

    override func tearDown() {
        PrismLog.resetForTests()
        super.tearDown()
    }

    func testSACNSendFailureLogsAndNextSuccessRecovers() throws {
        let sink = InMemoryPrismLogSink()
        PrismLog.shared = sink
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        let driver = SACNOutputDriver()
        try driver.start()

        driver.handleSendCompletion(.posix(.EIO))
        driver.handleSendCompletion(nil)

        XCTAssertEqual(sink.snapshot().map(\.code), [
            "output.sacn.started", "output.sacn.failed", "output.sacn.recovered", "output.sacn.frame_summary",
        ])
        XCTAssertNotNil(sink.snapshot().first(where: { $0.code == "output.sacn.failed" })?.technicalMessage)
    }

    func testArtNetSendFailureLogsAndNextSuccessRecovers() throws {
        let sink = InMemoryPrismLogSink()
        PrismLog.shared = sink
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        let config = ArtNetConfig(enabled: true, destinationHost: "127.0.0.1", useBroadcast: false)
        let driver = ArtNetOutputDriver(config: config)
        try driver.start()
        defer { driver.stop() }

        driver.handleSendCompletion(.posix(.EIO))
        driver.handleSendCompletion(nil)

        let events = sink.snapshot()
        XCTAssertTrue(events.contains(where: { $0.code == "output.artnet.failed" && $0.technicalMessage != nil }))
        XCTAssertTrue(events.contains(where: { $0.code == "output.artnet.recovered" }))
    }

    func testDisabledDebugDoesNotInvokeNetworkFrameCounters() throws {
        let sink = InMemoryPrismLogSink()
        PrismLog.shared = sink
        PrismLogConfigurationStore.shared.replace(.productionDefaults)
        let counter = CallCounter()
        let note: @Sendable () -> Int? = { counter.increment() }
        let sacn = SACNOutputDriver(frameSummaryNote: note)
        try sacn.start()
        sacn.handleSendCompletion(nil)

        let artnet = ArtNetOutputDriver(
            config: ArtNetConfig(enabled: true, destinationHost: "127.0.0.1", useBroadcast: false),
            frameSummaryNote: note
        )
        try artnet.start()
        defer { artnet.stop() }
        artnet.handleSendCompletion(nil)

        let local = ENTTECUSBDMXProDriver(
            transport: MockENTTECTransport(),
            frameSummaryNote: note
        )
        try local.start()
        let frame = [UInt8](repeating: 0, count: 512)
        frame.withUnsafeBufferPointer { local.send(universe: 1, dmx: $0) }
        local.stop()

        XCTAssertEqual(counter.count, 0)
    }

    func testStopEventsRequireARealTransition() throws {
        let sink = InMemoryPrismLogSink()
        PrismLog.shared = sink
        PrismLogConfigurationStore.shared.replace(.verboseAll)
        let driver = SACNOutputDriver()
        driver.stop()
        XCTAssertFalse(sink.snapshot().contains(where: { $0.code == "output.sacn.stopped" }))
        try driver.start()
        driver.stop()
        driver.stop()
        XCTAssertEqual(sink.snapshot().filter { $0.code == "output.sacn.stopped" }.count, 1)
    }
}
