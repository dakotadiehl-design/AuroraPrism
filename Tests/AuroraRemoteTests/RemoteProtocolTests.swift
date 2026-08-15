import AuroraRemote
import XCTest

final class RemoteProtocolTests: XCTestCase {
    func testCodecRoundTripHelloAndWelcome() throws {
        let hello = RemoteClientMessage.hello(
            clientId: "ipad-1",
            protocolVersion: 1,
            pin: "1234",
            displayName: "Stage"
        )
        let data = try RemoteCodec.encodeClient(hello)
        let decoded = try RemoteCodec.decodeClient(data)
        XCTAssertEqual(decoded, hello)

        let welcome = RemoteServerMessage.welcome(
            sessionId: UUID(),
            role: .operatorRole,
            protocolVersion: 1
        )
        let wdata = try RemoteCodec.encodeServer(welcome)
        let wdec = try RemoteCodec.decodeServer(wdata)
        XCTAssertEqual(wdec, welcome)
    }

    func testCommandCodecFireWithRequestId() throws {
        let rid = "req-1"
        let cmd = RemoteClientMessage.command(requestId: rid, action: .fireCueIndex(2))
        let round = try RemoteCodec.decodeClient(try RemoteCodec.encodeClient(cmd))
        XCTAssertEqual(round, cmd)
    }

    func testDuplicateRequestIdDoesNotReExecute() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "42", maxClients: 2)
        )
        let hello = sessions.handleHello(
            clientId: "c1",
            protocolVersion: 1,
            pin: "42",
            displayName: nil
        )
        guard case .welcome(let info) = hello else {
            return XCTFail("welcome")
        }
        XCTAssertNil(sessions.takeRequestIdIfNew(sessionId: info.id, requestId: "go-1"))
        sessions.rememberRequestId(sessionId: info.id, requestId: "go-1", accepted: true, reason: nil)
        let prior = sessions.takeRequestIdIfNew(sessionId: info.id, requestId: "go-1")
        XCTAssertEqual(prior?.accepted, true)
    }

    func testProgrammerAttributeNotAllowed() {
        XCTAssertFalse(RemoteCommandAllowList.isAllowed(
            .setProgrammerAttribute(attribute: "intensity", value: 0.5)
        ))
        XCTAssertTrue(RemoteCommandAllowList.isAllowed(.go))
    }

    func testPINRejectAndProtocolMismatch() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "9999", maxClients: 2)
        )
        let badPin = sessions.handleHello(
            clientId: "c1",
            protocolVersion: 1,
            pin: "0000",
            displayName: nil
        )
        XCTAssertEqual(badPin, .reject("invalid PIN"))

        let badVer = sessions.handleHello(
            clientId: "c1",
            protocolVersion: 99,
            pin: "9999",
            displayName: nil
        )
        XCTAssertEqual(badVer, .reject("protocol version mismatch"))
    }

    func testViewerCannotAuthorizeCommands() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "1", lockedToViewer: true)
        )
        guard case .welcome(let info) = sessions.handleHello(
            clientId: "v",
            protocolVersion: 1,
            pin: "1",
            displayName: "V"
        ) else {
            return XCTFail("expected welcome")
        }
        XCTAssertEqual(info.role, .viewer)
        XCTAssertNil(sessions.authorize(sessionId: info.id, action: .go))
    }

    func testOperatorAllowList() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "1", lockedToViewer: false)
        )
        guard case .welcome(let info) = sessions.handleHello(
            clientId: "op",
            protocolVersion: 1,
            pin: "1",
            displayName: "Op"
        ) else {
            return XCTFail("expected welcome")
        }
        XCTAssertEqual(sessions.authorize(sessionId: info.id, action: .go), .go)
        XCTAssertEqual(
            sessions.authorize(sessionId: info.id, action: .fireCueIndex(0)),
            .fireCueIndex(0)
        )
    }

    func testHostHandleWithoutNetwork() {
        let sessions = RemoteSessionManager(
            config: RemoteHostConfig(enabled: true, pin: "42")
        )
        let host = RemoteHost(sessions: sessions)
        let exp = expectation(description: "action")
        host.setActionHandler { action in
            XCTAssertEqual(action, .stop)
            exp.fulfill()
        }
        let welcome = host.handle(
            sessionId: nil,
            message: .hello(clientId: "t", protocolVersion: 1, pin: "42", displayName: nil)
        )
        guard case .welcome(let sid, let role, _) = welcome else {
            return XCTFail("welcome")
        }
        XCTAssertEqual(role, .operatorRole)
        _ = host.handle(sessionId: sid, message: .command(requestId: "stop-1", action: .stop))
        wait(for: [exp], timeout: 1)
    }

    func testDisabledHostRejects() {
        let sessions = RemoteSessionManager(config: RemoteHostConfig(enabled: false, pin: "1"))
        let host = RemoteHost(sessions: sessions)
        let response = host.handle(
            sessionId: nil,
            message: .hello(clientId: "x", protocolVersion: 1, pin: "1", displayName: nil)
        )
        XCTAssertEqual(response, .reject(reason: "remote disabled"))
    }
}
