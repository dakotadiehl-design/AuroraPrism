import AuroraACP
import AuroraACPAppleSecurity
import Foundation

public struct PrismACPTrustedPeer: Sendable, Equatable, Identifiable {
    public var id: String { credentialID }
    public let nodeID: String
    public let credentialID: String
    public let displayName: String?
    public let state: String
    public let lastSeen: Date?
}

/// ACP owns provisioning, enrollment, credentials, authentication, transport,
/// trust and revocation. This adapter owns only observation-safe Prism state.
public actor PrismACPService {
    public private(set) var configuration: PrismACPConfiguration
    public let publisher = PrismACPStatePublisher()
    public let enrollment = PrismACPEnrollmentPresentationModel()

    private var host: ACPAppleHost?
    private var listener: ACPAppleFullServerListener?
    private var enrollmentService: ACPAppleEnrollmentService?
    private var acceptTask: Task<Void, Never>?
    private var enrollmentUpdatesTask: Task<Void, Never>?
    private var sessionTasks: [UUID: Task<Void, Never>] = [:]
    private var sessions: [UUID: ACPSession] = [:]
    private var diagnostic = PrismACPDiagnostics()
    private var lastState: PrismACPAuthoritativeState?

    public init(configuration: PrismACPConfiguration) {
        self.configuration = configuration
    }

    public func start() async throws {
        guard configuration.enabled else { await stop(); return }
        guard listener == nil, acceptTask == nil else { return }
        diagnostic.listenerState = .starting
        diagnostic.blocker = nil
        diagnostic.discoveryBlocker = nil
        diagnostic.lastConnectionFailure = nil
        diagnostic.lastAuthenticationFailure = nil

        do {
            let provenance = try validatedProvenance()
            let hostConfiguration = try ACPAppleHostConfiguration(
                identity: configuration.identity,
                storageNamespace: configuration.storageNamespace,
                keychainAccessGroup: configuration.keychainAccessGroup,
                providerProvenance: provenance,
                preferSecureEnclave: configuration.preferSecureEnclave,
                allowNonHardwareFallback: configuration.allowNonHardwareFallback
            )
            let host = try await ACPAppleHostFactory.openOrBootstrap(
                configuration: hostConfiguration)
            self.host = host
            diagnostic.nodeID = configuration.identity.nodeID
            diagnostic.instanceID = configuration.identity.instanceID
            diagnostic.provisioningState = host.provisioningStatus.state.rawValue
            let status = try host.operationalStatus()
            diagnostic.credentialExpiresAt = status.credentialExpiresAt
            diagnostic.renewalReadiness = status.renewalReadiness.rawValue

            if configuration.enrollmentEnabled {
                let service = try host.makeEnrollmentService(configuration: try .init(
                    port: configuration.enrollmentPort))
                let endpoint = try await service.start()
                enrollmentService = service
                diagnostic.enrollmentAvailable = true
                diagnostic.enrollmentPort = endpoint.port
                startEnrollmentUpdates(host)
            }

            let listener = try host.makeFullServerListener(port: configuration.port)
            try await listener.start()
            let endpoint = await listener.endpoint
            self.listener = listener
            diagnostic.listenerState = .ready
            diagnostic.boundPort = endpoint.port
            startAcceptLoop(local: configuration.identity)

            // ACP currently defines TXT fields but no canonical framed-TLS URL
            // or enrollment discovery representation. Never invent one here.
            if configuration.discoveryEnabled {
                diagnostic.discoveryBlocker = .discoveryContractUnavailable
            }
            if let lastState { await publish(lastState) }
        } catch let blocker as PrismACPBlocker {
            diagnostic.listenerState = .blocked
            diagnostic.blocker = blocker
            await stopResources(preserveState: .blocked)
            await enrollment.unavailable(blocker)
            throw blocker
        } catch let provisioning as ACPAppleHostProvisioningError {
            diagnostic.listenerState = .blocked
            diagnostic.blocker = .hostProvisioningUnavailable
            diagnostic.provisioningState = provisioning.rawValue
            diagnostic.lastConnectionFailure = provisioning.rawValue
            await stopResources(preserveState: .blocked)
            await enrollment.unavailable(.hostProvisioningUnavailable)
            throw provisioning
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

    public func applyConfiguration(_ value: PrismACPConfiguration) async throws {
        await stop()
        configuration = value
        if value.enabled { try await start() }
    }

    public func noteAuthoritativeState(_ state: PrismACPAuthoritativeState) async {
        lastState = state
        await publish(state)
    }

    public func diagnostics() -> PrismACPDiagnostics {
        var result = diagnostic
        result.authenticatedSessionCount = sessions.count
        return result
    }

    public func isNetworkSilent() -> Bool {
        listener == nil && enrollmentService == nil && acceptTask == nil && sessions.isEmpty
    }

    public func trustedPeers() -> [ACPAppleTrustedPeer] { host?.trustedPeers() ?? [] }

    public func trustedPeerSummaries() -> [PrismACPTrustedPeer] {
        trustedPeers().map {
            PrismACPTrustedPeer(nodeID: $0.nodeID, credentialID: $0.credentialID,
                                displayName: $0.displayName, state: $0.state.rawValue,
                                lastSeen: $0.lastSeen)
        }
    }

    public func revoke(credentialID: String) throws -> ACPAppleRevocationResult {
        guard let value = ACPCredentialID(rawValue: credentialID) else {
            throw PrismACPBlocker.hostProvisioningUnavailable
        }
        return try revoke(value)
    }

    public func enrollmentRequestUpdates() async
        -> AsyncStream<[PrismACPEnrollmentRequest]> {
        guard let host else {
            return AsyncStream { $0.yield([]); $0.finish() }
        }
        let upstream = await host.enrollmentRequestUpdates()
        return AsyncStream { continuation in
            let task = Task {
                for await requests in upstream {
                    guard !Task.isCancelled else { break }
                    continuation.yield(requests.map(PrismACPEnrollmentRequest.init))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func revoke(_ credentialID: ACPCredentialID) throws -> ACPAppleRevocationResult {
        guard let host else { throw PrismACPBlocker.hostProvisioningUnavailable }
        return try host.revokePeer(credentialID: credentialID)
    }

    public func beginEnrollment(
        enrollmentID: ACPEnrollmentID,
        candidateNodeID: ACPSecurityNodeID,
        displayName: String?,
        requestedRole: String = "remote",
        code: PrismACPEnrollmentCode
    ) async throws -> ACPAppleEnrollmentOutcome {
        guard let enrollmentService else {
            throw ACPAppleEnrollmentServiceError.notStarted
        }
        let candidate = try ACPAppleEnrollmentCandidate(
            enrollmentID: enrollmentID,
            nodeID: candidateNodeID,
            displayName: displayName,
            requestedRole: requestedRole,
            bootstrapSecret: try code.secret())
        return try await enrollmentService.beginEnrollment(candidate)
    }

    public func approveEnrollment(_ id: ACPEnrollmentAttemptID) async throws {
        guard let host else { throw PrismACPBlocker.hostProvisioningUnavailable }
        await enrollment.resolving(id)
        _ = try await host.approveEnrollment(requestID: id)
    }

    public func rejectEnrollment(_ id: ACPEnrollmentAttemptID) async throws {
        guard let host else { throw PrismACPBlocker.hostProvisioningUnavailable }
        await enrollment.resolving(id)
        _ = try await host.rejectEnrollment(requestID: id)
    }

    public func cancelEnrollment(_ id: ACPEnrollmentAttemptID) async throws {
        guard let host else { throw PrismACPBlocker.hostProvisioningUnavailable }
        await enrollment.resolving(id)
        _ = try await host.cancelEnrollment(requestID: id)
    }

    private func validatedProvenance() throws -> ACPProviderProvenance {
        guard let data = configuration.providerProvenanceJSON else {
            throw PrismACPBlocker.providerManifestMissing
        }
        let provenance: ACPProviderProvenance
        do { provenance = try ACPProviderProvenance(jsonData: data) }
        catch { throw PrismACPBlocker.providerManifestInvalid }
        guard let expected = configuration.expectedProviderSourceRevision,
              provenance.sourceRevision == expected else {
            throw PrismACPBlocker.providerRevisionMismatch
        }
        return provenance
    }

    private func startEnrollmentUpdates(_ host: ACPAppleHost) {
        enrollmentUpdatesTask = Task { [weak self] in
            let updates = await host.enrollmentRequestUpdates()
            for await requests in updates {
                guard !Task.isCancelled else { return }
                await self?.enrollment.update(requests)
            }
        }
    }

    private func publish(_ state: PrismACPAuthoritativeState) async {
        let owner = diagnostic.nodeID.isEmpty ? state.showID : diagnostic.nodeID
        await publisher.publish(state.snapshotPayload(ownerNodeID: owner))
    }

    private func startAcceptLoop(local: ACPIdentity) {
        acceptTask = Task { [weak self] in await self?.acceptLoop(local: local) }
    }

    private func acceptLoop(local: ACPIdentity) async {
        while !Task.isCancelled, let listener {
            do {
                let connection = try await listener.accept(timeout: 10)
                let id = UUID()
                sessionTasks[id] = Task { [weak self] in
                    await self?.serve(connection, local: local, id: id)
                }
            } catch is CancellationError { return }
            catch let error as ACPAppleSecurityError {
                if error == .timeout { continue }
                diagnostic.lastAuthenticationFailure = error.rawValue
            } catch { diagnostic.lastConnectionFailure = sanitized(error) }
        }
    }

    private func serve(_ connection: ACPAuthenticatedConnection, local: ACPIdentity, id: UUID) async {
        do {
            let session = try connection.makeSession(local: local)
            let offered = readOnlyCapabilities()
            await session.setProfiles(["core", "remote"])
            await session.setCapabilities(offered)
            _ = try await session.handshake()
            let negotiated = Set(await session.negotiatedCapabilities)
            guard negotiated.isSubset(of: Set(offered.map(\.id))) else {
                throw ACPSessionError("capability_not_permitted", "non-read-only capability negotiated")
            }
            sessions[id] = session
            while !Task.isCancelled {
                let inbound: ACPEnvelope?
                do { inbound = try await session.pumpOnce(deadline: Date().addingTimeInterval(30)) }
                catch let error as ACPSessionError where error.code == "timeout" { continue }
                guard let inbound else { continue }
                switch Self.disposition(for: inbound.type) {
                case .protocolInternal where inbound.type == "session.goodbye":
                    await session.goodbye(); sessions[id] = nil; sessionTasks[id] = nil; return
                case .protocolInternal:
                    break
                case .allowedReadOnly:
                    try await handleReadOnly(inbound, session: session)
                case .reject:
                    try await reject(inbound, session: session)
                case .close:
                    await session.goodbye(); sessions[id] = nil; sessionTasks[id] = nil; return
                }
            }
            await session.goodbye()
            diagnostic.lastDisconnectReason = "peer_disconnected"
        } catch { diagnostic.lastConnectionFailure = sanitized(error) }
        sessions[id] = nil
        sessionTasks[id] = nil
    }

    enum InboundDisposition: Sendable, Equatable {
        case allowedReadOnly, reject, protocolInternal, close
    }

    static func disposition(for type: String) -> InboundDisposition {
        switch type {
        case "state.request", "remote.hello": return .allowedReadOnly
        case "health.heartbeat", "remote.error", "error.report", "session.goodbye":
            return .protocolInternal
        default:
            return ACPRegistry.lookup(type) == nil ? .close : .reject
        }
    }

    private func handleReadOnly(_ request: ACPEnvelope, session: ACPSession) async throws {
        if request.type == "state.request" {
            try await send(type: "state.snapshot", payload: await publisher.lastSnapshot,
                           request: request, session: session)
            return
        }
        let negotiated = Set(await session.negotiatedCapabilities)
        let visible = ["state.live", "system.health"].filter(negotiated.contains)
            .map { AnySendable.string($0) }
        try await send(type: "remote.hello_ack", payload: [
            "accepted": .bool(true),
            "permissions": .object([
                "roles": .array([.string("remote.viewer")]),
                "capabilities": .array(visible),
                "permissions": .array([]), "revision": .uint(1),
            ]),
            "show_id": .string(lastState?.showID
                ?? PrismACPDiagnosticIdentifier.stableUUID(seed: "prism.acp.unloaded-show")),
            "show_revision": .uint(lastState?.revision ?? 0),
            "surface_id": .string(PrismACPDiagnosticIdentifier.stableUUID(
                seed: "prism.acp.diagnostics.read-only")),
            "layout_revision": .uint(1),
        ], request: request, session: session)
    }

    private func reject(_ request: ACPEnvelope, session: ACPSession) async throws {
        try await send(type: "error.report", payload: [
            "code": .string("capability_not_permitted"),
            "category": .string("authorization"),
            "severity": .string("warning"),
            "message": .string("Prism ACP is observation-only."),
            "retryable": .bool(false),
        ], request: request, session: session)
    }

    private func send(type: String, payload: [String: AnySendable], request: ACPEnvelope,
                      session: ACPSession) async throws {
        _ = try await session.send(ACPEnvelope(
            acp: "1.2", messageID: UUID().uuidString.lowercased(), type: type,
            source: ACPEndpoint(nodeID: diagnostic.nodeID),
            destination: ACPEndpoint(nodeID: request.source.nodeID),
            timestampUTC: ISO8601DateFormatter().string(from: Date()),
            correlationID: request.correlationID ?? request.messageID,
            qos: .reliable, payload: payload))
    }

    private func stopResources(preserveState finalState: PrismACPListenerState) async {
        acceptTask?.cancel(); acceptTask = nil
        enrollmentUpdatesTask?.cancel(); enrollmentUpdatesTask = nil
        if let listener { await listener.shutdown() }
        listener = nil
        if let enrollmentService { await enrollmentService.shutdown() }
        enrollmentService = nil
        for task in sessionTasks.values { task.cancel() }
        for session in sessions.values { await session.goodbye() }
        sessionTasks.removeAll(); sessions.removeAll(); host = nil
        diagnostic.listenerState = finalState
        diagnostic.discoveryActive = false
        diagnostic.boundPort = nil
        diagnostic.enrollmentAvailable = false
        diagnostic.enrollmentPort = nil
        if finalState == .stopped {
            diagnostic.blocker = nil
            diagnostic.discoveryBlocker = nil
            diagnostic.provisioningState = nil
            diagnostic.credentialExpiresAt = nil
            diagnostic.renewalReadiness = nil
        }
    }

    private func readOnlyCapabilities() -> [ACPCapability] {
        [.init(id: "remote.profile", version: "1.0"),
         .init(id: "state.live", version: "1.2"),
         .init(id: "system.health", version: "1.0")]
    }

    private func sanitized(_ error: Error) -> String {
        if let value = error as? ACPAppleHostProvisioningError { return value.rawValue }
        if let value = error as? ACPAppleEnrollmentServiceError { return value.rawValue }
        if let value = error as? ACPAppleSecurityError { return value.rawValue }
        if let value = error as? ACPSessionError { return value.code }
        if let value = error as? PrismACPBlocker { return value.rawValue }
        return "acp_operation_failed"
    }
}
