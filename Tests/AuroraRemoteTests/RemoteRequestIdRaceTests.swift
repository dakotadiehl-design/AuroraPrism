import AuroraRemote
import XCTest

/// UI10-02: concurrent duplicate requestIds execute the action at most once.
final class RemoteRequestIdRaceTests: XCTestCase {
    func testConcurrentSameRequestIdReservesOnce() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "123456", maxClients: 4)
        )
        let hello = sessions.handleHello(
            clientId: "race-client",
            protocolVersion: AuroraRemoteModule.protocolVersion,
            pin: "123456",
            displayName: "race"
        )
        guard case .welcome(let info) = hello else {
            return XCTFail("expected welcome")
        }

        let requestId = "go-race-1"
        let iterations = 20
        let group = DispatchGroup()
        let lock = NSLock()
        var executeCount = 0
        var inFlightCount = 0
        var completedCount = 0

        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = sessions.reserveRequestId(sessionId: info.id, requestId: requestId)
                lock.lock()
                switch result {
                case .execute:
                    executeCount += 1
                    // Simulate work, then complete.
                    sessions.completeRequestId(
                        sessionId: info.id,
                        requestId: requestId,
                        accepted: true,
                        reason: nil
                    )
                case .inFlight:
                    inFlightCount += 1
                case .completed:
                    completedCount += 1
                }
                lock.unlock()
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(executeCount, 1, "exactly one caller may execute")
        XCTAssertEqual(executeCount + inFlightCount + completedCount, iterations)
    }

    func testDuplicateAfterCompleteReturnsCompleted() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "123456")
        )
        let hello = sessions.handleHello(
            clientId: "dup",
            protocolVersion: AuroraRemoteModule.protocolVersion,
            pin: "123456",
            displayName: nil
        )
        guard case .welcome(let info) = hello else {
            return XCTFail("welcome")
        }
        XCTAssertEqual(
            sessions.reserveRequestId(sessionId: info.id, requestId: "x"),
            .execute
        )
        sessions.completeRequestId(sessionId: info.id, requestId: "x", accepted: true, reason: nil)
        XCTAssertEqual(
            sessions.reserveRequestId(sessionId: info.id, requestId: "x"),
            .completed(accepted: true, reason: nil, snapshotRevision: 0)
        )
    }

    func testKickClearsRequestCache() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "123456")
        )
        let hello = sessions.handleHello(
            clientId: "kick",
            protocolVersion: AuroraRemoteModule.protocolVersion,
            pin: "123456",
            displayName: nil
        )
        guard case .welcome(let info) = hello else {
            return XCTFail("welcome")
        }
        XCTAssertEqual(sessions.reserveRequestId(sessionId: info.id, requestId: "a"), .execute)
        sessions.completeRequestId(sessionId: info.id, requestId: "a", accepted: true, reason: nil, snapshotRevision: 3)
        _ = sessions.kickAll()
        // After kick, same id is treated as new (cache cleared).
        XCTAssertEqual(sessions.reserveRequestId(sessionId: info.id, requestId: "a"), .execute)
    }

    func testSnapshotTouchPreventsIdleReclaim() {
        var config = RemoteHostConfig(enabled: true, pin: "123456", maxClients: 2, sessionIdleTTL: 30)
        let sessions = RemoteSessionManager(config: config)
        let t0: TimeInterval = 1_000
        let hello = sessions.handleHello(
            clientId: "poller",
            protocolVersion: AuroraRemoteModule.protocolVersion,
            pin: "123456",
            displayName: nil,
            now: t0
        )
        guard case .welcome(let info) = hello else {
            return XCTFail("welcome")
        }
        // Keep touching as if snapshot polling.
        sessions.touch(sessionId: info.id, now: t0 + 20)
        sessions.touch(sessionId: info.id, now: t0 + 40)
        let reclaimed = sessions.reclaimInactive(now: t0 + 50)
        XCTAssertTrue(reclaimed.isEmpty)
        XCTAssertEqual(sessions.clientsSnapshot.count, 1)

        // Truly idle past TTL.
        let reclaimed2 = sessions.reclaimInactive(now: t0 + 200)
        XCTAssertEqual(reclaimed2, [info.id])
    }
}
