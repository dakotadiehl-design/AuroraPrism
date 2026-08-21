import AuroraDiagnostics
import Foundation

/// Boundary used for quantized scheduling (Phase B implements firing).
public enum MusicalBoundary: Codable, Equatable, Sendable, Hashable {
    case immediate
    case next(MusicalDuration)
    case nextBar
    /// Next metrical beat from `MusicalMeter.beatGrouping` — not “next quarter note”.
    case nextMetricalBeat

    public var isImmediate: Bool {
        if case .immediate = self { return true }
        return false
    }
}

public enum QuantizationFailurePolicy: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case cancel
    case executeImmediately
    case holdUntilTimingAvailable
}

public enum ScheduleOrigin: Codable, Equatable, Sendable, Hashable {
    case ameMapping(UUID)
    case sectionEnter(UUID)
    case sectionExit(UUID)
    case simulation
    case other(String)
}

/// Command payload for scheduled work. Safety is **part of the command**, not a free Boolean.
public enum ScheduledCommand: Codable, Equatable, Sendable, Hashable {
    /// Token + derived safety from `AuroraAction.isSafetyCritical` at registration time.
    case auroraActionToken(UUID, isSafetyCritical: Bool)
    /// Emergency path; always safety-critical and always immediate.
    case panicBypass

    public var isSafetyCritical: Bool {
        switch self {
        case .panicBypass: return true
        case .auroraActionToken(_, let s): return s
        }
    }
}

public enum ScheduledMusicalActionError: Error, Equatable, Sendable {
    case safetyMustBeImmediate
}

extension ScheduledMusicalActionError: LocalizedError, PrismDiagnosableError {
    public var errorDescription: String? { userMessage }
    public var prismErrorCode: String { "music.scheduler.safety_must_be_immediate" }
    public var userTitle: String { "That Safety Action Can’t Wait" }
    public var userMessage: String { "This safety action can’t wait for the next beat." }
    public var recoverySuggestion: String? { "Keep panic and other safety actions set to happen immediately." }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .musicScheduler }
    public var prismSeverity: PrismLogLevel { .error }
}

/// Typed scheduled work — no closures, no string action storage.
///
/// Safety is enforced by construction:
/// - `panicBypass` → always immediate + safety-critical
/// - token safety is baked into `ScheduledCommand` and cannot disagree with a separate flag
/// - safety-critical work cannot remain quantized (forced to `.immediate` or rejected)
public struct ScheduledMusicalAction: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var targetBoundary: MusicalBoundary
    public var command: ScheduledCommand
    public var origin: ScheduleOrigin
    public var failurePolicy: QuantizationFailurePolicy
    public var createdAt: HostTime

    /// Derived from command — never independently settable.
    public var isSafetyCritical: Bool { command.isSafetyCritical }

    /// Panic path: always immediate and safety-critical.
    public static func panicBypass(
        id: UUID = UUID(),
        origin: ScheduleOrigin = .other("panic"),
        createdAt: HostTime = .now()
    ) -> ScheduledMusicalAction {
        ScheduledMusicalAction(
            id: id,
            targetBoundary: .immediate,
            command: .panicBypass,
            origin: origin,
            failurePolicy: .executeImmediately,
            createdAt: createdAt
        )
    }

    /// Schedule a registered action token. Safety must match registry metadata for the token.
    /// If `isSafetyCritical`, boundary is forced to `.immediate` (cannot quantize safety).
    public static func actionToken(
        id: UUID = UUID(),
        token: UUID,
        isSafetyCritical: Bool,
        targetBoundary: MusicalBoundary,
        origin: ScheduleOrigin = .other("unspecified"),
        failurePolicy: QuantizationFailurePolicy = .cancel,
        createdAt: HostTime = .now(),
        allowForceImmediateForSafety: Bool = true
    ) throws -> ScheduledMusicalAction {
        var boundary = targetBoundary
        if isSafetyCritical {
            if !boundary.isImmediate {
                if allowForceImmediateForSafety {
                    boundary = .immediate
                } else {
                    throw ScheduledMusicalActionError.safetyMustBeImmediate
                }
            }
        }
        return ScheduledMusicalAction(
            id: id,
            targetBoundary: boundary,
            command: .auroraActionToken(token, isSafetyCritical: isSafetyCritical),
            origin: origin,
            failurePolicy: isSafetyCritical ? .executeImmediately : failurePolicy,
            createdAt: createdAt
        )
    }

    private init(
        id: UUID,
        targetBoundary: MusicalBoundary,
        command: ScheduledCommand,
        origin: ScheduleOrigin,
        failurePolicy: QuantizationFailurePolicy,
        createdAt: HostTime
    ) {
        self.id = id
        // Belt-and-suspenders: panicBypass cannot be quantized even if constructed via decode.
        if case .panicBypass = command {
            self.targetBoundary = .immediate
            self.failurePolicy = .executeImmediately
        } else if command.isSafetyCritical && !targetBoundary.isImmediate {
            self.targetBoundary = .immediate
            self.failurePolicy = .executeImmediately
        } else {
            self.targetBoundary = targetBoundary
            self.failurePolicy = failurePolicy
        }
        self.command = command
        self.origin = origin
        self.createdAt = createdAt
    }

    // Codable: re-normalize on decode so corrupted packages cannot reintroduce quantized panic.
    private enum CodingKeys: String, CodingKey {
        case id, targetBoundary, command, origin, failurePolicy, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let targetBoundary = try c.decode(MusicalBoundary.self, forKey: .targetBoundary)
        let command = try c.decode(ScheduledCommand.self, forKey: .command)
        let origin = try c.decode(ScheduleOrigin.self, forKey: .origin)
        let failurePolicy = try c.decode(QuantizationFailurePolicy.self, forKey: .failurePolicy)
        let createdAt = try c.decode(HostTime.self, forKey: .createdAt)
        self.init(
            id: id,
            targetBoundary: targetBoundary,
            command: command,
            origin: origin,
            failurePolicy: failurePolicy,
            createdAt: createdAt
        )
    }
}

public enum ScheduleEnqueueResult: Equatable, Sendable {
    case accepted(UUID)
    case rejectedQueueFull
    case rejectedInvalid
}
