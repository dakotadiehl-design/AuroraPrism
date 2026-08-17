import Foundation

// MARK: - Inheritance invariants (documented)
//
// 1. Effective scope order: section > song > project
// 2. overrideParentID / disablesParentID must reference existing mappings
// 3. No self override/disable; no cycles
// 4. Cannot both override and disable the same parent on one mapping
// 5. Ambiguous: two children override same parent at same scope+priority
// 6. Higher priority wins within same specificity
// 7. Disabled mappings still own legacy claims

// MARK: - Scopes (v1: Project → Song → Section)

public enum AMEMappingScope: Codable, Equatable, Sendable, Hashable {
    case project
    case song(UUID)
    case section(UUID)
}

public enum AMETimingRequirement: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case none
    case musicalTimeAvailable
    case transportRunning
    case externalSyncLocked
}

/// Trigger edge semantics for an AME mapping.
///
/// - `heldGate`: threshold-held activation (Note On/high acquires; Note Off/low releases with
///   `releaseActions`). **Not** a permission gate that enables other mappings — real cross-mapping
///   gating is reserved for a future behavior.
public enum AMETriggerBehavior: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case trigger
    case toggle
    case momentary
    case whileHeld
    case continuous
    /// Threshold-held activation (formerly encoded as `"gate"`).
    case heldGate

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        // Migration: Pass-1 `"gate"` → heldGate (held trigger, not permission gate).
        if raw == "gate" {
            self = .heldGate
            return
        }
        guard let value = AMETriggerBehavior(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unknown AMETriggerBehavior \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum AMESequenceMode: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case advance
    case reverse
    case pingPong
    case random
    case weightedRandom
    case shuffleBag
}

public enum AMESequenceResetPolicy: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case onSectionEntry
    case onSongStart
    case manual
    case never
}

public enum AMESequenceTriggerPolicy: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case fireThenAdvance
    case advanceThenFire
}

/// Where sequence runtime step state lives.
public enum AMESequenceStateScope: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case sequenceGlobal
    case perSong
    case perSection
}

public enum AMEQuantizationFailurePolicy: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case cancel
    case executeImmediately
    case holdUntilTimingAvailable
}

public enum AMEMIDIMessageType: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case noteOn
    case noteOff
    case cc
    case programChange
    case pitchBend
    case channelPressure
    case polyPressure
}

/// Model-side quantization boundary (mirrors Musical concepts without importing AuroraMusical).
public enum AMEQuantizationBoundary: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case immediate
    case nextSixteenth
    case nextEighth
    case nextQuarter
    case nextMetricalBeat
    case nextBar
}

public enum AMETimingPolicyStorage: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case internalOnly
    case externalMIDI
    case externalPreferredFallback
}

// MARK: - Triggers

public struct AMETriggerDefinition: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var friendlyName: String
    public var sourceBindingID: UUID?
    public var channel: UInt8?
    public var messageType: AMEMIDIMessageType
    public var data1Min: UInt8?
    public var data1Max: UInt8?
    public var data2Min: UInt8?
    public var data2Max: UInt8?
    public var drumRole: DrumRole?

    public init(
        id: UUID = UUID(),
        name: String = "",
        friendlyName: String = "",
        sourceBindingID: UUID? = nil,
        channel: UInt8? = nil,
        messageType: AMEMIDIMessageType = .noteOn,
        data1Min: UInt8? = nil,
        data1Max: UInt8? = nil,
        data2Min: UInt8? = nil,
        data2Max: UInt8? = nil,
        drumRole: DrumRole? = nil
    ) {
        self.id = id
        self.name = name
        self.friendlyName = friendlyName.isEmpty ? name : friendlyName
        self.sourceBindingID = sourceBindingID
        self.channel = channel
        self.messageType = messageType
        self.data1Min = data1Min
        self.data1Max = data1Max
        self.data2Min = data2Min
        self.data2Max = data2Max
        self.drumRole = drumRole
    }
}

public struct AMETriggerGroup: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var memberTriggerIDs: [UUID]

    public init(id: UUID = UUID(), name: String, memberTriggerIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.memberTriggerIDs = memberTriggerIDs
    }
}

// MARK: - Transforms / mappings

public struct AMEValueTransform: Codable, Equatable, Sendable, Hashable {
    public var inMin: Double
    public var inMax: Double
    public var outMin: Double
    public var outMax: Double
    public var invert: Bool
    public var deadZone: Double
    public var threshold: Double?

