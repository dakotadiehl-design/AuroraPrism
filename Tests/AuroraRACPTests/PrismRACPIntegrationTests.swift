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
    func testAdvertisementAndHelloShareAuthoritativeIdentity() throws {
        let configuration = PrismRACPConfiguration(
            enabled: true,
            port: 9_000,
            peerID: "stable-prism-id"
        )

        let advertisement = try configuration.makeAdvertisement()
        let hello = try configuration.makeHello()

        XCTAssertEqual(
            advertisement.instanceName,
            PrismRACPConfiguration.defaultInstanceName
        )
        XCTAssertEqual(advertisement.peerID, hello.peerID)
        XCTAssertEqual(advertisement.peerType, hello.peerType)
        XCTAssertEqual(advertisement.peerType, "prism")
        XCTAssertEqual(
            advertisement.txtValues,
            ["v": "1", "id": "stable-prism-id", "type": "prism"]
        )
        XCTAssertFalse(advertisement.txtValues.keys.contains("capabilities"))
    }

    func testInstanceNameUsesFriendlyComputerName() {
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: "Stage Left Mac"),
            "Prism - Stage Left Mac"
        )
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: "  Stage Left Mac  "),
            "Prism - Stage Left Mac"
        )
    }

    func testInstanceNameFallsBackForMissingComputerName() {
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: nil),
            "Prism"
        )
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: ""),
            "Prism"
        )
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: "  \n\t"),
            "Prism"
        )
    }

    func testInstanceNameFallsBackForInvalidComputerName() {
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: "Stage\nHidden"),
            "Prism"
        )
    }

    func testInstanceNameFallsBackWhenCombinedNameExceedsDNSByteLimit() {
        let oversizedComputerName = String(repeating: "é", count: 28)
        XCTAssertEqual("Prism - \(oversizedComputerName)".utf8.count, 64)
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(
                computerName: oversizedComputerName
            ),
            "Prism"
        )
    }

    func testInstanceNameAllowsDNSByteLimitBoundary() {
        let computerName = String(repeating: "a", count: 55)
        let expected = "Prism - \(computerName)"

        XCTAssertEqual(expected.utf8.count, 63)
        XCTAssertEqual(
            PrismRACPConfiguration.resolvedInstanceName(computerName: computerName),
            expected
        )
    }

    func testAdvertisementValidationDoesNotMutateIdentity() throws {
        let invalid = PrismRACPConfiguration(
            enabled: true,
            port: 9_000,
            peerID: "stable-prism-id",
            instanceName: String(repeating: "é", count: 32)
        )

        XCTAssertThrowsError(try invalid.makeAdvertisement())
        XCTAssertEqual(invalid.peerID, "stable-prism-id")
        XCTAssertEqual(try invalid.makeHello().peerID, "stable-prism-id")
    }

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

        try await connection.subscribe(PrismRACPCapability.songList)
        let initialSongList = try await eventually {
            recorder.messages(named: PrismRACPCapability.songList).last
        }
        XCTAssertEqual(initialSongList.revision, initial.revision)

        var projectWithAddedSong = fixture.project
        let addedSong = Song(title: "New Remote Song", artist: "Test Artist")
        projectWithAddedSong.songs.append(addedSong)
        fixture.controller.applyProjectUpdate(projectWithAddedSong, orderedSelection: [])
        fixture.controller.noteAuthoritativeCommit()
        let changedSongList = try await eventually {
            recorder.messages(named: PrismRACPCapability.songList)
                .last(where: { $0.revision > initialSongList.revision })
        }
        XCTAssertTrue(try changedSongList.value.encoded().contains(addedSong.id.uuidString.lowercased()))

        try await connection.command(PrismRACPCapability.cueGo)
        let changed = try await eventually {
            recorder.messages(named: PrismRACPCapability.cueCurrent)
                .last(where: { $0.revision > changedSongList.revision })
        }
        XCTAssertEqual(changed.revision, changedSongList.revision + 1)
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

    func testMulticastAdvertisementDiscoveryConnectionAndRemoval() async throws {
        guard ProcessInfo.processInfo.environment["PRISM_RUN_MULTICAST_TESTS"] == "1" else {
            throw XCTSkip("Set PRISM_RUN_MULTICAST_TESTS=1 where multicast DNS is available")
        }

        let peerID = "prism-multicast-\(UUID().uuidString.lowercased())"
        let instanceName = "Prism Test \(UUID().uuidString)"
        let discovery = RACPNetworkDiscovery()
        let observation = await discovery.observe()
        try await discovery.start()

        let fixture = makeController()
        let service = PrismRACPService(controller: fixture.controller)
        await service.startAndWait(configuration: .init(
            enabled: true,
            port: 0,
            peerID: peerID,
            instanceName: instanceName
        ))

        do {
            let discovered = try await discover(
                peerID: peerID,
                observation: observation
            )
            XCTAssertEqual(discovered.instanceName, instanceName)
            XCTAssertEqual(discovered.peerTypeHint, PrismRACPConfiguration.peerType)

            let connection = RACPConnection(
                stream: try await NetworkByteStream.connect(endpoint: discovered.endpoint),
                session: RACPSession(
                    local: try RACPHello(peerType: "remote", peerID: "multicast-client")
                )
            )
            let run = Task { await connection.run() }
            let hello = try await connection.waitUntilReady()
            XCTAssertEqual(hello.peerID, peerID)
            XCTAssertEqual(hello.peerType, PrismRACPConfiguration.peerType)
            XCTAssertEqual(discovered.validate(peer: hello).peerID, .matches)
            XCTAssertEqual(discovered.validate(peer: hello).peerType, .matches)
            try await connection.command(PrismRACPCapability.cueGo)
            await connection.close(reason: "test_complete")
            await run.value

            await service.stopAndWait()
            let removed = try await eventuallyAsync(timeout: .seconds(10)) {
                let services = await discovery.discoveredServices()
                return services.contains(where: { $0.peerIDHint == peerID }) ? nil : true
            }
            XCTAssertTrue(removed)
            await discovery.stop()
        } catch {
            await service.stopAndWait()
            await discovery.stop()
            throw error
        }
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

    private func eventuallyAsync<T>(
        timeout: Duration,
        value: () async -> T?
    ) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let result = await value() { return result }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw RACPNetworkDiscoveryError.unavailable
    }

    private func discover(
        peerID: String,
        observation: RACPDiscoveryObservation
    ) async throws -> RACPDiscoveredService {
        try await withThrowingTaskGroup(of: RACPDiscoveredService.self) { group in
            group.addTask {
                for try await event in observation.events {
                    switch event {
                    case .added(let service) where service.peerIDHint == peerID,
                         .updated(let service) where service.peerIDHint == peerID:
                        return service
                    default:
                        continue
                    }
                }
                throw RACPNetworkDiscoveryError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw RACPNetworkDiscoveryError.unavailable
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func makeController() -> (
        controller: ShowControlController,
        cues: [Cue],
        project: ShowProject
    ) {
        let cues = [Cue(number: 1, name: "One"), Cue(number: 2, name: "Two")]
        let list = CueList(name: "Main", cues: cues)
        var project = ShowProject.empty()
        project.cueLists = [list]
        let controller = ShowControlController(output: OutputManager())
        controller.reloadFromProject(project, orderedSelection: [])
        return (controller, cues, project)
    }
}
