import AuroraModel
import AuroraOutput
import Foundation
import ReasonableACP
import XCTest
@testable import Aurora

private final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StateMessage] = []

    func append(_ state: StateMessage) {
        lock.lock()
        storage.append(state)
        lock.unlock()
    }

    func messages(named name: String) -> [StateMessage] {
        lock.lock()
        defer { lock.unlock() }
        return storage.filter { $0.name == name }
    }
}

@MainActor
final class PrismRACPIntegrationTests: XCTestCase {
    func testCapabilitiesAreCanonicalAndAdapterValidatesCommands() throws {
        XCTAssertEqual(PrismRACPCapability.all, PrismRACPCapability.all.sorted())
        XCTAssertEqual(Set(PrismRACPCapability.all).count, PrismRACPCapability.all.count)

        let fixture = makeController()
        let invalidGo = Command(
            requestID: 1,
            name: PrismRACPCapability.cueGo,
            value: .bool(true),
            hasValue: true
        )
        XCTAssertEqual(
            PrismRACPCommandAdapter.execute(invalidGo, controller: fixture.controller, sessionID: "test"),
            .error("invalid_value")
        )
        XCTAssertEqual(fixture.controller.stateRevision, 0)

        let master = Command(
            requestID: 2,
            name: PrismRACPCapability.outputGrandMasterSet,
            value: .number(0.25),
            hasValue: true
        )
        XCTAssertEqual(
            PrismRACPCommandAdapter.execute(master, controller: fixture.controller, sessionID: "test"),
            .success
        )
        XCTAssertEqual(fixture.controller.engine.globalShowControl.masterIntensity, 0.25)
        XCTAssertEqual(fixture.controller.stateRevision, 1)

        let unknown = Command(requestID: 3, name: "prism.unknown")
        XCTAssertEqual(
            PrismRACPCommandAdapter.execute(unknown, controller: fixture.controller, sessionID: "test"),
            .error("unsupported_capability")
        )
    }

    func testStateProjectionProvidesEveryAdvertisedStateAtOneRevision() throws {
        let controller = makeController().controller
        XCTAssertTrue(controller.go())
        let snapshot = controller.racpStateSnapshot()
        let messages = snapshot.allStateMessages(wireRevision: controller.stateRevision)

        XCTAssertEqual(Set(messages.map(\.name)), PrismRACPCapability.stateNames)
        XCTAssertEqual(Set(messages.map(\.revision)), [controller.stateRevision])
        XCTAssertTrue(messages.allSatisfy { $0.value != .null })
        for message in messages {
            XCTAssertFalse(try message.value.encoded().isEmpty)
        }
    }

    func testLoopbackConversationPublishesInitialAndChangedState() async throws {
        let fixture = makeController()
        let service = PrismRACPService(controller: fixture.controller)
        await service.startAndWait(configuration: .init(
            enabled: true,
            port: 0,
            peerID: "prism-test",
            binding: .loopback
        ))
        defer { Task { @MainActor in await service.stopAndWait() } }

        let port = try await eventually { service.snapshot.port }
        let recorder = StateRecorder()
        let session = RACPSession(
            local: try RACPHello(
                peerType: "remote",
                peerID: "integration-test",
                capabilities: PrismRACPCapability.all
            ),
            stateHandler: { recorder.append($0) }
        )
        let connection = RACPConnection(
            stream: try await NetworkByteStream.connect(host: "127.0.0.1", port: port),
            session: session,
            // Incoming STATE frames are solicited by this test's SUB request,
            // but rACP intentionally leaves outgoing subscription bookkeeping
            // to the caller rather than mutating RACPSession.subscriptions.
            allowUnsolicitedState: true
        )
        let run = Task { await connection.run() }
        let peer = try await connection.waitUntilReady()
        XCTAssertEqual(peer.peerType, "prism")
        XCTAssertEqual(peer.capabilities, PrismRACPCapability.all)

        try await connection.subscribe(PrismRACPCapability.cueCurrent)
        let initial = try await eventually {
            recorder.messages(named: PrismRACPCapability.cueCurrent).last
        }
        XCTAssertEqual(initial.revision, 0)

        try await connection.command(PrismRACPCapability.cueGo)
        let changed = try await eventually {
            recorder.messages(named: PrismRACPCapability.cueCurrent)
                .last(where: { $0.revision > initial.revision })
        }
        XCTAssertEqual(changed.revision, 1)
        XCTAssertEqual(fixture.controller.engine.playback.snapshot().cueID, fixture.cues[0].id)
        XCTAssertEqual(service.snapshot.clientCount, 1)

        // Prism revisions reset when a document becomes a new authority epoch;
        // the rACP transport revision must remain strictly increasing for an
        // already-connected subscriber.
        fixture.controller.noteAuthoritativeCommit()
        let beforeEpochChange = try await eventually {
            recorder.messages(named: PrismRACPCapability.cueCurrent)
                .last(where: { $0.revision > changed.revision })
        }
        fixture.controller.noteAuthoritativeCommit(replacingUniverse: true)
        let afterEpochChange = try await eventually {
            recorder.messages(named: PrismRACPCapability.cueCurrent)
                .last(where: { $0.revision > beforeEpochChange.revision })
        }
        XCTAssertEqual(fixture.controller.stateRevision, 1)
        XCTAssertGreaterThan(afterEpochChange.revision, beforeEpochChange.revision)

        do {
            try await connection.command("prism.unknown")
            XCTFail("Unsupported commands must fail")
        } catch let error as RACPRemoteError {
            XCTAssertEqual(error.code, "unsupported_capability")
        }

        await connection.close(reason: "test_complete")
        await run.value
        await service.stopAndWait()
    }

