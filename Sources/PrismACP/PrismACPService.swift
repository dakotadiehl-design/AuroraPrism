import AuroraACP
import Foundation

private actor PrismACPStateDelivery {
    enum Outcome { case sent, overloaded, failed(String) }
    private var tail: Task<String?, Never>?
    private var pending = 0
    private let capacity = 128

    func send(_ envelope: ACPEnvelope, through session: ACPSession) async -> Outcome {
        guard pending < capacity else { return .overloaded }
        pending += 1
        let previous = tail
        let task = Task<String?, Never> {
            _ = await previous?.value
            do {
                _ = try await session.send(envelope)
                return nil
            } catch {
                return String(describing: error)
            }
        }
        tail = task
        let error = await task.value
        pending -= 1
        return error.map(Outcome.failed) ?? .sent
    }
}

public actor PrismACPService {
    public private(set) var identity: PrismACPIdentity?
    public private(set) var listenerState: PrismACPListenerState = .stopped
    public private(set) var configuration: PrismACPConfiguration
    public private(set) var boundPort: UInt16?
    public let publisher = PrismACPStatePublisher()
    public let dispositions = PrismACPExecutionDispositionStore()
    public let audit = PrismACPAuditStore()
    public private(set) var actionRouter: PrismACPActionRouter
    public private(set) var policy: PrismACPAuthorizationPolicy
    public let availability = PrismACPAvailabilityProvider()
    public private(set) var lastState: PrismACPAuthoritativeState?
    public private(set) var lastSessionError: String?
    public private(set) var lastDiscoveryError: String?
    private let identityStore = PrismACPIdentityStore()
    private var listener: ACPWebSocketListener?
    private var hostExecutor: (@Sendable (PrismACPControlRequest) async -> PrismACPControlResult)?
    private var hostMomentaryRelease: PrismACPMomentaryAuthority.ReleaseHandler?
    private var acceptTask: Task<Void, Never>?
    private var sessionTasks: [UUID: Task<Void, Never>] = [:]
    private var sessions: [UUID: ACPSession] = [:]
    private var stateDeliveries: [UUID: PrismACPStateDelivery] = [:]
    private var remoteContexts: [UUID: PrismACPRemoteContext] = [:]
    private struct SurfaceOffer: Sendable {
        var connectionID: UUID
        var data: Data
        var digest: String
        var revision: UInt64
        var verified = false
    }
    private var surfaceOffers: [String: SurfaceOffer] = [:]
    private var momentary: PrismACPMomentaryAuthority?
    private var momentaryHolds: [PrismACPMomentaryHold] = []
    private var lastPublishedMomentaryHolds: [PrismACPMomentaryHold] = []
    /// Admission generation used to collapse bursts of continuous master
    /// updates before they reach Prism's semantic command router.
    private var masterAdmissionGeneration: UInt64 = 0

    public init(configuration: PrismACPConfiguration) {
        self.configuration = configuration
        self.actionRouter = PrismACPActionRouter(advertiseControl: configuration.advertiseControl)
        self.policy = PrismACPAuthorizationPolicy(
            allowMutations: configuration.advertiseControl,
            operatorNodeIDs: configuration.operatorNodeIDs,
            blackoutClearNodeIDs: configuration.blackoutClearNodeIDs
        )
    }

    public func installHostExecutor(
        _ handler: @escaping @Sendable (PrismACPControlRequest) async -> PrismACPControlResult
    ) {
        hostExecutor = handler
    }

    /// Installs the application/hardware release boundary for physical
    /// momentaries. The harmless lease_test is released internally; every
    /// other control fails unsafe when no handler is installed.
    public func installHostMomentaryRelease(
        _ handler: @escaping PrismACPMomentaryAuthority.ReleaseHandler
    ) {
        hostMomentaryRelease = handler
    }

    /// Updates the server-owned enrollment policy. Client role claims never
    /// enter this set. Existing sessions must complete Remote synchronization
    /// again before mutation is admitted.
    public func setOperatorNodeIDs(_ nodeIDs: Set<String>) {
        let removed = configuration.operatorNodeIDs.subtracting(nodeIDs)
        configuration.operatorNodeIDs = nodeIDs
        configuration.blackoutClearNodeIDs.formIntersection(nodeIDs)
        policy = PrismACPAuthorizationPolicy(
            allowMutations: configuration.advertiseControl,
            operatorNodeIDs: nodeIDs,
            blackoutClearNodeIDs: configuration.blackoutClearNodeIDs
        )
        for id in remoteContexts.keys {
            remoteContexts[id]?.ready = false
        }
        if let momentary {
            Task { for nodeID in removed { await momentary.revokePrincipal(nodeID) } }
        }
    }

    public func noteAuthoritativeState(_ state: PrismACPAuthoritativeState) async {
        let previous = lastState
        let canPublishDelta = previous?.authorityEpoch == state.authorityEpoch
            && state.revision == (previous?.revision ?? 0) &+ 1
        if !canPublishDelta {
            for id in remoteContexts.keys {
                remoteContexts[id]?.ready = false
            }
        }
        lastState = state
        let node = identity?.nodeID ?? state.showID
        let snapshot = state.snapshotPayload(ownerNodeID: node)
        await publisher.publish(snapshot)
        if canPublishDelta, case .array(let resources) = snapshot["resources"] {
            for (id, context) in remoteContexts where context.ready {
                guard let session = sessions[id] else { continue }
                let filtered = filterResources(resources, subscribed: context.subscribedResources)
                let payload = ACPStateRevision.deltaPayload(
                    authorityEpoch: state.authorityEpoch,
                    baseRevision: previous?.revision ?? 0,
                    revision: state.revision,
                    changes: filtered
                )
                let envelope = ACPEnvelope(
                        acp: "1.2",
                        messageID: UUID().uuidString.lowercased(),
                        type: "state.delta",
                        source: ACPEndpoint(nodeID: node),
                        destination: ACPEndpoint(nodeID: context.principalNodeID),
                        timestampUTC: currentTimestampUTC(),
                        qos: .latest,
                        payload: payload
                    )
                let delivery = stateDeliveries[id] ?? PrismACPStateDelivery()
                stateDeliveries[id] = delivery
                switch await delivery.send(envelope, through: session) {
                case .sent:
                    remoteContexts[id]?.snapshotDeliveredRevision = state.revision
                case .overloaded:
                    remoteContexts[id]?.ready = false
                    lastSessionError = "state delivery overloaded; snapshot resync required"
                case .failed(let error):
                    remoteContexts[id]?.ready = false
                    lastSessionError = error
                }
            }
        }
    }

    public func start() async throws {
        guard configuration.enabled else {
            await stop()
            return
        }
        listenerState = .starting
        lastDiscoveryError = nil
        identity = try identityStore.loadOrCreate(in: configuration.applicationSupportDirectory)
        let momentary = PrismACPMomentaryAuthority(
            storeURL: configuration.applicationSupportDirectory.appendingPathComponent("ACP/momentary-holds.json"),
            releaseHandler: { [weak self] hold in
                guard let self else { return (confirmedInactive: false, physicalActive: nil) }
                return await self.releaseMomentaryHold(hold)
            },
            onChange: { [weak self] holds in await self?.momentaryDidChange(holds) }
        )
        await momentary.start()
        self.momentary = momentary
        let configuredPort = configuration.webSocketPort
        let discovery: ACPBonjourAdvertisement?
        if configuration.discoveryEnabled, let identity {
            let url = ACPDiscoveryTXT.advertisementURL(
                port: configuredPort,
                loopbackOnly: configuration.loopbackOnly
            )
            let endpoint = ACPDiscoveryTXT(
                name: "Prism",
                port: configuredPort,
                nodeID: identity.nodeID,
                instanceID: identity.instanceID,
                endpointURL: url
            )
            discovery = ACPBonjourAdvertisement(
                name: endpoint.name,
                type: "_acp._tcp",
                txtRecord: endpoint.txtRecord
            )
        } else {
            discovery = nil
        }
        let listener = try ACPWebSocketListener(
            port: configuredPort,
            loopbackOnly: configuration.loopbackOnly,
            bonjour: discovery
        )
        try await listener.start()
        boundPort = await listener.port ?? configuration.webSocketPort
        self.listener = listener
        startAcceptLoop()
        listenerState = .ready
        if let lastState {
            await noteAuthoritativeState(lastState)
        }
    }

    public func stop() async {
        acceptTask?.cancel()
        if let momentary { await momentary.shutdown() }
        momentary = nil
        if let listener {
            await listener.stop()
        }
        listener = nil
        for task in sessionTasks.values { task.cancel() }
        sessionTasks.removeAll()
        sessions.removeAll()
        stateDeliveries.removeAll()
        remoteContexts.removeAll()
        surfaceOffers.removeAll()
        acceptTask = nil
        boundPort = nil
        listenerState = .stopped
    }

    public func diagnostics() -> PrismACPDiagnostics {
        PrismACPDiagnostics(
            enabled: configuration.enabled && listenerState == .ready,
            listenerState: listenerState,
            sessionCount: sessionTasks.count,
            nodeID: identity?.nodeID ?? "",
            instanceID: identity?.instanceID ?? "",
            advertisedCapabilities: actionRouter.advertisedCapabilities()
        )
    }

    public func isNetworkSilent() -> Bool {
        listenerState == .stopped && listener == nil && !configuration.discoveryEnabled
    }

    public func setEnabled(_ enabled: Bool) async throws {
        configuration.enabled = enabled
        if enabled {
            try await start()
        } else {
            await stop()
        }
    }

    public func applyConfiguration(_ configuration: PrismACPConfiguration) async throws {
        await stop()
        self.configuration = configuration
        actionRouter = PrismACPActionRouter(advertiseControl: configuration.advertiseControl)
        policy = PrismACPAuthorizationPolicy(
            allowMutations: configuration.advertiseControl,
            operatorNodeIDs: configuration.operatorNodeIDs,
            blackoutClearNodeIDs: configuration.blackoutClearNodeIDs
        )
        if configuration.enabled {
            try await start()
        }
    }

    public func admit(_ action: PrismACPAction) async throws -> PrismACPAdmissionResult {
        try actionRouter.submit(action)
        guard let principal = action.originPrincipal,
              policy.permitsMutation(principalNodeID: principal),
              let hostExecutor
        else {
            throw PrismACPActionRouterError.mutationsNotAdvertised
        }
        if action.name == "blackoutOff", !policy.permitsBlackoutClear(principalNodeID: principal) {
            await recordAudit(action, disposition: "rejected")
            throw PrismACPActionRouterError.rejected("blackout_clear_not_authorized")
        }
        let showLoaded = !(lastState?.showName.isEmpty ?? true)
        let avail = availability.availability(for: action.name, showLoaded: showLoaded)
        guard avail.available else {
            throw PrismACPActionRouterError.unavailable(avail.reason ?? "resource_unavailable")
        }
        let fingerprint = PrismACPActionRouter.fingerprint(action)
        let reservation = ACPCommandRecord(
            commandID: action.commandID,
            originNodeID: action.originNodeID,
            originInstanceID: action.originInstanceID,
            operation: action.name,
            disposition: "in_flight",
            idempotencyKey: action.idempotencyKey,
            originPrincipal: action.originPrincipal,
            originSessionID: action.originSessionID,
            receivedAt: currentTimestampUTC(),
            fingerprint: fingerprint
        )
        switch await dispositions.reserve(reservation) {
        case .existing(let existing):
            return PrismACPAdmissionResult(
                disposition: existing.disposition,
                storageKey: PrismACPActionRouter.showActionStorageKey(for: action),
                resultingEpoch: existing.resultingEpoch,
                resultingRevision: existing.resultingRevision
            )
        case .conflict:
            await recordAudit(action, disposition: "conflict")
            return PrismACPAdmissionResult(disposition: "conflict", reason: "command_identity_conflict")
        case .unavailable:
            // The bounded ACP command ledger could not safely reserve this mutation.
            // Fail closed: executing without a reservation would break at-most-once
            // semantics and could replay a live lighting command.
            await recordAudit(action, disposition: "unavailable")
            throw PrismACPActionRouterError.unavailable("command_ledger_capacity")
        case .reserved:
            break
        }
        if let reason = action.freshnessRejection {
            var expired = reservation
            expired.disposition = "expired"
            expired.result["reason"] = .string(reason)
            _ = try await dispositions.complete(expired)
            await recordAudit(action, disposition: "expired")
            return PrismACPAdmissionResult(disposition: "expired", reason: reason)
        }
        guard let key = PrismACPActionRouter.showActionStorageKey(for: action) else {
            throw PrismACPActionRouterError.unsupported
        }
        if action.name == "output.master" {
            masterAdmissionGeneration &+= 1
            let generation = masterAdmissionGeneration
            // A small bounded window absorbs dense fader traffic. Transport
            // commands bypass this delay and therefore cannot queue behind it.
            do {
                try await Task.sleep(nanoseconds: 8_000_000)
            } catch {
                var cancelled = reservation
                cancelled.disposition = "failed"
                cancelled.result["reason"] = .string("cancelled")
                _ = try await dispositions.complete(cancelled)
                await recordAudit(action, disposition: "failed")
                return PrismACPAdmissionResult(
                    disposition: "failed",
                    storageKey: key,
                    reason: "cancelled"
                )
            }
            if generation != masterAdmissionGeneration {
                var coalesced = reservation
                coalesced.disposition = "completed"
                coalesced.result["reason"] = .string("superseded_by_newer_value")
                _ = try await dispositions.complete(coalesced)
                await recordAudit(action, disposition: "completed")
                return PrismACPAdmissionResult(
                    disposition: "completed",
                    storageKey: key,
                    reason: "superseded_by_newer_value"
                )
            }
        }
        let outcome = await hostExecutor(PrismACPControlRequest(action: action))
        var record = reservation
        record.disposition = outcome.disposition
        record.resultingEpoch = outcome.resultingEpoch
        record.resultingRevision = outcome.resultingRevision
        if let reason = outcome.reason { record.result["reason"] = .string(reason) }
        _ = try await dispositions.complete(record)
        await audit.record(PrismACPAuditEvent(
            timestamp: record.receivedAt,
            operation: action.name,
            disposition: outcome.disposition,
            origin: action.originPrincipal ?? action.originNodeID,
            target: auditTarget(for: action),
            resultingEpoch: outcome.resultingEpoch,
            resultingRevision: outcome.resultingRevision,
            safetyOutcome: blackoutSafetyOutcome(action: action, disposition: outcome.disposition)
        ))
        return PrismACPAdmissionResult(
            disposition: outcome.disposition,
            storageKey: key,
            reason: outcome.reason,
            resultingEpoch: outcome.resultingEpoch,
            resultingRevision: outcome.resultingRevision
        )
    }

    private func recordAudit(_ action: PrismACPAction, disposition: String) async {
        await audit.record(PrismACPAuditEvent(
            timestamp: currentTimestampUTC(),
            operation: action.name,
            disposition: disposition,
            origin: action.originPrincipal ?? action.originNodeID,
            target: auditTarget(for: action),
            safetyOutcome: blackoutSafetyOutcome(action: action, disposition: disposition)
        ))
    }

    private func auditTarget(for action: PrismACPAction) -> String? {
        action.parameter ?? action.value.map { String($0) }
    }

    private func blackoutSafetyOutcome(action: PrismACPAction, disposition: String) -> String {
        guard disposition == "applied" else {
            return ["blackoutOn", "blackoutOff"].contains(action.name)
                ? "safety_state_unchanged"
                : "not_safety_sensitive"
        }
        switch action.name {
        case "blackoutOn": return "blackout_engaged"
        case "blackoutOff": return "blackout_cleared"
        default: return "not_safety_sensitive"
        }
    }

    private func startAcceptLoop() {
        acceptTask?.cancel()
        acceptTask = Task { [weak self] in
            await self?.acceptLoop()
        }
    }

    private func acceptLoop() async {
        while !Task.isCancelled {
            guard let listener else { return }
            do {
                let connection = try await listener.accept(timeout: nil)
                let id = UUID()
                sessionTasks[id] = Task { [weak self] in
                    await self?.serve(connection, id: id)
                }
            } catch {
                return
            }
        }
    }

    private func serve(_ connection: ACPWebSocketConnection, id: UUID) async {
        guard let identity else {
            await connection.close()
            sessionTasks[id] = nil
            return
        }
        let session = ACPSession(
            transport: connection,
            local: ACPIdentity(nodeID: identity.nodeID, instanceID: identity.instanceID, role: "prism", name: "Prism"),
            isServer: true,
            allowPlaintext: true
        )
        await session.setProfiles(ACPDiscoveryTXT.advertisedProfiles)
        await session.setCapabilities(sessionCapabilities())
        do {
            _ = try await session.handshake()
            sessions[id] = session
            stateDeliveries[id] = PrismACPStateDelivery()
            remoteContexts[id] = PrismACPRemoteContext()
            while !Task.isCancelled {
                let inbound: ACPEnvelope?
                do {
                    inbound = try await session.pumpOnce(deadline: Date().addingTimeInterval(30))
                } catch let err as ACPSessionError where err.code == "timeout" {
                    continue
                }
                guard let inbound else { continue }
                if inbound.type == "session.goodbye" {
                    await session.goodbye()
                    break
                }
                try await handle(inbound, session: session, connectionID: id)
                let state = await session.state
                if state == .closed || state == .failed { break }
            }
        } catch {
            lastSessionError = String(describing: error)
            await session.goodbye()
        }
        if let momentary { await momentary.releaseConnection(id) }
        remoteContexts[id] = nil
        surfaceOffers = surfaceOffers.filter { $0.value.connectionID != id }
        sessions[id] = nil
        stateDeliveries[id] = nil
        sessionTasks[id] = nil
    }

    private func handle(_ env: ACPEnvelope, session: ACPSession, connectionID: UUID) async throws {
        switch env.type {
        case "remote.hello":
            try await handleRemoteHello(env, session: session, connectionID: connectionID)
        case "remote.layout.request":
            try await handleRemoteLayoutRequest(env, session: session, connectionID: connectionID)
        case "resource.accept":
            try await handleSurfaceAccept(env, session: session, connectionID: connectionID)
        case "resource.transfer_result":
            try await handleSurfaceTransferResult(env, session: session, connectionID: connectionID)
        case "resource.activation_result":
            try await handleSurfaceActivationResult(env, connectionID: connectionID)
        case "resource.reject", "resource.cancel":
            discardSurfaceOffer(env, connectionID: connectionID)
        case "remote.readiness":
            try await handleRemoteReadiness(env, session: session, connectionID: connectionID)
        case "state.request":
            let node = identity?.nodeID ?? env.source.nodeID
            var payload = lastState?.snapshotPayload(ownerNodeID: node)
                ?? ACPStateRevision.snapshotPayload(authorityEpoch: lastState?.authorityEpoch ?? 0, revision: lastState?.revision ?? 0, resources: [])
            let subscription = requestedResources(env.payload["resources"])
            if case .array(let resources) = payload["resources"] {
                payload["resources"] = .array(filterResources(resources, subscribed: subscription))
            }
            _ = try await session.send(ACPEnvelope(
                acp: "1.2",
                messageID: UUID().uuidString.lowercased(),
                type: "state.snapshot",
                source: ACPEndpoint(nodeID: node),
                destination: ACPEndpoint(nodeID: env.source.nodeID),
                timestampUTC: currentTimestampUTC(),
                correlationID: env.correlationID ?? env.messageID,
                qos: .reliable,
                payload: payload
            ))
            if var context = remoteContexts[connectionID], context.helloCompleted {
                context.snapshotDeliveredRevision = lastState?.revision ?? 0
                context.subscribedResources = subscription
                remoteContexts[connectionID] = context
            }
        case "command.execute":
            // The first mutation milestone is Remote-profile GO only. Generic
            // command.execute remains closed until it has an equivalent
            // synchronization/readiness contract.
            try await sendAcknowledgement(
                result: PrismACPAdmissionResult(disposition: "rejected", reason: "remote_profile_required"),
                request: env,
                session: session
            )
        case "command.status_request":
            try await handleCommandStatusRequest(env, session: session, connectionID: connectionID)
        case "remote.control.invoke":
            guard let context = remoteContexts[connectionID],
                  context.helloCompleted,
                  context.ready,
                  context.principalNodeID == env.source.nodeID,
                  policy.permitsMutation(principalNodeID: context.principalNodeID)
            else {
                try await sendAcknowledgement(
                    result: PrismACPAdmissionResult(disposition: "rejected", reason: "remote_not_ready_or_unauthorized"),
                    request: env,
                    session: session
                )
                return
            }
            guard case .string(let controlID) = env.payload["control_id"],
                  case .string(let interaction) = env.payload["interaction"],
                  let remoteInteraction = ACPRemoteInteraction(rawValue: interaction),
                  let remoteControl = PrismACPRemoteProfile.executionLayout(
                    for: lastState,
                    mutationsEnabled: true,
                    blackoutClearEnabled: policy.permitsBlackoutClear(principalNodeID: context.principalNodeID)
                  ).control(controlID)
            else {
                try await sendAcknowledgement(
                    result: PrismACPAdmissionResult(disposition: "rejected", reason: "unsupported_control"),
                    request: env,
                    session: session
                )
                return
            }
            guard invocationMatchesCurrentSurface(env.payload) else {
                try await sendAcknowledgement(
                    result: PrismACPAdmissionResult(disposition: "rejected", reason: "remote.layout.stale"),
                    request: env,
                    session: session
                )
                return
            }
            guard let name = prismActionName(bindingAction: remoteControl.action, payload: env.payload) else {
                try await sendAcknowledgement(
                    result: PrismACPAdmissionResult(disposition: "rejected", reason: "unsupported_control"),
                    request: env,
                    session: session
                )
                return
            }
            let validInteraction: Bool
            switch remoteControl.action {
            case "output.grand_master.set": validInteraction = [.set, .adjust].contains(remoteInteraction)
            case "output.blackout.set": validInteraction = remoteInteraction == .set
            default: validInteraction = remoteInteraction == .activate
            }
            guard validInteraction else {
                try await sendAcknowledgement(
                    result: PrismACPAdmissionResult(disposition: "rejected", reason: "invalid_interaction"),
                    request: env,
                    session: session
                )
                return
            }
            let commandID: String
            if case .string(let id) = env.payload["idempotency_key"] {
                commandID = id
            } else if case .string(let id) = env.payload["invocation_id"] {
                commandID = id
            } else {
                commandID = env.messageID
            }
            let value: Double?
            switch env.payload["value"] {
            case .double(let number): value = number
            case .int(let number): value = Double(number)
            case .uint(let number): value = Double(number)
            default: value = nil
            }
            let action = PrismACPAction(
                name: name,
                commandID: commandID,
                originNodeID: env.source.nodeID,
                originInstanceID: context.principalInstanceID,
                originPrincipal: env.source.nodeID,
                originSessionID: env.sessionID,
                idempotencyKey: commandID,
                parameter: remoteParameter(bindingAction: remoteControl.action, payload: env.payload),
                value: value,
                preconditions: decodePreconditions(env.payload["preconditions"]),
                freshnessRejection: remoteControl.action == "cue.go"
                    ? PrismACPInvocationFreshness.rejectionReason(payload: env.payload)
                    : nil
            )
            try await acknowledge(action, request: env, session: session)
        case "remote.momentary.refresh":
            try await handleMomentaryRefresh(env, session: session, connectionID: connectionID)
        case "remote.error", "error.report", "health.heartbeat":
            break
        default:
            try await sendRemote(
                type: "error.report",
                payload: [
                    "code": .string("unsupported_message"),
                    "category": .string("protocol"),
                    "severity": .string("error"),
                    "message": .string("Prism does not implement \(env.type)"),
                    "retryable": .bool(false),
                ],
                request: env,
                session: session
            )
        }
    }

    private func sessionCapabilities() -> [ACPCapability] {
        // This is protocol support, not per-principal authorization or current
        // control availability. Keep versions sourced from the frozen preset.
        let supported: Set<String> = [
            "remote.profile", "remote.layout", "remote.control.invoke",
            "remote.control.momentary", "remote.control.state", "remote.readiness",
            "remote.asset_sync", "remote.surfaces", "resource.transfer",
            "command.status", "cue.go", "control.momentary",
            "output.grand_master", "output.blackout", "output.blackout.engage",
            "output.blackout.clear", "state.live", "system.health",
        ]
        return ACPCapabilitySet.prismRemoteProvider.filter { supported.contains($0.id) }
    }

    private func handleRemoteHello(_ env: ACPEnvelope, session: ACPSession, connectionID: UUID) async throws {
        let remoteNodeID: String?
        let remoteInstanceID: String?
        if case .object(let remote) = env.payload["remote"], case .string(let nodeID) = remote["node_id"] {
            remoteNodeID = nodeID
            if case .string(let instanceID) = remote["instance_id"] { remoteInstanceID = instanceID } else { remoteInstanceID = nil }
        } else {
            remoteNodeID = nil
            remoteInstanceID = nil
        }
        let peerInstanceID = await session.peer?.instanceID
        guard remoteNodeID == env.source.nodeID,
              let remoteInstanceID,
              remoteInstanceID == peerInstanceID
        else {
            try await sendRemote(
                type: "remote.hello_ack",
                payload: [
                    "accepted": .bool(false),
                    "error": .object([
                        "code": .string("remote.authentication_failed"),
                        "category": .string("authentication"),
                        "severity": .string("error"),
                        "message": .string("remote.node_id does not match the authenticated source"),
                        "retryable": .bool(false),
                    ]),
                ],
                request: env,
                session: session
            )
            return
        }
        var context = remoteContexts[connectionID] ?? PrismACPRemoteContext()
        context.helloCompleted = true
        context.principalNodeID = env.source.nodeID
        context.principalInstanceID = remoteInstanceID
        if case .array(let capabilities) = env.payload["capabilities"] {
            context.clientCapabilities = Set(capabilities.compactMap { item in
                if case .string(let value) = item { return value }
                if case .object(let value) = item, case .string(let id) = value["id"] { return id }
                return nil
            })
        }
        remoteContexts[connectionID] = context
        let operatorEnabled = policy.permitsMutation(principalNodeID: env.source.nodeID)
        let blackoutClearEnabled = policy.permitsBlackoutClear(principalNodeID: env.source.nodeID)
        let layout = PrismACPRemoteProfile.layout(
            for: lastState,
            mutationsEnabled: operatorEnabled,
            blackoutClearEnabled: blackoutClearEnabled
        )
        try await sendRemote(
            type: "remote.hello_ack",
            payload: [
                "accepted": .bool(true),
                "permissions": .object(PrismACPRemoteProfile.permissionsPayload(
                    operatorEnabled: operatorEnabled,
                    blackoutClearEnabled: blackoutClearEnabled
                )),
                "show_id": .string(PrismACPRemoteProfile.showID(for: lastState)),
                "show_revision": .uint(lastState?.revision ?? 0),
                "surface_id": layout["surface_id"] ?? .string(PrismACPRemoteProfile.surfaceID(for: lastState)),
                "layout_revision": layout["revision"] ?? .uint(1),
            ],
            request: env,
            session: session
        )
    }

    private func handleRemoteLayoutRequest(_ env: ACPEnvelope, session: ACPSession, connectionID: UUID) async throws {
        guard var context = remoteContexts[connectionID], context.helloCompleted, context.principalNodeID == env.source.nodeID else { return }
        let operatorEnabled = policy.permitsMutation(principalNodeID: context.principalNodeID)
        let blackoutClearEnabled = policy.permitsBlackoutClear(principalNodeID: context.principalNodeID)
        var layout = PrismACPRemoteProfile.layout(
            for: lastState,
            mutationsEnabled: operatorEnabled,
            blackoutClearEnabled: blackoutClearEnabled
        )
        let digest = PrismACPRemoteProfile.layoutHash(layout)
        layout["sha256"] = .string(digest)
        let cachedDigest: String? = if case .string(let value) = env.payload["cached_sha256"] { value }
            else if case .string(let value) = env.payload["sha256"] { value }
            else { nil }
        let negotiatedCapabilities = await session.negotiatedCapabilities
        let supportsTransfer = negotiatedCapabilities.contains("resource.transfer")
        if cachedDigest == digest {
            context.layoutDelivered = true
            context.layoutActivated = true
            remoteContexts[connectionID] = context
            try await sendRemote(
                type: "remote.layout.report",
                payload: surfaceReport(layout: layout, digest: digest, cached: true),
                request: env,
                session: session
            )
        } else if supportsTransfer, let data = PrismACPRemoteProfile.layoutData(layout), data.count <= 1_048_576 {
            surfaceOffers = surfaceOffers.filter { $0.value.connectionID != connectionID }
            let transferID = UUID().uuidString.lowercased()
            let revision = uintValue(layout["revision"]) ?? 1
            surfaceOffers[transferID] = SurfaceOffer(
                connectionID: connectionID,
                data: data,
                digest: digest,
                revision: revision
            )
            context.layoutDelivered = false
            context.layoutActivated = false
            remoteContexts[connectionID] = context
            try await sendRemote(
                type: "remote.layout.report",
                payload: surfaceReport(layout: layout, digest: digest, cached: false),
                request: env,
                session: session
            )
            try await sendRemote(
                type: "resource.offer",
                payload: [
                    "transfer_id": .string(transferID),
                    "asset": .object(surfaceAsset(layout: layout, digest: digest, size: data.count)),
                    "purpose": .string("remote.surface"),
                    "locator": .object(["mode": .string("chunked")]),
                    "max_chunk_bytes": .uint(32_768),
                ],
                request: env,
                session: session
            )
        } else {
            try await sendRemote(
                type: "remote.error",
                payload: [
                    "code": .string("capability_not_permitted"),
                    "category": .string("capability"),
                    "severity": .string("error"),
                    "message": .string("resource.transfer is required for Remote surfaces"),
                    "retryable": .bool(false),
                ],
                request: env,
                session: session
            )
        }
        try await sendRemote(
            type: "remote.control.snapshot",
            payload: PrismACPRemoteProfile.controlSnapshot(
                for: lastState,
                mutationsEnabled: operatorEnabled,
                blackoutClearEnabled: blackoutClearEnabled,
                momentaryHolds: momentaryHolds
            ),
            request: env,
            session: session
        )
    }

    private func handleRemoteReadiness(_ env: ACPEnvelope, session: ACPSession, connectionID: UUID) async throws {
        let context = remoteContexts[connectionID]
        let operatorEnabled = context.map { policy.permitsMutation(principalNodeID: $0.principalNodeID) } ?? false
        let blackoutClearEnabled = context.map { policy.permitsBlackoutClear(principalNodeID: $0.principalNodeID) } ?? false
        let layout = PrismACPRemoteProfile.layout(
            for: lastState,
            mutationsEnabled: operatorEnabled,
            blackoutClearEnabled: blackoutClearEnabled
        )
        let expectedRevision = PrismACPRemoteProfile.surfaceRevision
        let expectedHash = PrismACPRemoteProfile.layoutHash(layout)
        let requestedRevision = uintValue(env.payload["layout_revision"])
        let requestedSnapshot = uintValue(env.payload["snapshot_revision"])
        let requestedHash: String? = if case .string(let value) = env.payload["layout_hash"] { value } else { nil }
        let ready = context?.helloCompleted == true
            && context?.layoutDelivered == true
            && context?.layoutActivated == true
            && context?.snapshotDeliveredRevision == (lastState?.revision ?? 0)
            && requestedRevision == expectedRevision
            && requestedSnapshot == (lastState?.revision ?? 0)
            && requestedHash == expectedHash
        if var updated = context {
            updated.ready = ready
            remoteContexts[connectionID] = updated
        }
        var payload: [String: AnySendable] = [
            "state": .string(ready ? "ready" : "syncing_state"),
            "layout_revision": .uint(expectedRevision),
            "layout_hash": .string(expectedHash),
            "snapshot_revision": .uint(lastState?.revision ?? 0),
            "permissions_revision": .uint(PrismACPRemoteProfile.permissionsRevision),
        ]
        if !ready { payload["reason"] = .string("surface or authoritative state is stale") }
        try await sendRemote(type: "remote.readiness.changed", payload: payload, request: env, session: session)
    }

    private func handleSurfaceAccept(_ env: ACPEnvelope, session: ACPSession, connectionID: UUID) async throws {
        guard case .string(let transferID) = env.payload["transfer_id"],
              let offer = surfaceOffers[transferID], offer.connectionID == connectionID,
              remoteContexts[connectionID]?.principalNodeID == env.source.nodeID
        else { return }
        let requested = uintValue(env.payload["max_chunk_bytes"]) ?? 32_768
        let chunkSize = Int(max(1, min(requested, 32_768)))
        var offset = 0
        while offset < offer.data.count {
            let end = min(offset + chunkSize, offer.data.count)
            let chunk = offer.data.subdata(in: offset..<end)
            try await sendRemote(
                type: "resource.chunk",
                payload: [
                    "transfer_id": .string(transferID),
                    "offset": .uint(UInt64(offset)),
                    "length": .uint(UInt64(chunk.count)),
                    "data": .string(chunk.base64EncodedString()),
                ],
                request: env,
                session: session
            )
            offset = end
        }
        try await sendRemote(
            type: "resource.complete",
            payload: ["transfer_id": .string(transferID)],
            request: env,
            session: session
        )
    }

    private func handleSurfaceTransferResult(
        _ env: ACPEnvelope,
        session: ACPSession,
        connectionID: UUID
    ) async throws {
        guard case .string(let transferID) = env.payload["transfer_id"],
              var offer = surfaceOffers[transferID], offer.connectionID == connectionID,
              remoteContexts[connectionID]?.principalNodeID == env.source.nodeID
        else { return }
        if case .string("verified") = env.payload["status"] {
            offer.verified = true
            surfaceOffers[transferID] = offer
            try await sendRemote(
                type: "resource.activate",
                payload: [
                    "transfer_id": .string(transferID),
                    "idempotency_key": .string(UUID().uuidString.lowercased()),
                ],
                request: env,
                session: session
            )
        } else {
            surfaceOffers[transferID] = nil
        }
    }

    private func handleSurfaceActivationResult(_ env: ACPEnvelope, connectionID: UUID) async throws {
        guard case .string(let transferID) = env.payload["transfer_id"],
              let offer = surfaceOffers[transferID], offer.connectionID == connectionID,
              remoteContexts[connectionID]?.principalNodeID == env.source.nodeID
        else { return }
        guard offer.verified, case .string("applied") = env.payload["status"] else {
            surfaceOffers[transferID] = nil
            return
        }
        let operatorEnabled = remoteContexts[connectionID].map {
            policy.permitsMutation(principalNodeID: $0.principalNodeID)
        } ?? false
        let blackoutClearEnabled = remoteContexts[connectionID].map {
            policy.permitsBlackoutClear(principalNodeID: $0.principalNodeID)
        } ?? false
        let currentLayout = PrismACPRemoteProfile.layout(
            for: lastState,
            mutationsEnabled: operatorEnabled,
            blackoutClearEnabled: blackoutClearEnabled
        )
        guard PrismACPRemoteProfile.layoutHash(currentLayout) == offer.digest else {
            surfaceOffers[transferID] = nil
            return
        }
        if var context = remoteContexts[connectionID] {
            context.layoutDelivered = true
            context.layoutActivated = true
            remoteContexts[connectionID] = context
        }
        surfaceOffers[transferID] = nil
    }

    private func discardSurfaceOffer(_ env: ACPEnvelope, connectionID: UUID) {
        guard case .string(let transferID) = env.payload["transfer_id"],
              surfaceOffers[transferID]?.connectionID == connectionID
        else { return }
        surfaceOffers[transferID] = nil
    }

    private func surfaceReport(
        layout: [String: AnySendable],
        digest: String,
        cached: Bool
    ) -> [String: AnySendable] {
        let size = PrismACPRemoteProfile.layoutData(layout)?.count ?? 0
        return [
            "surface_id": layout["surface_id"]!,
            "revision": layout["revision"]!,
            "sha256": .string(digest),
            "asset": .object(surfaceAsset(layout: layout, digest: digest, size: size)),
            "cached": .bool(cached),
        ]
    }

    private func surfaceAsset(
        layout: [String: AnySendable],
        digest: String,
        size: Int
    ) -> [String: AnySendable] {
        [
            "asset_id": layout["surface_id"]!,
            "asset_type": .string("aurora.remote.surface"),
            "revision": layout["revision"]!,
            "sha256": .string(digest),
            "size_bytes": .uint(UInt64(size)),
            "media_type": .string("application/json"),
        ]
    }

    private func requestedResources(_ encoded: AnySendable?) -> Set<String>? {
        guard case .array(let values) = encoded else { return nil }
        let resources = Set(values.compactMap { item -> String? in
            if case .string(let value) = item { return value }
            return nil
        })
        return resources.isEmpty ? nil : resources
    }

    private func filterResources(_ resources: [AnySendable], subscribed: Set<String>?) -> [AnySendable] {
        guard let subscribed else { return resources }
        return resources.filter { item in
            guard case .object(let object) = item, case .string(let name) = object["resource"] else { return false }
            return subscribed.contains(name)
        }
    }

    private func handleCommandStatusRequest(_ env: ACPEnvelope, session: ACPSession, connectionID: UUID) async throws {
        guard let context = remoteContexts[connectionID],
              context.helloCompleted,
              context.principalNodeID == env.source.nodeID
        else {
            try await sendRemote(
                type: "command.status_report",
                payload: ["disposition": .string("unknown")],
                request: env,
                session: session
            )
            return
        }
        if case .string(let requestedOrigin) = env.payload["origin_node_id"], requestedOrigin != context.principalNodeID {
            try await sendRemote(
                type: "command.status_report",
                payload: ["disposition": .string("unknown")],
                request: env,
                session: session
            )
            return
        }
        let commandID: String? = if case .string(let value) = env.payload["command_id"] { value } else { nil }
        let idempotencyKey: String? = if case .string(let value) = env.payload["idempotency_key"] { value } else { nil }
        let record = await dispositions.lookup(
            originNodeID: context.principalNodeID,
            commandID: commandID,
            idempotencyKey: idempotencyKey,
            originPrincipal: context.principalNodeID
        )
        try await sendRemote(
            type: "command.status_report",
            payload: record?.reportPayload() ?? ["disposition": .string("unknown")],
            request: env,
            session: session
        )
    }

    private func handleMomentaryInvoke(
        _ env: ACPEnvelope,
        interaction: String,
        session: ACPSession,
        connectionID: UUID
    ) async throws {
        guard let context = remoteContexts[connectionID], context.ready,
              context.principalNodeID == env.source.nodeID,
              policy.permitsMutation(principalNodeID: context.principalNodeID),
              let momentary,
              case .string(let activationID) = env.payload["invocation_id"]
        else {
            try await sendAcknowledgement(
                result: PrismACPAdmissionResult(disposition: "rejected", reason: "remote_not_ready_or_unauthorized"),
                request: env,
                session: session
            )
            return
        }
        let outcome: PrismACPMomentaryResult
        switch interaction {
        case "momentary_begin":
            if let reason = PrismACPInvocationFreshness.rejectionReason(payload: env.payload) {
                outcome = PrismACPMomentaryResult(disposition: "expired", reason: reason)
            } else {
                outcome = await momentary.begin(
                    controlID: "lease_test",
                    activationID: activationID,
                    principalNodeID: context.principalNodeID,
                    connectionID: connectionID,
                    requestedLeaseMS: uintValue(env.payload["requested_lease_ms"]) ?? 1_000
                )
            }
        case "momentary_end", "momentary_cancel":
            guard case .string(let leaseID) = env.payload["lease_id"] else {
                outcome = PrismACPMomentaryResult(disposition: "rejected", reason: "remote.momentary.unknown_invocation")
                break
            }
            outcome = await momentary.end(
                activationID: activationID,
                leaseID: leaseID,
                principalNodeID: context.principalNodeID,
                cancelled: interaction == "momentary_cancel"
            )
        default:
            outcome = PrismACPMomentaryResult(disposition: "rejected", reason: "invalid_interaction")
        }
        try await sendAcknowledgement(
            result: momentaryAdmission(outcome),
            request: env,
            session: session
        )
        await publishMomentaryState(momentaryHolds)
    }

    private func handleMomentaryRefresh(
        _ env: ACPEnvelope,
        session: ACPSession,
        connectionID: UUID
    ) async throws {
        guard let context = remoteContexts[connectionID], context.ready,
              context.principalNodeID == env.source.nodeID,
              policy.permitsMutation(principalNodeID: context.principalNodeID),
              let momentary,
              case .string("lease_test") = env.payload["control_id"],
              case .string(let activationID) = env.payload["invocation_id"],
              case .string(let leaseID) = env.payload["lease_id"]
        else {
            try await sendAcknowledgement(
                result: PrismACPAdmissionResult(disposition: "rejected", reason: "remote.momentary.unknown_invocation"),
                request: env,
                session: session
            )
            return
        }
        let outcome = await momentary.renew(
            controlID: "lease_test",
            activationID: activationID,
            leaseID: leaseID,
            principalNodeID: context.principalNodeID
        )
        try await sendAcknowledgement(result: momentaryAdmission(outcome), request: env, session: session)
        await publishMomentaryState(momentaryHolds)
    }

    private func momentaryAdmission(_ outcome: PrismACPMomentaryResult) -> PrismACPAdmissionResult {
        var result: [String: AnySendable] = [:]
        if let hold = outcome.hold {
            result["control_id"] = .string(hold.controlID)
            result["activation_id"] = .string(hold.activationID)
            result["lease_id"] = .string(hold.leaseID)
            result["granted_lease_ms"] = .uint(hold.grantedLeaseMS)
            result["renew_before_ms"] = .uint(hold.grantedLeaseMS / 2)
            result["release_pending"] = .bool(hold.releasePending)
            if let active = hold.physicalActive { result["physical_active"] = .bool(active) }
        } else {
            result["active"] = .bool(false)
        }
        return PrismACPAdmissionResult(disposition: outcome.disposition, reason: outcome.reason, result: result)
    }

    private func momentaryDidChange(_ holds: [PrismACPMomentaryHold]) async {
        momentaryHolds = holds
        Task { [weak self] in
            // Command handlers publish immediately after their acknowledgement.
            // Timer/disconnect/recovery changes have no acknowledgement, so this
            // delayed path guarantees they still become wire-visible.
            try? await Task.sleep(nanoseconds: 50_000_000)
            await self?.publishMomentaryState(holds)
        }
    }

    private func publishMomentaryState(_ holds: [PrismACPMomentaryHold]) async {
        // Ignore superseded publications; only the latest durable hold set is
        // allowed onto the wire.
        guard holds == momentaryHolds, holds != lastPublishedMomentaryHolds else { return }
        lastPublishedMomentaryHolds = holds
        let active = holds.contains { $0.physicalActive != false }
        let releasePending = holds.contains { $0.releasePending }
        let value: AnySendable = .object([
            "active": .bool(active),
            "release_pending": .bool(releasePending),
            "physical_active": .bool(active),
        ])
        for (id, context) in remoteContexts where context.ready {
            guard let session = sessions[id] else { continue }
            do {
                _ = try await session.send(ACPEnvelope(
                    acp: "1.2",
                    messageID: UUID().uuidString.lowercased(),
                    type: "remote.control.state",
                    source: ACPEndpoint(nodeID: identity?.nodeID ?? context.principalNodeID),
                    destination: ACPEndpoint(nodeID: context.principalNodeID),
                    timestampUTC: currentTimestampUTC(),
                    qos: .latest,
                    payload: [
                        "control_id": .string("lease_test"),
                        "revision": .uint(lastState?.revision ?? 0),
                        "enabled": .bool(true),
                        "available": .bool(true),
                        "confidence": .string(releasePending ? "unverified" : "confirmed"),
                        "value": value,
                    ]
                ))
            } catch {
                remoteContexts[id]?.ready = false
                lastSessionError = String(describing: error)
            }
        }
    }

    private func sendRemote(type: String, payload: [String: AnySendable], request: ACPEnvelope, session: ACPSession) async throws {
        _ = try await session.send(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: type,
            source: ACPEndpoint(nodeID: identity?.nodeID ?? request.source.nodeID),
            destination: ACPEndpoint(nodeID: request.source.nodeID),
            timestampUTC: currentTimestampUTC(),
            correlationID: request.correlationID ?? request.messageID,
            causationID: request.messageID,
            qos: .reliable,
            payload: payload
        ))
    }

    private func uintValue(_ value: AnySendable?) -> UInt64? {
        switch value {
        case .uint(let value): return value
        case .int(let value) where value >= 0: return UInt64(value)
        default: return nil
        }
    }

    private func currentTimestampUTC() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func decodePreconditions(_ encoded: AnySendable?) -> [ACPPrecondition] {
        guard case .array(let values) = encoded else { return [] }
        return values.compactMap { item in
            guard case .object(let object) = item,
                  case .string(let op) = object["op"],
                  case .string(let field) = object["field"],
                  let value = object["value"]
            else { return nil }
            let resource: String?
            if case .string(let text) = object["resource"] { resource = text } else { resource = nil }
            let resourceField: String?
            if case .string(let text) = object["resource_field"] { resourceField = text } else { resourceField = nil }
            return ACPPrecondition(op: op, field: field, value: value, resource: resource, resourceField: resourceField)
        }
    }

    private func invocationMatchesCurrentSurface(_ payload: [String: AnySendable]) -> Bool {
        if case .string(let showID) = payload["show_id"], showID != PrismACPRemoteProfile.showID(for: lastState) {
            return false
        }
        if let showRevision = uintValue(payload["show_revision"]), showRevision != (lastState?.revision ?? 0) {
            return false
        }
        let requestedSurface: String? = {
            if case .string(let value) = payload["surface_id"] { return value }
            if case .string(let value) = payload["layout_id"] { return value }
            return nil
        }()
        if let requestedSurface, requestedSurface != PrismACPRemoteProfile.surfaceID(for: lastState) {
            return false
        }
        if let revision = uintValue(payload["layout_revision"]), revision != PrismACPRemoteProfile.surfaceRevision {
            return false
        }
        return true
    }

    private func prismActionName(bindingAction: String, payload: [String: AnySendable]) -> String? {
        switch bindingAction {
        case "cue.go": return "performance.go"
        case "output.grand_master.set": return "output.master"
        case "output.blackout.set":
            if case .bool(true) = payload["value"] { return "blackoutOn" }
            if case .bool(false) = payload["value"] { return "blackoutOff" }
            return nil
        default: return nil
        }
    }

    private func remoteParameter(bindingAction: String, payload: [String: AnySendable]) -> String? {
        return nil
    }

    private func releaseMomentaryHold(
        _ hold: PrismACPMomentaryHold
    ) async -> (confirmedInactive: Bool, physicalActive: Bool?) {
        if hold.controlID == "lease_test" {
            return (confirmedInactive: true, physicalActive: false)
        }
        guard let hostMomentaryRelease else {
            return (confirmedInactive: false, physicalActive: true)
        }
        return await hostMomentaryRelease(hold)
    }

    private func acknowledge(_ action: PrismACPAction, request: ACPEnvelope, session: ACPSession) async throws {
        let result: PrismACPAdmissionResult
        do {
            result = try await admit(action)
        } catch PrismACPActionRouterError.preconditionFailed {
            result = PrismACPAdmissionResult(disposition: "precondition_failed", reason: "precondition_failed")
        } catch let PrismACPActionRouterError.unavailable(reason) {
            result = PrismACPAdmissionResult(disposition: "rejected", reason: reason)
        } catch let PrismACPActionRouterError.rejected(reason) {
            result = PrismACPAdmissionResult(disposition: "rejected", reason: reason)
        } catch {
            result = PrismACPAdmissionResult(disposition: "rejected", reason: "not_authorized_or_unsupported")
        }
        try await sendAcknowledgement(result: result, request: request, session: session)
    }

    private func sendAcknowledgement(result: PrismACPAdmissionResult, request: ACPEnvelope, session: ACPSession) async throws {
        var resultPayload = result.result
        if let epoch = result.resultingEpoch { resultPayload["authority_epoch"] = .uint(epoch) }
        if let revision = result.resultingRevision { resultPayload["snapshot_revision"] = .uint(revision) }
        var payload: [String: AnySendable] = ["status": .string(result.disposition)]
        let commandID: String
        if case .string(let value) = request.payload["idempotency_key"] {
            commandID = value
        } else if case .string(let value) = request.payload["invocation_id"] {
            commandID = value
        } else {
            commandID = request.messageID
        }
        payload["command_id"] = .string(commandID)
        if let epoch = result.resultingEpoch { payload["resulting_epoch"] = .uint(epoch) }
        if let revision = result.resultingRevision { payload["resulting_revision"] = .uint(revision) }
        if !resultPayload.isEmpty { payload["result"] = .object(resultPayload) }
        if let reason = result.reason {
            let category = reason == "remote_not_ready_or_unauthorized"
                || reason == "not_authorized_or_unsupported"
                ? "authorization"
                : "validation"
            payload["error"] = .object([
                "code": .string(reason),
                "category": .string(category),
                "severity": .string("warning"),
                "message": .string(reason),
                "retryable": .bool(false),
            ])
        }
        _ = try await session.send(ACPEnvelope(
            acp: "1.2",
            messageID: UUID().uuidString.lowercased(),
            type: "command.ack",
            source: ACPEndpoint(nodeID: identity?.nodeID ?? request.source.nodeID),
            destination: ACPEndpoint(nodeID: request.source.nodeID),
            timestampUTC: currentTimestampUTC(),
            correlationID: request.correlationID ?? request.messageID,
            qos: .reliable,
            payload: payload
        ))
    }
}
