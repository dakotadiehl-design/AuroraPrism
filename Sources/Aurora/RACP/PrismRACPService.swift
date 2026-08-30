import AuroraDiagnostics
import Combine
import Foundation
import ReasonableACP

struct PrismRACPConfiguration: Equatable, Sendable {
    static let peerType = "prism"
    static let fallbackInstanceName = "Prism"
    static let defaultInstanceName = resolvedInstanceName(
        computerName: Host.current().localizedName
    )

    var enabled: Bool
    var port: UInt16
    var peerID: String
    var instanceName: String = Self.defaultInstanceName
    var maximumConnections: Int = 16
    var binding: RACPNetworkServerBinding = .allInterfaces

    static func resolvedInstanceName(computerName: String?) -> String {
        guard let computerName else {
            return fallbackInstanceName
        }
        let normalizedComputerName = computerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedComputerName.isEmpty else {
            return fallbackInstanceName
        }
        let instanceName = "Prism - \(normalizedComputerName)"
        guard (try? RACPNetworkAdvertisement(
            instanceName: instanceName,
            peerID: "prism",
            peerType: peerType
        )) != nil else {
            return fallbackInstanceName
        }
        return instanceName
    }

    func makeHello() throws -> RACPHello {
        try RACPHello(
            peerType: Self.peerType,
            peerID: peerID,
            capabilities: PrismRACPCapability.all
        )
    }

    func makeAdvertisement() throws -> RACPNetworkAdvertisement {
        try RACPNetworkAdvertisement(
            instanceName: instanceName,
            peerID: peerID,
            peerType: Self.peerType
        )
    }
}

@MainActor
final class PrismRACPService: ObservableObject {
    @Published private(set) var snapshot: PrismRACPServiceSnapshot = .disabled

    private weak var controller: ShowControlController?
    private var runtime: PrismRACPRuntime?
    private var lifecycleTask: Task<Void, Never>?
    private var lastStatusSequence: UInt64 = 0

    init(controller: ShowControlController) {
        self.controller = controller
        let executeOnMain: @MainActor @Sendable (Command, String) -> RACPCommandDisposition = {
            [weak controller] command, sessionID in
            guard let controller else { return .error("unavailable") }
            return PrismRACPCommandAdapter.execute(
                command,
                controller: controller,
                sessionID: sessionID
            )
        }
        runtime = PrismRACPRuntime(
            execute: { command, sessionID in
                await executeOnMain(command, sessionID)
            },
            reportStatus: { [weak self] sequence, snapshot in
                Task { @MainActor [weak self] in
                    guard let self, sequence >= self.lastStatusSequence else { return }
                    self.lastStatusSequence = sequence
                    self.snapshot = snapshot
                }
            }
        )
        controller.onSemanticCommit = { [weak self] in
            self?.publishAuthoritativeState()
        }
    }

    func apply(configuration: PrismRACPConfiguration) {
        lifecycleTask?.cancel()
        guard let runtime else { return }
        if configuration.enabled {
            snapshot = PrismRACPServiceSnapshot(
                state: .starting,
                port: nil,
                clientCount: 0,
                lastError: nil
            )
            let initialState = controller?.racpStateSnapshot()
            lifecycleTask = Task {
                await runtime.stop(reportDisabled: false)
                guard !Task.isCancelled else { return }
                await runtime.start(configuration: configuration, initialState: initialState)
            }
        } else {
            snapshot = .disabled
            lifecycleTask = Task { await runtime.stop() }
        }
    }

    func publishAuthoritativeState() {
        guard let state = controller?.racpStateSnapshot(), let runtime else { return }
        Task { await runtime.publish(state) }
    }

    func stop() {
        lifecycleTask?.cancel()
        guard let runtime else { return }
        snapshot = .disabled
        lifecycleTask = Task { await runtime.stop() }
    }

    func stopAndWait() async {
        lifecycleTask?.cancel()
        await runtime?.stop()
        snapshot = .disabled
    }

