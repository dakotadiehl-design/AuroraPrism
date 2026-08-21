import Foundation

public struct PrismACPMomentaryHold: Codable, Sendable, Equatable {
    public var controlID: String
    public var activationID: String
    public var leaseID: String
    public var principalNodeID: String
    public var connectionID: UUID
    public var expiresAt: Date
    public var grantedLeaseMS: UInt64
    public var releasePending: Bool
    public var physicalActive: Bool?
}

public struct PrismACPMomentaryResult: Sendable, Equatable {
    public var disposition: String
    public var reason: String?
    public var hold: PrismACPMomentaryHold?
}

public actor PrismACPMomentaryAuthority {
    public typealias ReleaseHandler = @Sendable (PrismACPMomentaryHold) async -> (confirmedInactive: Bool, physicalActive: Bool?)
    public typealias ChangeHandler = @Sendable ([PrismACPMomentaryHold]) async -> Void

    private let storeURL: URL
    private let releaseHandler: ReleaseHandler
    private let onChange: ChangeHandler
    private var holds: [String: PrismACPMomentaryHold] = [:]
    private let clock = ContinuousClock()
    private var deadlines: [String: ContinuousClock.Instant] = [:]
    private var expiryTask: Task<Void, Never>?
    private var started = false

    public init(
        storeURL: URL,
        releaseHandler: @escaping ReleaseHandler,
        onChange: @escaping ChangeHandler = { _ in }
    ) {
        self.storeURL = storeURL
        self.releaseHandler = releaseHandler
        self.onChange = onChange
    }

    public func start() async {
        guard !started else { return }
        started = true
        load()
        // A persisted hold is conservatively active after restart. Enter the
        // same durable release transaction before any listener is opened.
        for activationID in Array(holds.keys) {
            _ = await release(activationID: activationID, leaseID: nil, principalNodeID: nil, reason: "restart")
        }
        expiryTask = Task { [weak self] in await self?.expiryLoop() }
        await publish()
    }

    public func begin(
        controlID: String,
        activationID: String,
        principalNodeID: String,
        connectionID: UUID,
        requestedLeaseMS: UInt64
    ) async -> PrismACPMomentaryResult {
        if let existing = holds[activationID] {
            guard existing.controlID == controlID, existing.principalNodeID == principalNodeID else {
                return PrismACPMomentaryResult(disposition: "conflict", reason: "command_identity_conflict")
            }
            return PrismACPMomentaryResult(disposition: "applied", hold: existing)
        }
        let granted = min(2_000, max(250, requestedLeaseMS))
        let hold = PrismACPMomentaryHold(
            controlID: controlID,
            activationID: activationID,
            leaseID: UUID().uuidString.lowercased(),
            principalNodeID: principalNodeID,
            connectionID: connectionID,
            expiresAt: Date().addingTimeInterval(Double(granted) / 1_000),
            grantedLeaseMS: granted,
            releasePending: false,
            physicalActive: true
        )
        holds[activationID] = hold
        deadlines[activationID] = clock.now.advanced(by: .milliseconds(Int64(granted)))
        guard persist() else {
            holds[activationID] = nil
            deadlines[activationID] = nil
            return PrismACPMomentaryResult(disposition: "failed", reason: "hold_persistence_failed")
        }
        await publish()
        return PrismACPMomentaryResult(disposition: "applied", hold: hold)
    }

    public func renew(
        controlID: String,
        activationID: String,
        leaseID: String,
        principalNodeID: String
    ) async -> PrismACPMomentaryResult {
        guard var hold = holds[activationID], hold.controlID == controlID,
              hold.leaseID == leaseID, hold.principalNodeID == principalNodeID,
              !hold.releasePending
        else { return PrismACPMomentaryResult(disposition: "rejected", reason: "remote.momentary.unknown_invocation") }
        hold.expiresAt = Date().addingTimeInterval(Double(hold.grantedLeaseMS) / 1_000)
        holds[activationID] = hold
        deadlines[activationID] = clock.now.advanced(by: .milliseconds(Int64(hold.grantedLeaseMS)))
        guard persist() else { return PrismACPMomentaryResult(disposition: "failed", reason: "hold_persistence_failed", hold: hold) }
        await publish()
        return PrismACPMomentaryResult(disposition: "applied", hold: hold)
    }

    public func end(
        activationID: String,
        leaseID: String,
        principalNodeID: String,
        cancelled: Bool
    ) async -> PrismACPMomentaryResult {
        await release(
            activationID: activationID,
            leaseID: leaseID,
            principalNodeID: principalNodeID,
            reason: cancelled ? "cancel" : "end"
        )
    }

    public func releaseConnection(_ connectionID: UUID) async {
        for hold in holds.values where hold.connectionID == connectionID {
            _ = await release(activationID: hold.activationID, leaseID: nil, principalNodeID: nil, reason: "disconnect")
        }
    }

    public func revokePrincipal(_ nodeID: String) async {
        for hold in holds.values where hold.principalNodeID.caseInsensitiveCompare(nodeID) == .orderedSame {
            _ = await release(activationID: hold.activationID, leaseID: nil, principalNodeID: nil, reason: "authorization_removed")
        }
    }

    public func removeControl(_ controlID: String) async {
        for hold in holds.values where hold.controlID == controlID {
            _ = await release(activationID: hold.activationID, leaseID: nil, principalNodeID: nil, reason: "control_removed")
        }
    }

    public func shutdown() async {
        expiryTask?.cancel()
        expiryTask = nil
        for activationID in Array(holds.keys) {
            _ = await release(activationID: activationID, leaseID: nil, principalNodeID: nil, reason: "shutdown")
        }
        started = false
    }

    public func snapshot() -> [PrismACPMomentaryHold] {
        holds.values.sorted { $0.activationID < $1.activationID }
    }

    private func expiryLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard !Task.isCancelled else { return }
            let now = clock.now
            for hold in holds.values where deadlines[hold.activationID].map({ $0 <= now }) == true && !hold.releasePending {
                _ = await release(activationID: hold.activationID, leaseID: nil, principalNodeID: nil, reason: "expiry")
            }
        }
    }

    private func release(
        activationID: String,
        leaseID: String?,
        principalNodeID: String?,
        reason: String
    ) async -> PrismACPMomentaryResult {
        guard var hold = holds[activationID] else {
            return PrismACPMomentaryResult(disposition: "completed", reason: "already_released")
        }
        if let leaseID, leaseID != hold.leaseID {
            return PrismACPMomentaryResult(disposition: "rejected", reason: "remote.momentary.unknown_invocation", hold: hold)
        }
        if let principalNodeID, principalNodeID.caseInsensitiveCompare(hold.principalNodeID) != .orderedSame {
            return PrismACPMomentaryResult(disposition: "rejected", reason: "remote.control.permission_denied", hold: hold)
        }
        hold.releasePending = true
        holds[activationID] = hold
        guard persist() else {
            return PrismACPMomentaryResult(disposition: "failed", reason: "hold_persistence_failed", hold: hold)
        }
        await publish()
        let physical = await releaseHandler(hold)
        if physical.confirmedInactive {
            holds[activationID] = nil
            deadlines[activationID] = nil
            guard persist() else {
                hold.releasePending = true
                hold.physicalActive = physical.physicalActive
                holds[activationID] = hold
                await publish()
                return PrismACPMomentaryResult(disposition: "failed", reason: "hold_persistence_failed", hold: hold)
            }
            await publish()
            return PrismACPMomentaryResult(disposition: "applied", reason: reason)
        }
        hold.releasePending = true
        hold.physicalActive = physical.physicalActive
        holds[activationID] = hold
        _ = persist()
        await publish()
        return PrismACPMomentaryResult(disposition: "failed", reason: "remote.control.unconfirmed_release", hold: hold)
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(holds.values))
            try data.write(to: storeURL, options: .atomic)
            return true
        } catch { return false }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([PrismACPMomentaryHold].self, from: data)
        else { return }
        holds = Dictionary(uniqueKeysWithValues: decoded.map { ($0.activationID, $0) })
    }

    private func publish() async {
        await onChange(snapshot())
    }
}
