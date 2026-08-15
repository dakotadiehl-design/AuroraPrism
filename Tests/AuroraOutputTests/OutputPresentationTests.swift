import AuroraModel
import AuroraOutput
import XCTest

/// Mock driver with injectable health for PRE-UI-1.
final class MutableHealthDriver: OutputDriver, OutputHealthReporting, @unchecked Sendable {
    let id = UUID()
    let name = "Mutable"
    let outputProtocol: UniverseProtocolHint = .artNet
    private let lock = NSLock()
    private var _isRunning = false
    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }
    var state: OutputDriverState = .ready
    var lastError: String?

    func start() throws {
        lock.lock(); _isRunning = true; lock.unlock()
    }

    func stop() {
        lock.lock(); _isRunning = false; lock.unlock()
    }

    func send(universe: UInt16, dmx: UnsafeBufferPointer<UInt8>) {}

    func healthSnapshot() -> OutputHealthSnapshot {
        OutputHealthSnapshot(
            driverID: id,
            name: name,
            outputProtocol: outputProtocol,
            state: isRunning ? state : .disabled,
            target: "127.0.0.1",
            lastError: lastError
        )
    }
}

final class OutputPresentationTests: XCTestCase {
    func testHealthTransitionReflectedWithoutConfigChange() throws {
        let driver = MutableHealthDriver()
        try driver.start()
        driver.state = .ready

        var snap = OutputPresentationSnapshot.from(health: [driver.healthSnapshot()])
        XCTAssertEqual(snap.aggregate, .healthy)
        XCTAssertTrue(snap.statusLine.contains("ready"))

        // Async-style health change (no OutputController config action).
        driver.state = .degraded
        driver.lastError = "send failed"
        snap = OutputPresentationSnapshot.from(health: [driver.healthSnapshot()])
        XCTAssertEqual(snap.aggregate, .warning)
        XCTAssertTrue(snap.statusLine.contains("degraded"))
        XCTAssertTrue(snap.statusLine.contains("send failed"))

        driver.state = .failed
        snap = OutputPresentationSnapshot.from(health: [driver.healthSnapshot()])
        XCTAssertEqual(snap.aggregate, .failed)
    }

    func testAllDisabledYieldsDisabledAggregate() {
        let snap = OutputPresentationSnapshot.from(health: [
            OutputHealthSnapshot(
                driverID: UUID(),
                name: "Null",
                outputProtocol: .local,
                state: .disabled
            )
        ])
        XCTAssertEqual(snap.aggregate, .disabled)
    }

    /// ST-02: Null-only (disabled) never looks healthy.
    func testNullOnlyIsDisabledEvenWhenRunningSink() {
        let null = NullOutputDriver()
        try? null.start()
        let snap = OutputPresentationSnapshot.from(health: [null.healthSnapshot()])
        XCTAssertEqual(snap.aggregate, .disabled)
        XCTAssertEqual(null.healthSnapshot().state, .disabled)
    }

    /// ST-02: Null + ready Art-Net → healthy.
    func testNullPlusReadyNetworkIsHealthy() {
        let null = NullOutputDriver()
        try? null.start()
        let art = OutputHealthSnapshot(
            driverID: UUID(),
            name: "Art-Net",
            outputProtocol: .artNet,
            state: .ready,
            target: "255.255.255.255"
        )
        let snap = OutputPresentationSnapshot.from(health: [null.healthSnapshot(), art])
        XCTAssertEqual(snap.aggregate, .healthy)
    }

    /// ST-02: Null + failed driver → failed.
    func testNullPlusFailedIsFailed() {
        let null = NullOutputDriver()
        try? null.start()
        let failed = OutputHealthSnapshot(
            driverID: UUID(),
            name: "Art-Net",
            outputProtocol: .artNet,
            state: .failed,
            lastError: "bind failed"
        )
        let snap = OutputPresentationSnapshot.from(health: [null.healthSnapshot(), failed])
        XCTAssertEqual(snap.aggregate, .failed)
    }
}
