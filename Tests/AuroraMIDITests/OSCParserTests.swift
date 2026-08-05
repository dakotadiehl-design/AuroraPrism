import AuroraMIDI
import XCTest

final class OSCParserTests: XCTestCase {
    func testParseGoAddress() {
        let data = encodeMessage(address: "/aurora/go", typeTag: ",", args: Data())
        let messages = OSCParser.parse(packet: data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].address, "/aurora/go")
        let mapped = OSCAddressMap.action(for: messages[0])
        XCTAssertEqual(mapped?.0, .go)
    }

    func testParseFireIndex() {
        var args = Data()
        // no args; index in path
        let data = encodeMessage(address: "/aurora/fire/2", typeTag: ",", args: args)
        let messages = OSCParser.parse(packet: data)
        let mapped = OSCAddressMap.action(for: messages[0])
        XCTAssertEqual(mapped?.0, .fireCueIndex(2))
    }

    func testParseProgrammerFloat() {
        var args = Data()
        var bits = Float(0.5).bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { args.append(contentsOf: $0) }
        let data = encodeMessage(address: "/aurora/programmer/intensity", typeTag: ",f", args: args)
        let messages = OSCParser.parse(packet: data)
        let mapped = OSCAddressMap.action(for: messages[0])
        XCTAssertEqual(mapped?.0, .programmerAttribute("intensity"))
        XCTAssertEqual(mapped?.value ?? -1, 0.5, accuracy: 0.001)
    }

    func testLegacyGo() {
        let data = encodeMessage(address: "/go", typeTag: ",", args: Data())
        let msg = OSCParser.parse(packet: data)[0]
        XCTAssertEqual(OSCAddressMap.action(for: msg)?.0, .go)
    }

    func testServerHandleInvokesHandler() {
        let server = OSCInputServer(port: 0)
        let exp = expectation(description: "action")
        server.setHandler { action, _ in
            XCTAssertEqual(action, .stop)
            exp.fulfill()
        }
        let data = encodeMessage(address: "/aurora/stop", typeTag: ",", args: Data())
        server.handle(packet: data)
        wait(for: [exp], timeout: 1)
    }

    /// Build a minimal OSC message packet.
    private func encodeMessage(address: String, typeTag: String, args: Data) -> Data {
        var data = Data()
        data.append(oscString(address))
        data.append(oscString(typeTag))
        data.append(args)
        return data
    }

    private func oscString(_ s: String) -> Data {
        var d = Data(s.utf8)
        d.append(0)
        while d.count % 4 != 0 { d.append(0) }
        return d
    }
}
