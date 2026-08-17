import AuroraModel
import AuroraMusical
import Foundation

// MARK: - Diagnostics

public enum AMEDiagnosticKind: String, Codable, Equatable, Sendable, Hashable {
    case eventReceived
    case triggerMatched
    case triggerMissed
    case mappingCandidate
    case mappingSuppressed
    case mappingDisabled
    case scopeInactive
    case timingRequirementFailed
    case transformRejected
    case behaviorSkipped
    case behaviorFired
    case heldAcquired
    case heldReleased
    case heldReleaseAll
    case heldReleaseEmission
    case heldReleasedByContextChange
    case heldReleasedByDocumentChange
    case heldReleasedByModeChange
    case heldReleasedBySourceDisconnect
    case debounceSuppressed
    case burstSuppressed
    case quantizeImmediate
    case quantizeDeferred
    case quantizeCancelled
    case quantizeHeld
    case dryRunEmission
    case armedEmission
    case unsupportedAction
    case invalidRuntimeConfiguration
    case timestampFallbackUsed
    case sequenceDeferred
    case sequenceStepFired
    case sequenceAdvanced
    case sequenceReset
    case sequenceMissing
    case sequenceEmpty
    case sequenceInvalidStep
    case sequenceControlAction
    case sequenceNoContext
    case modeEditSkipped
    case simulationDomainPurged
    /// AME Learn capture failed (e.g. missing durable source metadata).
    case learnCaptureFailed
}

public struct AMEDiagnosticEvent: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: AMEDiagnosticKind
    public var latencyID: UUID?
    public var mappingID: UUID?
    public var triggerID: UUID?
    public var sequenceID: UUID?
    public var stepIndex: Int?
    public var message: String
    public var hostTime: HostTime?

    public init(
        id: UUID = UUID(),
        kind: AMEDiagnosticKind,
        latencyID: UUID? = nil,
        mappingID: UUID? = nil,
        triggerID: UUID? = nil,
        sequenceID: UUID? = nil,
        stepIndex: Int? = nil,
        message: String,
        hostTime: HostTime? = nil
    ) {
        self.id = id
        self.kind = kind
        self.latencyID = latencyID
        self.mappingID = mappingID
        self.triggerID = triggerID
        self.sequenceID = sequenceID
        self.stepIndex = stepIndex
        self.message = message
        self.hostTime = hostTime
    }
}

// MARK: - Live execution support (Phase D Option B)

/// Emission gate for AME pipeline — must match host executor capability.
///
/// Unsupported product surfaces (effects/presets/etc.) must return `false` so they are not
/// emitted as executable and do not count as AME live fires.
public enum AMELiveActionSupport {
    public static func isLiveSupported(_ action: AuroraAction) -> Bool {
        switch action {
        case .go, .stop, .back,
             .fireCue, .fireCueIndex,
             .programmerAttribute,
             .blackout, .blackoutOff, .toggleBlackout,
             .freeze, .freezeOff, .toggleFreeze,
             .blind, .blindOff, .toggleBlind,
             .masterIntensity, .panic, .clearOverrides, .toggleMIDIPerformance,
             .selectSong, .enterSection, .nextSection, .previousSection,
             .tapTempo, .setTransportStart, .setTransportStop, .setTransportContinue, .setTempoBPM,
             .resetSequence, .advanceSequence, .fireSequenceStep:
            return true
        case .compound(let inner):
            return inner.contains(where: isLiveSupported)
        case .triggerEffect, .setEffectRate, .setEffectDepth,
             .firePreset, .firePalette, .fireLook, .runBehavior:
            // Not productized in the generalized executor — honest unsupported.
            return false
        }
    }

    @available(*, deprecated, renamed: "isLiveSupported")
    public static func isPhaseDLiveSupported(_ action: AuroraAction) -> Bool {
        isLiveSupported(action)
    }
}

// MARK: - Emissions / results

/// One action the pipeline decided to emit.
public struct AMEActionEmission: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var latencyID: UUID
    public var mappingID: UUID
    public var action: AuroraAction
    public var controlValue: Double
    public var quantizeBoundary: AMEQuantizationBoundary?
    public var quantizationFailurePolicy: AMEQuantizationFailurePolicy
    /// True when safety-critical or boundary is immediate/nil — must not wait for quantize.
    public var executeImmediately: Bool
    /// True only when armed **and** Phase D live-supported. Never silent no-op.
    public var shouldExecute: Bool
    /// False when action is not supported by the Phase D live executor.
    public var isLiveSupported: Bool
    /// True when this emission is a deactivation / release edge.
    public var isRelease: Bool
    public var ingressHostTime: HostTime

    public init(
        id: UUID = UUID(),
        latencyID: UUID,
        mappingID: UUID,
        action: AuroraAction,
        controlValue: Double,
        quantizeBoundary: AMEQuantizationBoundary? = nil,
        quantizationFailurePolicy: AMEQuantizationFailurePolicy = .cancel,
        executeImmediately: Bool,
        shouldExecute: Bool,
        isLiveSupported: Bool = true,
        isRelease: Bool = false,
        ingressHostTime: HostTime
    ) {
        self.id = id
        self.latencyID = latencyID
        self.mappingID = mappingID
        self.action = action
        self.controlValue = controlValue
        self.quantizeBoundary = quantizeBoundary
        self.quantizationFailurePolicy = quantizationFailurePolicy
        self.executeImmediately = executeImmediately
        self.shouldExecute = shouldExecute
        self.isLiveSupported = isLiveSupported
        self.isRelease = isRelease
        self.ingressHostTime = ingressHostTime
    }
}

public struct AMEEventResult: Equatable, Sendable {
    public var latencyID: UUID
    public var emissions: [AMEActionEmission]
    public var diagnostics: [AMEDiagnosticEvent]
    public var matchedMappingIDs: [UUID]
    public var matchedTriggerIDs: [UUID]

    public init(
        latencyID: UUID,
        emissions: [AMEActionEmission] = [],
        diagnostics: [AMEDiagnosticEvent] = [],
        matchedMappingIDs: [UUID] = [],
        matchedTriggerIDs: [UUID] = []
    ) {
        self.latencyID = latencyID
        self.emissions = emissions
        self.diagnostics = diagnostics
        self.matchedMappingIDs = matchedMappingIDs
        self.matchedTriggerIDs = matchedTriggerIDs
    }

    public static func empty(latencyID: UUID) -> AMEEventResult {
        AMEEventResult(latencyID: latencyID)
    }

    /// Emissions that the live path should actually dispatch.
    public var executableEmissions: [AMEActionEmission] {
        emissions.filter { $0.shouldExecute && $0.isLiveSupported }
    }
}