    public init(
        inMin: Double = 0,
        inMax: Double = 127,
        outMin: Double = 0,
        outMax: Double = 1,
        invert: Bool = false,
        deadZone: Double = 0,
        threshold: Double? = nil
    ) {
        self.inMin = inMin
        self.inMax = inMax
        self.outMin = outMin
        self.outMax = outMax
        self.invert = invert
        self.deadZone = deadZone
        self.threshold = threshold
    }

    public var isStructurallyValid: Bool {
        inMin.isFinite && inMax.isFinite && outMin.isFinite && outMax.isFinite
            && deadZone.isFinite && deadZone >= 0
            && inMax > inMin
            && (threshold == nil || (threshold!.isFinite))
    }
}

public struct AMEMapping: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var priority: Int
    public var scope: AMEMappingScope
    public var triggerID: UUID?
    public var triggerGroupID: UUID?
    public var timingRequirement: AMETimingRequirement
    public var behavior: AMETriggerBehavior
    public var transform: AMEValueTransform?
    /// Activation / on-edge actions.
    public var actions: [AuroraAction]
    /// Deactivation / off-edge / release actions (momentary, whileHeld, heldGate, toggle-off).
    public var releaseActions: [AuroraAction]
    public var sequenceID: UUID?
    public var quantizeBoundary: AMEQuantizationBoundary?
    public var quantizationFailurePolicy: AMEQuantizationFailurePolicy
    public var debounceMilliseconds: Double
    public var burstSuppressionMilliseconds: Double?
    public var overrideParentID: UUID?
    public var disablesParentID: UUID?
    public var claimsLegacyMappingID: UUID?
    public var claimsLegacyRuleID: UUID?

    public init(
        id: UUID = UUID(),
        name: String = "",
        enabled: Bool = true,
        priority: Int = 0,
        scope: AMEMappingScope = .project,
        triggerID: UUID? = nil,
        triggerGroupID: UUID? = nil,
        timingRequirement: AMETimingRequirement = .none,
        behavior: AMETriggerBehavior = .trigger,
        transform: AMEValueTransform? = nil,
        actions: [AuroraAction] = [],
        releaseActions: [AuroraAction] = [],
        sequenceID: UUID? = nil,
        quantizeBoundary: AMEQuantizationBoundary? = nil,
        quantizationFailurePolicy: AMEQuantizationFailurePolicy = .cancel,
        debounceMilliseconds: Double = 0,
        burstSuppressionMilliseconds: Double? = nil,
        overrideParentID: UUID? = nil,
        disablesParentID: UUID? = nil,
        claimsLegacyMappingID: UUID? = nil,
        claimsLegacyRuleID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.scope = scope
        self.triggerID = triggerID
        self.triggerGroupID = triggerGroupID
        self.timingRequirement = timingRequirement
        self.behavior = behavior
        self.transform = transform
        self.actions = actions
        self.releaseActions = releaseActions
        self.sequenceID = sequenceID
        self.quantizeBoundary = quantizeBoundary
        self.quantizationFailurePolicy = quantizationFailurePolicy
        self.debounceMilliseconds = debounceMilliseconds
        self.burstSuppressionMilliseconds = burstSuppressionMilliseconds
        self.overrideParentID = overrideParentID
        self.disablesParentID = disablesParentID
        self.claimsLegacyMappingID = claimsLegacyMappingID
        self.claimsLegacyRuleID = claimsLegacyRuleID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, priority, scope, triggerID, triggerGroupID
        case timingRequirement, behavior, transform, actions, releaseActions
        case sequenceID, quantizeBoundary, quantizationFailurePolicy
        case debounceMilliseconds, burstSuppressionMilliseconds
        case overrideParentID, disablesParentID
        case claimsLegacyMappingID, claimsLegacyRuleID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        scope = try c.decodeIfPresent(AMEMappingScope.self, forKey: .scope) ?? .project
        triggerID = try c.decodeIfPresent(UUID.self, forKey: .triggerID)
        triggerGroupID = try c.decodeIfPresent(UUID.self, forKey: .triggerGroupID)
        timingRequirement = try c.decodeIfPresent(AMETimingRequirement.self, forKey: .timingRequirement) ?? .none
        behavior = try c.decodeIfPresent(AMETriggerBehavior.self, forKey: .behavior) ?? .trigger
        transform = try c.decodeIfPresent(AMEValueTransform.self, forKey: .transform)
        actions = try c.decodeIfPresent([AuroraAction].self, forKey: .actions) ?? []
        releaseActions = try c.decodeIfPresent([AuroraAction].self, forKey: .releaseActions) ?? []
        sequenceID = try c.decodeIfPresent(UUID.self, forKey: .sequenceID)
        quantizeBoundary = try c.decodeIfPresent(AMEQuantizationBoundary.self, forKey: .quantizeBoundary)
        quantizationFailurePolicy = try c.decodeIfPresent(AMEQuantizationFailurePolicy.self, forKey: .quantizationFailurePolicy) ?? .cancel
        debounceMilliseconds = try c.decodeIfPresent(Double.self, forKey: .debounceMilliseconds) ?? 0
        burstSuppressionMilliseconds = try c.decodeIfPresent(Double.self, forKey: .burstSuppressionMilliseconds)
        overrideParentID = try c.decodeIfPresent(UUID.self, forKey: .overrideParentID)
        disablesParentID = try c.decodeIfPresent(UUID.self, forKey: .disablesParentID)
        claimsLegacyMappingID = try c.decodeIfPresent(UUID.self, forKey: .claimsLegacyMappingID)
        claimsLegacyRuleID = try c.decodeIfPresent(UUID.self, forKey: .claimsLegacyRuleID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(priority, forKey: .priority)
        try c.encode(scope, forKey: .scope)
        try c.encodeIfPresent(triggerID, forKey: .triggerID)
        try c.encodeIfPresent(triggerGroupID, forKey: .triggerGroupID)
        try c.encode(timingRequirement, forKey: .timingRequirement)
        try c.encode(behavior, forKey: .behavior)
        try c.encodeIfPresent(transform, forKey: .transform)
        try c.encode(actions, forKey: .actions)
        try c.encode(releaseActions, forKey: .releaseActions)
        try c.encodeIfPresent(sequenceID, forKey: .sequenceID)
        try c.encodeIfPresent(quantizeBoundary, forKey: .quantizeBoundary)
        try c.encode(quantizationFailurePolicy, forKey: .quantizationFailurePolicy)
        try c.encode(debounceMilliseconds, forKey: .debounceMilliseconds)
        try c.encodeIfPresent(burstSuppressionMilliseconds, forKey: .burstSuppressionMilliseconds)
        try c.encodeIfPresent(overrideParentID, forKey: .overrideParentID)
        try c.encodeIfPresent(disablesParentID, forKey: .disablesParentID)
        try c.encodeIfPresent(claimsLegacyMappingID, forKey: .claimsLegacyMappingID)
        try c.encodeIfPresent(claimsLegacyRuleID, forKey: .claimsLegacyRuleID)
    }
}

