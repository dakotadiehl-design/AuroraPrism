import AuroraModel
import AuroraMusical
import Foundation

/// Deterministic identity for a held MIDI control (note / whileHeld / momentary / heldGate).
public struct AMEHeldIdentity: Hashable, Equatable, Sendable {
    public var mappingID: UUID
    public var sourceID: String
    public var channel: UInt8
    /// Note number or CC number (data1); nil for channel-wide pressure.
    public var data1: UInt8?

    public init(mappingID: UUID, sourceID: String, channel: UInt8, data1: UInt8?) {
        self.mappingID = mappingID
        self.sourceID = sourceID
        self.channel = channel
        self.data1 = data1
    }

    public static func from(mappingID: UUID, event: AMENormalizedEvent) -> AMEHeldIdentity {
        AMEHeldIdentity(
            mappingID: mappingID,
            sourceID: event.sourceID,
            channel: event.channel,
            data1: event.data1
        )
    }

    /// Physical key match without mapping ID (release edges match by source/channel/data1).
    public func matchesPhysicalKey(of event: AMENormalizedEvent) -> Bool {
        sourceID == event.sourceID
            && channel == event.channel
            && data1 == event.data1
    }
}

public struct AMEHeldEntry: Equatable, Sendable {
    public var identity: AMEHeldIdentity
    public var acquiredHostTime: HostTime
    public var controlValue: Double
    /// Snapshotted at acquisition so document edits cannot block unwind.
    public var releaseActions: [AuroraAction]
    public var mappingScope: AMEMappingScope
    public var activationLatencyID: UUID?
    /// True when activation was acquired in armed mode (live output may need unwind).
    public var wasLiveExecuted: Bool

    public init(
        identity: AMEHeldIdentity,
        acquiredHostTime: HostTime,
        controlValue: Double,
        releaseActions: [AuroraAction] = [],
        mappingScope: AMEMappingScope = .project,
        activationLatencyID: UUID? = nil,
        wasLiveExecuted: Bool = false
    ) {
        self.identity = identity
        self.acquiredHostTime = acquiredHostTime
        self.controlValue = controlValue
        self.releaseActions = releaseActions
        self.mappingScope = mappingScope
        self.activationLatencyID = activationLatencyID
        self.wasLiveExecuted = wasLiveExecuted
    }
}

/// Result of releasing one or more held identities (includes outward deactivation emissions).
public struct AMEHeldReleaseBatch: Equatable, Sendable {
    public var releasedEntries: [AMEHeldEntry]
    public var emissions: [AMEActionEmission]
    public var diagnostics: [AMEDiagnosticEvent]

    public init(
        releasedEntries: [AMEHeldEntry] = [],
        emissions: [AMEActionEmission] = [],
        diagnostics: [AMEDiagnosticEvent] = []
    ) {
        self.releasedEntries = releasedEntries
        self.emissions = emissions
        self.diagnostics = diagnostics
    }

    public static let empty = AMEHeldReleaseBatch()
}

/// Ephemeral held-note / gate table. Not persisted.
public final class AMEHeldStateTable: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [AMEHeldIdentity: AMEHeldEntry] = [:]

    public init() {}

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    public func snapshot() -> [AMEHeldEntry] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.values)
    }

    public func isHeld(_ identity: AMEHeldIdentity) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return entries[identity] != nil
    }

    @discardableResult
    public func acquire(_ entry: AMEHeldEntry) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if entries[entry.identity] != nil { return false }
        entries[entry.identity] = entry
        return true
    }

    @discardableResult
    public func release(_ identity: AMEHeldIdentity) -> AMEHeldEntry? {
        lock.lock(); defer { lock.unlock() }
        let entry = entries[identity]
        entries[identity] = nil
        return entry
    }

    @discardableResult
    public func releaseAll() -> [AMEHeldEntry] {
        lock.lock(); defer { lock.unlock() }
        let all = Array(entries.values)
        entries.removeAll(keepingCapacity: true)
        return all
    }

    @discardableResult
    public func releaseInvalid(validEnabledMappingIDs: Set<UUID>) -> [AMEHeldEntry] {
        lock.lock(); defer { lock.unlock() }
        var released: [AMEHeldEntry] = []
        for (id, entry) in entries {
            if !validEnabledMappingIDs.contains(id.mappingID) {
                released.append(entry)
                entries[id] = nil
            }
        }
        return released
    }

    @discardableResult
    public func releaseInactiveScopes(context: AMEShowContext) -> [AMEHeldEntry] {
        lock.lock(); defer { lock.unlock() }
        var released: [AMEHeldEntry] = []
        for (id, entry) in entries {
            if !AMEMatchEngine.scopeIsActive(entry.mappingScope, context: context) {
                released.append(entry)
                entries[id] = nil
            }
        }
        return released
    }

    /// Toggle ON/OFF table with source provenance for disconnect unwind.
    public final class ToggleTable: @unchecked Sendable {
        private let lock = NSLock()

        public struct OnRecord: Equatable, Sendable {
            public var sourceID: String
            public var channel: UInt8
            public var data1: UInt8?
            public var releaseActions: [AuroraAction]
            public var wasLiveExecuted: Bool
            public var activationLatencyID: UUID?

            public init(
                sourceID: String,
                channel: UInt8,
                data1: UInt8?,
                releaseActions: [AuroraAction],
                wasLiveExecuted: Bool,
                activationLatencyID: UUID? = nil
            ) {
                self.sourceID = sourceID
                self.channel = channel
                self.data1 = data1
                self.releaseActions = releaseActions
                self.wasLiveExecuted = wasLiveExecuted
                self.activationLatencyID = activationLatencyID
            }
        }

        private var onState: [UUID: OnRecord] = [:]

        public init() {}

        public func isOn(mappingID: UUID) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return onState[mappingID] != nil
        }

        public enum Flip: Equatable, Sendable {
            case activated
            case deactivated(record: OnRecord)
        }

        public func flip(
            mappingID: UUID,
            sourceID: String,
            channel: UInt8,
            data1: UInt8?,
            releaseActions: [AuroraAction],
            wasLiveExecuted: Bool,
            activationLatencyID: UUID? = nil
        ) -> Flip {
            lock.lock(); defer { lock.unlock() }
            if let existing = onState[mappingID] {
                onState[mappingID] = nil
                return .deactivated(record: existing)
            } else {
                onState[mappingID] = OnRecord(
                    sourceID: sourceID,
                    channel: channel,
                    data1: data1,
                    releaseActions: releaseActions,
                    wasLiveExecuted: wasLiveExecuted,
                    activationLatencyID: activationLatencyID
                )
                return .activated
            }
        }

        /// Release all toggles activated by a given source.
        public func release(forSourceID sourceID: String) -> [(UUID, OnRecord)] {
            lock.lock(); defer { lock.unlock() }
            var out: [(UUID, OnRecord)] = []
            for (mid, rec) in onState where rec.sourceID == sourceID {
                out.append((mid, rec))
                onState[mid] = nil
            }
            return out
        }

        public func clear() -> [(UUID, OnRecord)] {
            lock.lock(); defer { lock.unlock() }
            let all = onState.map { ($0.key, $0.value) }
            onState.removeAll()
            return all
        }
    }
}