    func testSecondListenerReportsBindFailureAndShutdownClosesClients() async throws {
        let firstController = makeController().controller
        let first = PrismRACPService(controller: firstController)
        await first.startAndWait(configuration: .init(
            enabled: true, port: 0, peerID: "first", binding: .loopback
        ))
        let port = try await eventually { first.snapshot.port }

        let second = PrismRACPService(controller: makeController().controller)
        await second.startAndWait(configuration: .init(
            enabled: true, port: port, peerID: "second", binding: .loopback
        ))
        _ = try await eventually {
            second.snapshot.state == .failed ? second.snapshot.lastError : nil
        }

        let connection = RACPConnection(
            stream: try await NetworkByteStream.connect(host: "127.0.0.1", port: port),
            session: RACPSession(local: try RACPHello(peerType: "remote", peerID: "shutdown-test"))
        )
        let run = Task { await connection.run() }
        _ = try await connection.waitUntilReady()
        await first.stopAndWait()

        do {
            try await connection.command(PrismRACPCapability.cueGo, timeout: .milliseconds(250))
            XCTFail("A stopped service must not accept commands")
        } catch {
            // Disconnection is the expected terminal result.
        }
        await run.value
        await second.stopAndWait()
    }

    func testMultipleClientsReceiveStateAndDisconnectIndependently() async throws {
        let fixture = makeController()
        let service = PrismRACPService(controller: fixture.controller)
        await service.startAndWait(configuration: .init(
            enabled: true, port: 0, peerID: "multi", binding: .loopback
        ))
        let port = try await eventually { service.snapshot.port }

        let firstRecorder = StateRecorder()
        let first = try await connectClient(port: port, peerID: "first", recorder: firstRecorder)
        let secondRecorder = StateRecorder()
        let second = try await connectClient(port: port, peerID: "second", recorder: secondRecorder)
        _ = try await eventually { service.snapshot.clientCount == 2 ? true : nil }

        try await first.connection.subscribe(PrismRACPCapability.outputBlackout)
        try await second.connection.subscribe(PrismRACPCapability.outputBlackout)
        _ = try await eventually {
            firstRecorder.messages(named: PrismRACPCapability.outputBlackout).last
        }
        _ = try await eventually {
            secondRecorder.messages(named: PrismRACPCapability.outputBlackout).last
        }

        try await first.connection.command(
            PrismRACPCapability.outputBlackoutSet,
            arguments: .bool(true)
        )
        _ = try await eventually {
            firstRecorder.messages(named: PrismRACPCapability.outputBlackout)
                .last(where: { $0.revision > 0 })
        }
        _ = try await eventually {
            secondRecorder.messages(named: PrismRACPCapability.outputBlackout)
                .last(where: { $0.revision > 0 })
        }

        await first.connection.close(reason: "first_done")
        await first.run.value
        _ = try await eventually { service.snapshot.clientCount == 1 ? true : nil }
        try await second.connection.command(PrismRACPCapability.outputBlackoutSet, arguments: .bool(false))

        await second.connection.close(reason: "second_done")
        await second.run.value
        await service.stopAndWait()
    }

