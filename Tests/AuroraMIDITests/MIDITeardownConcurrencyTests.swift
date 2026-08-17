import AuroraMIDI
import CoreMIDI
import XCTest

/// Hardware-dependent quit freezes: CoreMIDI dispose/disconnect must not run under the
/// manager lock while packet/notification callbacks still need that lock.
final class MIDITeardownConcurrencyTests: XCTestCase {

    /// Flood a virtual source while calling `stop()` from another thread.
    /// Pre-fix: stop held the lock across `MIDIPortDisconnectSource`, so an active
    /// input callback waiting for the lock deadlocked permanently.
    func testInputStopWhileVirtualSourceFloodingDoesNotDeadlock() throws {
        let manager = MIDIInputManager()
        try manager.start()
        defer { manager.stop() }

        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        XCTAssertEqual(MIDIClientCreate("AuroraTeardownTestClient" as CFString, nil, nil, &client), noErr)
        defer {
            if client != 0 { MIDIClientDispose(client) }
        }
        XCTAssertEqual(
            MIDISourceCreate(client, "AuroraTeardownVirtualSrc" as CFString, &source),
            noErr
        )
        defer {
            if source != 0 { MIDIEndpointDispose(source) }
        }

        // Hotplug reconcile should pick up the virtual source.
        try manager.reconcileSources()
        // Brief settle so CoreMIDI finishes connect.
        Thread.sleep(forTimeInterval: 0.05)

        let flood = DispatchQueue(label: "aurora.midi.teardown.flood", qos: .userInitiated)
        let stopQ = DispatchQueue(label: "aurora.midi.teardown.stop", qos: .userInitiated)
        let flooding = AtomicFlag(true)

        flood.async {
            var packet = MIDIPacket()
            packet.timeStamp = 0
            packet.length = 3
            packet.data.0 = 0x90
            packet.data.1 = 60
            packet.data.2 = 100
            var list = MIDIPacketList(numPackets: 1, packet: packet)
            while flooding.value {
                _ = MIDIReceived(source, &list)
            }
        }

        // Overlap flood with stop.
        Thread.sleep(forTimeInterval: 0.02)

        let stopDone = expectation(description: "MIDIInputManager.stop returns")
        stopQ.async {
            manager.stop()
            stopDone.fulfill()
        }

        // If the old lock-order bug regresses, this times out (deadlock).
        wait(for: [stopDone], timeout: 3.0)
        flooding.set(false)
        // Drain flood queue.
        let drain = expectation(description: "flood drained")
        flood.async { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        // stop is idempotent
        manager.stop()
        XCTAssertEqual(manager.connectedCount, 0)
    }

    /// Output `stop()` must not hold the lock across `MIDIClientDispose`, because the
    /// client notification block calls `reconcileDestinations()` which needs the lock.
    func testOutputStopWhileConcurrentReconcileDoesNotDeadlock() throws {
        let manager = MIDIOutputManager()
        try manager.start()

        let reconcileQ = DispatchQueue(label: "aurora.midi.out.reconcile", qos: .userInitiated)
        let stopQ = DispatchQueue(label: "aurora.midi.out.stop", qos: .userInitiated)
        let reconciling = AtomicFlag(true)

        reconcileQ.async {
            while reconciling.value {
                try? manager.reconcileDestinations()
            }
        }

        Thread.sleep(forTimeInterval: 0.02)

        let stopDone = expectation(description: "MIDIOutputManager.stop returns")
        stopQ.async {
            manager.stop()
            stopDone.fulfill()
        }

        wait(for: [stopDone], timeout: 3.0)
        reconciling.set(false)
        let drain = expectation(description: "reconcile drained")
        reconcileQ.async { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        manager.stop()
        XCTAssertTrue(manager.destinationIDs.isEmpty)
    }

    /// Repeated start/stop with a virtual source present must stay deadlock-free.
    func testInputStartStopCyclesWithVirtualSource() throws {
        var client = MIDIClientRef()
        var source = MIDIEndpointRef()
        XCTAssertEqual(MIDIClientCreate("AuroraTeardownCycleClient" as CFString, nil, nil, &client), noErr)
        defer { if client != 0 { MIDIClientDispose(client) } }
        XCTAssertEqual(
            MIDISourceCreate(client, "AuroraTeardownCycleSrc" as CFString, &source),
            noErr
        )
        defer { if source != 0 { MIDIEndpointDispose(source) } }

        let manager = MIDIInputManager()
        for _ in 0..<8 {
            try manager.start()
            try manager.reconcileSources()
            let stopDone = expectation(description: "cycle stop")
            DispatchQueue.global(qos: .userInitiated).async {
                manager.stop()
                stopDone.fulfill()
            }
            wait(for: [stopDone], timeout: 2.0)
        }
    }
}

// MARK: - Helpers

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ value: Bool) { _value = value }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func set(_ value: Bool) {
        lock.lock()
        _value = value
        lock.unlock()
    }
}
