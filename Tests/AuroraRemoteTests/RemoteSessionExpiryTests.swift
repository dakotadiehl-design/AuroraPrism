import AuroraRemote
import XCTest

final class RemoteSessionExpiryTests: XCTestCase {
    func testReclaimInactiveFreesClientSlots() {
        var config = RemoteHostConfig(enabled: true, pin: "123456", maxClients: 2, sessionIdleTTL: 30)
        let sessions = RemoteSessionManager(config: config)
        let t0: TimeInterval = 1_000
        _ = sessions.handleHello(clientId: "a", protocolVersion: AuroraRemoteModule.protocolVersion, pin: "123456", displayName: "A", now: t0)
        _ = sessions.handleHello(clientId: "b", protocolVersion: AuroraRemoteModule.protocolVersion, pin: "123456", displayName: "B", now: t0)
        XCTAssertEqual(sessions.clientsSnapshot.count, 2)
        // Idle past TTL
        let reclaimed = sessions.reclaimInactive(now: t0 + 60)
        XCTAssertEqual(reclaimed.count, 2)
        XCTAssertTrue(sessions.clientsSnapshot.isEmpty)
        // New client can connect
        let r = sessions.handleHello(clientId: "c", protocolVersion: AuroraRemoteModule.protocolVersion, pin: "123456", displayName: "C", now: t0 + 61)
        if case .welcome = r {
            XCTAssertEqual(sessions.clientsSnapshot.count, 1)
        } else {
            XCTFail("expected welcome after reclaim")
        }
        _ = config
    }

    func testClientIdReuseOnReload() {
        let sessions = RemoteSessionManager(config: RemoteHostConfig(enabled: true, pin: "999999", maxClients: 2))
        let first = sessions.handleHello(clientId: "browser", protocolVersion: AuroraRemoteModule.protocolVersion, pin: "999999", displayName: "Pad", now: 10)
        let second = sessions.handleHello(clientId: "browser", protocolVersion: AuroraRemoteModule.protocolVersion, pin: "999999", displayName: "Pad", now: 20)
        guard case .welcome(let a) = first, case .welcome(let b) = second else {
            return XCTFail("expected welcome")
        }
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(sessions.clientsSnapshot.count, 1)
    }

    func testLoopbackBindHost() {
        XCTAssertEqual(RemoteSessionManager.listenerHost(for: .loopbackOnly), "127.0.0.1")
        XCTAssertNil(RemoteSessionManager.listenerHost(for: .privateLAN))
    }
}
