import AuroraACP
import AuroraACPAppleSecurity
import Foundation

/// Prism's production ACP host. It consumes ACP-authenticated connections and
/// deliberately exposes no mutation callback, action router, or engine handle.
public actor PrismACPService {
    public private(set) var configuration: PrismACPConfiguration
    public let publisher = PrismACPStatePublisher()
    public let enrollment = PrismACPEnrollmentPresentationModel()

    private var listener: ACPAppleFullServerListener?
    private var acceptTask: Task<Void, Never>?
    private var sessionTasks: [UUID: Task<Void, Never>] = [:]
    private var sessions: [UUID: ACPSession] = [:]
    private var bonjour: PrismACPBonjourPublisher?
    private var diagnostic = PrismACPDiagnostics()
    private var lastState: PrismACPAuthoritativeState?

    public init(configuration: PrismACPConfiguration) {
        self.configuration = configuration
    }

    public func start() async throws {
        guard configuration.enabled else {
            await stop()
            return
        }
        guard listener == nil, acceptTask == nil else { return }
        diagnostic.listenerState = .starting
        diagnostic.blocker = nil
        diagnostic.lastConnectionFailure = nil
        diagnostic.lastAuthenticationFailure = nil

        guard let material = configuration.secureHostMaterial else {
            diagnostic.listenerState = .blocked
            diagnostic.blocker = .secureIdentityUnavailable
            throw PrismACPBlocker.secureIdentityUnavailable
        }

        do {
            let listener = try ACPAppleFullServerFactory.makeListener(
                port: configuration.port,
                configuration: material.configuration
            )
            try await listener.start()
            let endpoint = await listener.endpoint
            self.listener = listener
            diagnostic.listenerState = .ready
            diagnostic.boundPort = endpoint.port
            diagnostic.nodeID = material.configuration.localACPIdentity.nodeID
            diagnostic.instanceID = material.configuration.localACPIdentity.instanceID
            if configuration.discoveryEnabled {
                let publisher = PrismACPBonjourPublisher()
                publisher.start(
                    port: endpoint.port,
                    nodeID: material.configuration.localACPIdentity.nodeID,
                    instanceID: material.configuration.localACPIdentity.instanceID
                )
                bonjour = publisher
                diagnostic.discoveryActive = true
            }
            startAcceptLoop(local: material.configuration.localACPIdentity)
            if let lastState { await publish(lastState) }
        } catch {
            diagnostic.listenerState = .failed
            diagnostic.lastConnectionFailure = sanitized(error)
            await stopResources(preserveState: .failed)
            throw error
        }
    }

    public func stop() async {
        diagnostic.listenerState = .stopping
        await stopResources(preserveState: .stopped)
        await enrollment.serviceStopped()
    }

    public func setEnabled(_ enabled: Bool) async throws {
        configuration.enabled = enabled
        if enabled { try await start() } else { await stop() }
    }

    public func applyConfiguration(_ newConfiguration: PrismACPConfiguration) async throws {
        await stop()
        configuration = newConfiguration
        if newConfiguration.enabled { try await start() }
    }

    public func noteAuthoritativeState(_ state: PrismACPAuthoritativeState) async {
        lastState = state
        await publish(state)
    }

    public func diagnostics() -> PrismACPDiagnostics {
        var result = diagnostic
        result.authenticatedSessionCount = sessions.count
        result.discoveryActive = bonjour?.isActive == true
        result.enrollmentAvailable = false
        return result
    }

    public func isNetworkSilent() -> Bool {
        listener == nil && acceptTask == nil && sessions.isEmpty && bonjour == nil
    }

    public func trustedPeers() -> [ACPAppleTrustedPeer] {
        configuration.secureHostMaterial?.configuration.trustStore.trustedPeers() ?? []
    }

    public func revoke(_ credentialID: ACPCredentialID) throws -> ACPAppleRevocationResult {
        guard let store = configuration.secureHostMaterial?.configuration.trustStore else {
            throw PrismACPBlocker.secureIdentityUnavailable
        }
        return try store.revoke(credentialID)
    }

    private func publish(_ state: PrismACPAuthoritativeState) async {
        let owner = diagnostic.nodeID.isEmpty ? state.showID : diagnostic.nodeID
        await publisher.publish(state.snapshotPayload(ownerNodeID: owner))
    }

    private func startAcceptLoop(local: ACPIdentity) {
        acceptTask = Task { [weak self] in
            await self?.acceptLoop(local: local)
        }
    }

    private func acceptLoop(local: ACPIdentity) async {
        while !Task.isCancelled, let listener {
            do {
                let connection = try await listener.accept(timeout: 10)
                let id = UUID()
                sessionTasks[id] = Task { [weak self] in
                    await self?.serve(connection, local: local, id: id)
                }
            } catch is CancellationError {
                return
            } catch let error as ACPAppleSecurityError {
                if error == .timeout { continue }
                diagnostic.lastAuthenticationFailure = error.rawValue
            } catch {
                diagnostic.lastConnectionFailure = sanitized(error)
            }
        }
    }

    private func serve(_ connection: ACPAuthenticatedConnection, local: ACPIdentity, id: UUID) async {
        do {
            let session = try connection.makeSession(local: local)
            await session.setProfiles(["core", "remote"])
            await session.setCapabilities(readOnlyCapabilities())
            _ = try await session.handshake()
            sessions[id] = session
            while !Task.isCancelled {
                let inbound: ACPEnvelope?
                do {
                    inbound = try await session.pumpOnce(deadline: Date().addingTimeInterval(30))
                } catch let error as ACPSessionError where error.code == "timeout" {
                    continue
                }
                guard let inbound else { continue }
                if inbound.type == "session.goodbye" { break }
                try await handle(inbound, session: session)
                let state = await session.state
                if state == .closed || state == .failed { break }
            }
            await session.goodbye()
            diagnostic.lastDisconnectReason = "peer_disconnected"
        } catch {
            diagnostic.lastConnectionFailure = sanitized(error)
        }
        sessions[id] = nil
        sessionTasks[id] = nil
    }

    private func handle(_ request: ACPEnvelope, session: ACPSession) async throws {
        switch request.type {
        case "state.request":
            let snapshot = await publisher.lastSnapshot
            try await send(
                type: "state.snapshot",
                payload: snapshot,
                request: request,
                session: session
            )
        case "remote.hello":
            try await send(
                type: "remote.hello_ack",
                payload: [
                    "accepted": .bool(true),
                    "permissions": .object([
                        "roles": .array([.string("remote.viewer")]),
                        "capabilities": .array([.string("state.live"), .string("system.health")]),
                        "permissions": .array([]),
                        "revision": .uint(1),
                    ]),
                    "show_id": .string(lastState?.showID
                        ?? PrismACPDiagnosticIdentifier.stableUUID(seed: "prism.acp.unloaded-show")),
                    "show_revision": .uint(lastState?.revision ?? 0),
                    "surface_id": .string(PrismACPDiagnosticIdentifier.stableUUID(seed: "prism.acp.diagnostics.read-only")),
                    "layout_revision": .uint(1),
                ],
                request: request,
                session: session
            )
        case "health.heartbeat", "remote.error", "error.report":
            break
        default:
            try await send(
                type: "error.report",
                payload: [
                    "code": .string("unsupported_message"),
                    "category": .string("authorization"),
                    "severity": .string("warning"),
                    "message": .string("Prism's ACP qualification host is read-only."),
                    "retryable": .bool(false),
                ],
                request: request,
                session: session
            )
        }
    }

    private func send(
        type: String,
        payload: [String: AnySendable],
        request: ACPEnvelope,
        session: ACPSession
    ) async throws {
        _ = try await session.send(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: type,
            source: ACPEndpoint(nodeID: diagnostic.nodeID),
            destination: ACPEndpoint(nodeID: request.source.nodeID),
            timestampUTC: Self.timestamp(),
            correlationID: request.correlationID ?? request.messageID,
            qos: .reliable,
            payload: payload
        ))
    }

    private func stopResources(preserveState finalState: PrismACPListenerState) async {
        acceptTask?.cancel()
        acceptTask = nil
        if let listener { await listener.shutdown() }
        listener = nil
        bonjour?.stop()
        bonjour = nil
        for task in sessionTasks.values { task.cancel() }
        for session in sessions.values { await session.goodbye() }
        sessionTasks.removeAll()
        sessions.removeAll()
        diagnostic.listenerState = finalState
        diagnostic.discoveryActive = false
        diagnostic.boundPort = nil
    }

    private func readOnlyCapabilities() -> [ACPCapability] {
        [
            ACPCapability(id: "remote.profile", version: "1.0"),
            ACPCapability(id: "state.live", version: "1.2"),
            ACPCapability(id: "system.health", version: "1.0"),
        ]
    }

    private func sanitized(_ error: Error) -> String {
        if let security = error as? ACPAppleSecurityError { return security.rawValue }
        if let session = error as? ACPSessionError { return session.code }
        if let blocker = error as? PrismACPBlocker { return blocker.rawValue }
        return "acp_operation_failed"
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
