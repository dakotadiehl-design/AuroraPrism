import AuroraRemote
import XCTest

final class RemoteProtocolClientTests: XCTestCase {
    func testClientHelloAndWelcome() throws {
        let client = RemoteProtocolClient(clientId: "pad-1", displayName: "Pad")
        let helloData = try client.makeHello(pin: "0000")
        let hello = try RemoteCodec.decodeClient(helloData)
        guard case .hello(let id, let ver, let pin, let name) = hello else {
            return XCTFail("hello")
        }
        XCTAssertEqual(id, "pad-1")
        XCTAssertEqual(ver, 1)
        XCTAssertEqual(pin, "0000")
        XCTAssertEqual(name, "Pad")

        let sessions = RemoteSessionManager(config: RemoteHostConfig(enabled: true, pin: "0000"))
        let host = RemoteHost(sessions: sessions)
        let response = host.handle(sessionId: nil, message: hello)
        let responseData = try RemoteCodec.encodeServer(response!)
        XCTAssertTrue(try client.handleServerMessage(responseData))
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(client.role, .operatorRole)
    }

    func testClientCommandEncode() throws {
        let client = RemoteProtocolClient()
        let data = try client.makeCommand(.fireCueIndex(3))
        let msg = try RemoteCodec.decodeClient(data)
        XCTAssertEqual(msg, .command(.fireCueIndex(3)))
    }

    func testRejectClearsSession() throws {
        let client = RemoteProtocolClient()
        let welcome = try RemoteCodec.encodeServer(
            .welcome(sessionId: UUID(), role: .viewer, protocolVersion: 1)
        )
        XCTAssertTrue(try client.handleServerMessage(welcome))
        let reject = try RemoteCodec.encodeServer(.reject(reason: "bye"))
        XCTAssertFalse(try client.handleServerMessage(reject))
        XCTAssertFalse(client.isConnected)
    }
}
