import AuroraRemote
import XCTest

final class RemoteWebServerTests: XCTestCase {
    func testHealthAndIndex() {
        let sessions = RemoteSessionManager(config: RemoteHostConfig(enabled: true, pin: "1234"))
        let html = Data("<html>hi</html>".utf8)
        let server = RemoteWebServer(sessions: sessions, indexHTML: html)
        let health = server.handleHTTP(method: "GET", path: "/api/health", headers: [:], body: nil)
        XCTAssertEqual(health.status, 200)
        let index = server.handleHTTP(method: "GET", path: "/", headers: [:], body: nil)
        XCTAssertEqual(index.status, 200)
        XCTAssertEqual(index.body, html)
    }

    func testHelloCommandSnapshotFlow() throws {
        let sessions = RemoteSessionManager(config: RemoteHostConfig(enabled: true, pin: "1234"))
        let server = RemoteWebServer(sessions: sessions, indexHTML: Data())
        let exp = expectation(description: "go")
        server.setActionHandler { action in
            XCTAssertEqual(action, .go)
            exp.fulfill()
        }
        server.setSnapshotProvider {
            RemoteSnapshot(showName: "Demo", engineRunning: true, cueIndex: 0, cueName: "Open")
        }

        let helloBody = try JSONSerialization.data(withJSONObject: [
            "clientId": "web1",
            "pin": "1234",
            "displayName": "Pad",
        ])
        let hello = server.handleHTTP(method: "POST", path: "/api/hello", headers: [:], body: helloBody)
        XCTAssertEqual(hello.status, 200)
        let obj = try JSONSerialization.jsonObject(with: hello.body) as? [String: Any]
        let token = obj?["token"] as? String
        XCTAssertNotNil(token)

        let cmdBody = try JSONSerialization.data(withJSONObject: [
            "action": ["name": "go"],
        ])
        let cmd = server.handleHTTP(
            method: "POST",
            path: "/api/command",
            headers: ["X-Aurora-Token": token!],
            body: cmdBody
        )
        XCTAssertEqual(cmd.status, 200)
        wait(for: [exp], timeout: 1)

        let snap = server.handleHTTP(
            method: "GET",
            path: "/api/snapshot",
            headers: ["X-Aurora-Token": token!],
            body: nil
        )
        XCTAssertEqual(snap.status, 200)
        let decoded = try JSONDecoder().decode(RemoteSnapshot.self, from: snap.body)
        XCTAssertEqual(decoded.showName, "Demo")
        XCTAssertEqual(decoded.cueIndex, 0)
    }

    func testBadPIN() throws {
        let sessions = RemoteSessionManager(config: RemoteHostConfig(enabled: true, pin: "9999"))
        let server = RemoteWebServer(sessions: sessions, indexHTML: Data())
        let helloBody = try JSONSerialization.data(withJSONObject: [
            "clientId": "web1",
            "pin": "0000",
        ])
        let hello = server.handleHTTP(method: "POST", path: "/api/hello", headers: [:], body: helloBody)
        XCTAssertEqual(hello.status, 401)
    }
}