public struct AMEMappingSet: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var mappingIDs: [UUID]

    public init(id: UUID = UUID(), name: String, mappingIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.mappingIDs = mappingIDs
    }
}

// MARK: - Sequences

public struct AMESequenceStep: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var actions: [AuroraAction]
    public var weight: Double

    public init(
        id: UUID = UUID(),
        name: String = "",
        actions: [AuroraAction] = [],
        weight: Double = 1
    ) {
        self.id = id
        self.name = name
        self.actions = actions
        self.weight = weight
    }
}

public struct AMETriggeredSequence: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var steps: [AMESequenceStep]
    public var mode: AMESequenceMode
    public var loop: Bool
    /// Sole source of truth for when runtime step resets.
    public var resetPolicy: AMESequenceResetPolicy
    public var triggerPolicy: AMESequenceTriggerPolicy
    public var initialIndex: Int
    public var stateScope: AMESequenceStateScope

    public init(
        id: UUID = UUID(),
        name: String = "",
        steps: [AMESequenceStep] = [],
        mode: AMESequenceMode = .advance,
        loop: Bool = true,
        resetPolicy: AMESequenceResetPolicy = .onSectionEntry,
        triggerPolicy: AMESequenceTriggerPolicy = .fireThenAdvance,
        initialIndex: Int = 0,
        stateScope: AMESequenceStateScope = .perSection
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.mode = mode
        self.loop = loop
        self.resetPolicy = resetPolicy
        self.triggerPolicy = triggerPolicy
        self.initialIndex = max(0, initialIndex)
        self.stateScope = stateScope
    }
}

// MARK: - Source bindings

public struct MIDISourceBinding: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var displayName: String
    public var lastCoreMIDIUniqueID: Int32?
    public var manufacturerHint: String?
    public var modelHint: String?
    public var endpointNameHint: String?
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        lastCoreMIDIUniqueID: Int32? = nil,
        manufacturerHint: String? = nil,
        modelHint: String? = nil,
        endpointNameHint: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.lastCoreMIDIUniqueID = lastCoreMIDIUniqueID
        self.manufacturerHint = manufacturerHint
        self.modelHint = modelHint
        self.endpointNameHint = endpointNameHint
        self.enabled = enabled
    }
}