    func testMalformedWireInputIsIsolatedAndListenerRemainsAvailable() async throws {
        let fixture = makeController()
        let service = PrismRACPService(controller: fixture.controller)
        await service.startAndWait(configuration: .init(
            enabled: true, port: 0, peerID: "malformed", binding: .loopback
        ))
        let port = try await eventually { service.snapshot.port }

        let stream = try await NetworkByteStream.connect(host: "127.0.0.1", port: port)
        _ = try await stream.read(maximum: 16_384)
        let hello = try RACPHello(peerType: "remote", peerID: "malformed-client")
        try await stream.write(hello.encoded)
        try await stream.write(Data("THIS IS NOT RACP\n".utf8))
        let response = try await stream.read(maximum: 16_384)
        XCTAssertTrue(response.isEmpty || String(decoding: response, as: UTF8.self).contains("ERR"))
        await stream.close()

        let healthy = try await connectClient(port: port, peerID: "healthy")
        try await healthy.connection.command(PrismRACPCapability.cueGo)
        XCTAssertEqual(fixture.controller.engine.playback.snapshot().cueID, fixture.cues[0].id)
        await healthy.connection.close(reason: "healthy_done")
        await healthy.run.value
        await service.stopAndWait()
    }

    func testUnavailableControllerReturnsProtocolError() async throws {
        var controller: ShowControlController? = makeController().controller
        let service = PrismRACPService(controller: try XCTUnwrap(controller))
        await service.startAndWait(configuration: .init(
            enabled: true, port: 0, peerID: "unavailable", binding: .loopback
        ))
        let port = try await eventually { service.snapshot.port }
        controller = nil

        let client = try await connectClient(port: port, peerID: "unavailable-client")
        do {
            try await client.connection.command(PrismRACPCapability.cueGo)
            XCTFail("Commands must fail when the application controller is gone")
        } catch let error as RACPRemoteError {
            XCTAssertEqual(error.code, "unavailable")
        }
        await client.connection.close(reason: "test_done")
        await client.run.value
        await service.stopAndWait()
    }

    func testRapidReconfigurationConvergesOnLatestListener() async throws {
        let fixture = makeController()
        let service = PrismRACPService(controller: fixture.controller)
        service.apply(configuration: .init(
            enabled: true, port: 0, peerID: "first-run", binding: .loopback
        ))
        service.apply(configuration: .init(
            enabled: false, port: 0, peerID: "disabled", binding: .loopback
        ))
        service.apply(configuration: .init(
            enabled: true, port: 0, peerID: "final-run", binding: .loopback
        ))

        let port = try await eventually {
            service.snapshot.state == .listening ? service.snapshot.port : nil
        }
        let client = try await connectClient(port: port, peerID: "reconfigure-client")
        XCTAssertEqual(client.peer.peerID, "final-run")
        await client.connection.close(reason: "test_done")
        await client.run.value
        await service.stopAndWait()
    }

    private func connectClient(
        port: UInt16,
        peerID: String,
        recorder: StateRecorder? = nil
    ) async throws -> (
        connection: RACPConnection,
        run: Task<Void, Never>,
        peer: RACPHello
    ) {
        let session = RACPSession(
            local: try RACPHello(
                peerType: "remote",
                peerID: peerID,
                capabilities: PrismRACPCapability.all
            ),
            stateHandler: { recorder?.append($0) }
        )
        let connection = RACPConnection(
            stream: try await NetworkByteStream.connect(host: "127.0.0.1", port: port),
            session: session,
            allowUnsolicitedState: true
        )
        let run = Task { await connection.run() }
        let peer = try await connection.waitUntilReady()
        return (connection, run, peer)
    }

    private func eventually<T>(
        timeout: Duration = .seconds(3),
        value: @MainActor () -> T?
    ) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let result = value() { return result }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for asynchronous integration state")
        throw NSError(
            domain: "PrismRACPIntegrationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for asynchronous integration state"]
        )
    }

    private func makeController() -> (controller: ShowControlController, cues: [Cue]) {
        let cues = [Cue(number: 1, name: "One"), Cue(number: 2, name: "Two")]
        let list = CueList(name: "Main", cues: cues)
        var project = ShowProject.empty()
        project.cueLists = [list]
        let controller = ShowControlController(output: OutputManager())
        controller.reloadFromProject(project, orderedSelection: [])
        return (controller, cues)
    }
}