    /// Test/support entry point that does not race an unstructured lifecycle task.
    func startAndWait(configuration: PrismRACPConfiguration) async {
        lifecycleTask?.cancel()
        let initialState = controller?.racpStateSnapshot()
        await runtime?.stop(reportDisabled: false)
        await runtime?.start(configuration: configuration, initialState: initialState)
    }
}

private actor PrismRACPRuntime {
    typealias Executor = @Sendable (Command, String) async -> RACPCommandDisposition
    typealias StatusReporter = @Sendable (UInt64, PrismRACPServiceSnapshot) -> Void

    private struct Client {
        let connection: RACPConnection
        var ready = false
        var lastPublishedRevision: [String: UInt64] = [:]
    }

    private let execute: Executor
    private let reportStatus: StatusReporter
    private var server: RACPNetworkServer?
    private var clients: [UUID: Client] = [:]
    private var latestState: PrismRACPStateSnapshot?
    private var listeningPort: UInt16?
    private var activeRunID: UUID?
    /// Monotonic for the lifetime of one listener. Prism's semantic revision may
    /// reset when the authority epoch changes, but rACP STATE revisions may not.
    private var publicationRevision: UInt64 = 0
    private var statusSequence: UInt64 = 0

    init(execute: @escaping Executor, reportStatus: @escaping StatusReporter) {
        self.execute = execute
        self.reportStatus = reportStatus
    }

    func start(configuration: PrismRACPConfiguration, initialState: PrismRACPStateSnapshot?) async {
        latestState = initialState
        publicationRevision = 0
        report(.init(state: .starting, port: nil, clientCount: 0, lastError: nil))
        let runID = UUID()
        activeRunID = runID
        do {
            let hello = try configuration.makeHello()
            let advertisement = try configuration.makeAdvertisement()
            let execute = self.execute
            let networkServer = try RACPNetworkServer(
                port: configuration.port,
                binding: configuration.binding,
                maximumConnections: configuration.maximumConnections,
                advertisement: advertisement,
                connectionHandler: { [weak self] connection in
                    Task { await self?.accept(connection, runID: runID) }
                },
                sessionFactory: {
                    let sessionID = UUID().uuidString.lowercased()
                    return RACPSession(
                        local: hello,
                        asyncCommandHandler: { command in
                            await execute(command, sessionID)
                        }
                    )
                }
            )
            server = networkServer
            try await networkServer.start()
            guard server === networkServer else {
                networkServer.cancel()
                return
            }
            listeningPort = networkServer.port
            publishStatus(state: .listening)
            PrismLog.notice(.remoteHost, "remote.racp.started", "The rACP listener started.")
        } catch {
            // A superseding configuration may have stopped or replaced this
            // listener while start() was suspended. Never tear down that newer
            // run or overwrite its status with a stale failure.
            guard activeRunID == runID else { return }
            server?.cancel()
            server = nil
            activeRunID = nil
            listeningPort = nil
            let message = String(describing: error)
            report(.init(state: .failed, port: nil, clientCount: 0, lastError: message))
            PrismLog.error(
                .remoteHost,
                "remote.racp.start_failed",
                "Prism couldn't start remote control.",
                technical: message
            )
        }
    }

    func stop(reportDisabled: Bool = true) async {
        server?.cancel()
        server = nil
        activeRunID = nil
        listeningPort = nil
        let current = clients
        clients.removeAll()
        for client in current.values {
            await client.connection.close(reason: "service_stopped")
        }
        latestState = nil
        publicationRevision = 0
        if reportDisabled { report(.disabled) }
    }

    func publish(_ state: PrismRACPStateSnapshot) async {
        if let latestState {
            let incomingVersion = (state.authorityEpoch, state.revision)
            let currentVersion = (latestState.authorityEpoch, latestState.revision)
            guard incomingVersion > currentVersion else { return }
            guard publicationRevision < racpMaximumSafeInteger else {
                for client in clients.values {
                    await client.connection.close(reason: "state_revision_exhausted")
                }
                clients.removeAll()
                publishStatus(state: server == nil ? .disabled : .listening)
                return
            }
            publicationRevision += 1
        }
        latestState = state
        let wireRevision = publicationRevision
        for name in PrismRACPCapability.stateNames.sorted() {
            await publish(
                name: name,
                state: state,
                wireRevision: wireRevision,
                to: Array(clients.keys)
            )
        }
    }

    private func accept(_ connection: RACPConnection, runID: UUID) {
        guard activeRunID == runID, server != nil else {
            Task { await connection.close(reason: "stale_listener") }
            return
        }
        let id = UUID()
        clients[id] = Client(connection: connection)
        Task { await observeLifecycle(id: id, connection: connection) }
        Task { await observeSubscriptions(id: id, connection: connection) }
    }

    private func observeLifecycle(id: UUID, connection: RACPConnection) async {
        for await state in await connection.stateUpdates() {
            switch state {
            case .ready(let peer):
                guard var client = clients[id] else { return }
                client.ready = true
                clients[id] = client
                publishStatus(state: .listening)
                // RACPNetworkServer begins running the connection immediately
                // after invoking its synchronous handler. A very fast client can
                // therefore subscribe before our subscription stream task has
                // registered. Retry the latest snapshot once after readiness;
                // publish() remains a no-op for channels that are not subscribed.
                Task { await publishInitialSnapshotAfterHandoff(to: id) }
                PrismLog.info(
                    .remoteSession,
                    "remote.racp.client_connected",
                    "An rACP client connected.",
                    metadata: ["peer": .identifier(peer.peerID, privacy: .private)]
                )
            case .disconnected:
                clients.removeValue(forKey: id)
                if server != nil { publishStatus(state: .listening) }
            case .connecting, .handshaking:
                break
            }
        }
        clients.removeValue(forKey: id)
        if server != nil { publishStatus(state: .listening) }
    }

    private func publishInitialSnapshotAfterHandoff(to id: UUID) async {
        try? await Task.sleep(for: .milliseconds(50))
        guard let state = latestState, clients[id]?.ready == true else { return }
        let wireRevision = publicationRevision
        for name in PrismRACPCapability.stateNames.sorted() {
            await publish(name: name, state: state, wireRevision: wireRevision, to: [id])
        }
    }

    private func observeSubscriptions(id: UUID, connection: RACPConnection) async {
        for await event in await connection.subscriptionUpdates() {
            guard case .subscribed(let name) = event,
                  PrismRACPCapability.stateNames.contains(name),
                  let state = latestState
            else { continue }
            await publish(
                name: name,
                state: state,
                wireRevision: publicationRevision,
                to: [id]
            )
        }
    }

    private func publish(
        name: String,
        state: PrismRACPStateSnapshot,
        wireRevision: UInt64,
        to ids: [UUID]
    ) async {
        guard let message = state.stateMessage(
            named: name,
            wireRevision: wireRevision
        ) else { return }
        for id in ids {
            // Actor methods re-enter while awaiting a connection write. Once a
            // newer snapshot exists, abandon this older fan-out before it can
            // send a lower revision after the newer one.
            guard wireRevision == publicationRevision, latestState == state else { return }
            guard let client = clients[id], client.ready else { continue }
            let previous = client.lastPublishedRevision[name]
            guard previous == nil || message.revision > previous! else { continue }
            do {
                switch try await client.connection.publish(message) {
                case .published:
                    guard var current = clients[id],
                          current.connection === client.connection
                    else { continue }
                    current.lastPublishedRevision[name] = max(
                        current.lastPublishedRevision[name] ?? 0,
                        message.revision
                    )
                    clients[id] = current
                case .notSubscribed:
                    break
                }
            } catch {
                await client.connection.close(reason: "state_publication_failed")
            }
        }
    }

    private func publishStatus(state: PrismRACPServiceSnapshot.State) {
        report(.init(
            state: state,
            port: listeningPort,
            clientCount: clients.values.filter(\.ready).count,
            lastError: nil
        ))
    }

    private func report(_ snapshot: PrismRACPServiceSnapshot) {
        statusSequence &+= 1
        reportStatus(statusSequence, snapshot)
    }
}
