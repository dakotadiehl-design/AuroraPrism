import AuroraRemote
import XCTest

final class RemoteHardeningTests: XCTestCase {
    func testClientLimit() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "1", maxClients: 1)
        )
        XCTAssertEqual(
            resultKind(sessions.handleHello(clientId: "a", protocolVersion: 1, pin: "1", displayName: nil)),
            "welcome"
        )
        XCTAssertEqual(
            sessions.handleHello(clientId: "b", protocolVersion: 1, pin: "1", displayName: nil),
            .reject("client limit reached")
        )
    }

    func testEmptyPINRejected() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "", maxClients: 2)
        )
        XCTAssertEqual(
            sessions.handleHello(clientId: "a", protocolVersion: 1, pin: "", displayName: nil),
            .reject("PIN not configured")
        )
    }

    func testRateLimit() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "1", maxCommandsPerSecond: 3)
        )
        guard case .welcome(let info) = sessions.handleHello(
            clientId: "op",
            protocolVersion: 1,
            pin: "1",
            displayName: nil
        ) else {
            return XCTFail("welcome")
        }
        let t0 = 1000.0
        XCTAssertNotNil(sessions.authorize(sessionId: info.id, action: .go, now: t0))
        XCTAssertNotNil(sessions.authorize(sessionId: info.id, action: .go, now: t0 + 0.1))
        XCTAssertNotNil(sessions.authorize(sessionId: info.id, action: .go, now: t0 + 0.2))
        XCTAssertNil(sessions.authorize(sessionId: info.id, action: .go, now: t0 + 0.3))
        // Next window
        XCTAssertNotNil(sessions.authorize(sessionId: info.id, action: .go, now: t0 + 1.05))
    }

    func testKickRemovesAuthorization() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "1")
        )
        guard case .welcome(let info) = sessions.handleHello(
            clientId: "op",
            protocolVersion: 1,
            pin: "1",
            displayName: nil
        ) else {
            return XCTFail("welcome")
        }
        XCTAssertTrue(sessions.kick(sessionId: info.id))
        XCTAssertNil(sessions.authorize(sessionId: info.id, action: .go))
    }

    func testLockDowngradesExistingOperators() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "1", lockedToViewer: false)
        )
        guard case .welcome(let info) = sessions.handleHello(
            clientId: "op",
            protocolVersion: 1,
            pin: "1",
            displayName: nil
        ) else {
            return XCTFail("welcome")
        }
        XCTAssertEqual(info.role, .operatorRole)
        sessions.setLockedToViewer(true)
        XCTAssertEqual(sessions.clientsSnapshot.first?.role, .viewer)
        XCTAssertNil(sessions.authorize(sessionId: info.id, action: .go))
    }

    private func resultKind(_ result: RemoteSessionManager.HelloResult) -> String {
        switch result {
        case .welcome: return "welcome"
        case .reject: return "reject"
        }
    }
}