public struct MusicalEngineProjectSettings: Codable, Equatable, Sendable, Hashable {
    public var timingPolicy: AMETimingPolicyStorage
    public var selectedExternalSourceBindingID: UUID?
    public var defaultTempoBPM: Double
    public var defaultMeter: ShowMusicalMeter
    public var freewheelSeconds: Double

    public init(
        timingPolicy: AMETimingPolicyStorage = .internalOnly,
        selectedExternalSourceBindingID: UUID? = nil,
        defaultTempoBPM: Double = 120,
        defaultMeter: ShowMusicalMeter = .fourFour,
        freewheelSeconds: Double = 2.0
    ) {
        self.timingPolicy = timingPolicy
        self.selectedExternalSourceBindingID = selectedExternalSourceBindingID
        self.defaultTempoBPM = defaultTempoBPM
        self.defaultMeter = defaultMeter
        self.freewheelSeconds = freewheelSeconds
    }

    public static let `default` = MusicalEngineProjectSettings()

    private enum CodingKeys: String, CodingKey {
        case timingPolicy, selectedExternalSourceBindingID, defaultTempoBPM, defaultMeter, freewheelSeconds
        case defaultMeterNumerator, defaultMeterDenominator
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timingPolicy = try c.decodeIfPresent(AMETimingPolicyStorage.self, forKey: .timingPolicy) ?? .internalOnly
        selectedExternalSourceBindingID = try c.decodeIfPresent(UUID.self, forKey: .selectedExternalSourceBindingID)
        defaultTempoBPM = try c.decodeIfPresent(Double.self, forKey: .defaultTempoBPM) ?? 120
        freewheelSeconds = try c.decodeIfPresent(Double.self, forKey: .freewheelSeconds) ?? 2.0
        if let meter = try c.decodeIfPresent(ShowMusicalMeter.self, forKey: .defaultMeter) {
            defaultMeter = meter
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .defaultMeterNumerator),
                  let d = try c.decodeIfPresent(Int.self, forKey: .defaultMeterDenominator),
                  let migrated = ShowMusicalMeter.migrating(numerator: n, denominator: d) {
            defaultMeter = migrated
        } else {
            defaultMeter = .fourFour
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timingPolicy, forKey: .timingPolicy)
        try c.encodeIfPresent(selectedExternalSourceBindingID, forKey: .selectedExternalSourceBindingID)
        try c.encode(defaultTempoBPM, forKey: .defaultTempoBPM)
        try c.encode(defaultMeter, forKey: .defaultMeter)
        try c.encode(freewheelSeconds, forKey: .freewheelSeconds)
    }
}

public struct AMEProjectDocument: Codable, Equatable, Sendable {
    public var triggers: [AMETriggerDefinition]
    public var triggerGroups: [AMETriggerGroup]
    public var mappings: [AMEMapping]
    public var mappingSets: [AMEMappingSet]
    public var sequences: [AMETriggeredSequence]
    public var sourceBindings: [MIDISourceBinding]
    public var musicalSettings: MusicalEngineProjectSettings

    public init(
        triggers: [AMETriggerDefinition] = [],
        triggerGroups: [AMETriggerGroup] = [],
        mappings: [AMEMapping] = [],
        mappingSets: [AMEMappingSet] = [],
        sequences: [AMETriggeredSequence] = [],
        sourceBindings: [MIDISourceBinding] = [],
        musicalSettings: MusicalEngineProjectSettings = .default
    ) {
        self.triggers = triggers
        self.triggerGroups = triggerGroups
        self.mappings = mappings
        self.mappingSets = mappingSets
        self.sequences = sequences
        self.sourceBindings = sourceBindings
        self.musicalSettings = musicalSettings
    }

    public static let empty = AMEProjectDocument()
}

public enum AMELegacyOwnership {
    public static func claimedLegacyMappingIDs(in document: AMEProjectDocument) -> Set<UUID> {
        Set(document.mappings.compactMap(\.claimsLegacyMappingID))
    }

    public static func claimedLegacyRuleIDs(in document: AMEProjectDocument) -> Set<UUID> {
        Set(document.mappings.compactMap(\.claimsLegacyRuleID))
    }

    public static func shouldRunLegacyMapping(id: UUID, document: AMEProjectDocument) -> Bool {
        !claimedLegacyMappingIDs(in: document).contains(id)
    }

    public static func shouldRunLegacyRule(id: UUID, document: AMEProjectDocument) -> Bool {
        !claimedLegacyRuleIDs(in: document).contains(id)
    }
}
