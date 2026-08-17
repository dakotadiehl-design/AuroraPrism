import AuroraModel
import AuroraMusical
import Foundation

/// Full decision context for a scheduled action (Wave 2 — preserves value/selection/latency).
public struct AuroraScheduledActionPayload: Equatable, Sendable {
    public var action: AuroraAction
    public var isSafetyCritical: Bool
    public var controlValue: Double?
    public var latencyID: UUID
    public var ingressHostTime: HostTime
    public var mappingID: UUID?
    public var orderedFixtureIDs: [UUID]?

    public init(
        action: AuroraAction,
        controlValue: Double? = nil,
        latencyID: UUID = UUID(),
        ingressHostTime: HostTime = .now(),
        mappingID: UUID? = nil,
        orderedFixtureIDs: [UUID]? = nil
    ) {
        self.action = action
        self.isSafetyCritical = action.isSafetyCritical
        self.controlValue = controlValue
        self.latencyID = latencyID
        self.ingressHostTime = ingressHostTime
        self.mappingID = mappingID
        self.orderedFixtureIDs = orderedFixtureIDs
    }
}

/// Resolved token record: action + safety never separated.
public struct AuroraActionTokenRecord: Equatable, Sendable {
    public let token: UUID
    public let payload: AuroraScheduledActionPayload

    public var action: AuroraAction { payload.action }
    public var isSafetyCritical: Bool { payload.isSafetyCritical }

    public init(token: UUID, payload: AuroraScheduledActionPayload) {
        self.token = token
        self.payload = payload
    }

    public init(token: UUID, action: AuroraAction) {
        self.token = token
        self.payload = AuroraScheduledActionPayload(action: action)
    }
}

/// Maps scheduler UUID tokens → scheduled payloads for fire-time resolution.
public final class AuroraActionTokenRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var table: [UUID: AuroraActionTokenRecord] = [:]

    public init() {}

    @discardableResult
    public func registerEphemeral(_ payload: AuroraScheduledActionPayload, token: UUID = UUID()) -> AuroraActionTokenRecord {
        let record = AuroraActionTokenRecord(token: token, payload: payload)
        lock.lock()
        table[token] = record
        lock.unlock()
        return record
    }

    @discardableResult
    public func registerEphemeral(_ action: AuroraAction, token: UUID = UUID()) -> AuroraActionTokenRecord {
        registerEphemeral(AuroraScheduledActionPayload(action: action), token: token)
    }

    @discardableResult
    public func register(_ action: AuroraAction, token: UUID = UUID()) -> UUID {
        registerEphemeral(action, token: token).token
    }

    public func resolve(_ token: UUID) -> AuroraAction? {
        lock.lock(); defer { lock.unlock() }
        return table[token]?.action
    }

    public func resolveRecord(_ token: UUID) -> AuroraActionTokenRecord? {
        lock.lock(); defer { lock.unlock() }
        return table[token]
    }

    public func consume(_ token: UUID) -> AuroraActionTokenRecord? {
        lock.lock()
        defer { lock.unlock() }
        let record = table[token]
        table[token] = nil
        return record
    }

    public func unregister(_ token: UUID) {
        _ = consume(token)
    }

    public func clear() {
        lock.lock()
        table.removeAll()
        lock.unlock()
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return table.count
    }

    public func schedulePayload(
        for action: AuroraAction,
        targetBoundary: MusicalBoundary,
        origin: ScheduleOrigin = .other("bridge"),
        failurePolicy: QuantizationFailurePolicy = .cancel,
        controlValue: Double? = nil,
        latencyID: UUID = UUID(),
        ingressHostTime: HostTime = .now(),
        mappingID: UUID? = nil,
        orderedFixtureIDs: [UUID]? = nil
    ) throws -> ScheduledMusicalAction {
        let payload = AuroraScheduledActionPayload(
            action: action,
            controlValue: controlValue,
            latencyID: latencyID,
            ingressHostTime: ingressHostTime,
            mappingID: mappingID,
            orderedFixtureIDs: orderedFixtureIDs
        )
        let record = registerEphemeral(payload)
        return try ScheduledMusicalAction.actionToken(
            token: record.token,
            isSafetyCritical: record.isSafetyCritical,
            targetBoundary: targetBoundary,
            origin: origin,
            failurePolicy: failurePolicy
        )
    }
}
