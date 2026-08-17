import AuroraModel
import AuroraMusical
import Foundation

// MARK: - Value transform

public enum AMEValueTransformEvaluator {
    /// Apply optional transform.
    ///
    /// - `rawNormalized` is MIDI 0…1 (e.g. velocity/CC / 127).
    /// - `inMin`/`inMax` are in **MIDI input units** (default 0…127).
    /// - Values outside `[inMin, inMax]` are **clamped** to 0/1 before invert/out scale.
    /// - `deadZone` and `threshold` are in the same input units.
    /// - Returns nil when `threshold` rejects (input units below threshold).
    public static func apply(_ transform: AMEValueTransform?, rawNormalized: Double) -> Double? {
        let raw = min(1, max(0, rawNormalized))
        guard let t = transform else { return raw }
        guard t.isStructurallyValid else { return raw }

        let inSpan = t.inMax - t.inMin
        guard inSpan > 0 else { return nil }

        // Canonical MIDI domain from normalized channel value.
        let midiValue = raw * 127.0

        // Dead zone around midpoint of configured input window (input units).
        if t.deadZone > 0 {
            let mid = (t.inMin + t.inMax) / 2
            if abs(midiValue - mid) < t.deadZone {
                return (t.outMin + t.outMax) / 2
            }
        }

        if let thr = t.threshold, midiValue < thr {
            return nil
        }

        var unit = (midiValue - t.inMin) / inSpan
        unit = min(1, max(0, unit)) // clamp outside inMin…inMax
        if t.invert { unit = 1 - unit }
        return t.outMin + unit * (t.outMax - t.outMin)
    }
}

// MARK: - Trigger / scope matching (pure)

public enum AMEMatchEngine {
    public static func triggerMatches(
        _ trigger: AMETriggerDefinition,
        event: AMENormalizedEvent,
        bindings: [UUID: MIDISourceBinding],
        allowNoteOffForNoteOnTrigger: Bool = false,
        resolvedSourceIDsByBinding: [UUID: Set<String>] = [:]
    ) -> Bool {
        let typeOK: Bool
        if trigger.messageType == event.messageType {
            typeOK = true
        } else if allowNoteOffForNoteOnTrigger,
                  trigger.messageType == .noteOn,
                  event.messageType == .noteOff {
            typeOK = true
        } else {
            typeOK = false
        }
        guard typeOK else { return false }
        if let ch = trigger.channel, ch != event.channel { return false }

        if let d1 = event.data1 {
            if let lo = trigger.data1Min, d1 < lo { return false }
            if let hi = trigger.data1Max, d1 > hi { return false }
        } else if trigger.data1Min != nil || trigger.data1Max != nil {
            return false
        }

        let isReleaseMatch = allowNoteOffForNoteOnTrigger
            && trigger.messageType == .noteOn
            && event.messageType == .noteOff
        if !isReleaseMatch {
            if let d2 = event.data2 {
                if let lo = trigger.data2Min, d2 < lo { return false }
                if let hi = trigger.data2Max, d2 > hi { return false }
            } else if trigger.data2Min != nil || trigger.data2Max != nil {
                switch event.messageType {
                case .programChange, .pitchBend:
                    break
                default:
                    return false
                }
            }
        }

        if let bid = trigger.sourceBindingID {
            guard let binding = bindings[bid], binding.enabled else { return false }
            // Host inventory resolution table:
            // - key present with IDs → match only those canonical IDs
            // - key present empty → fail closed (ambiguous)
            // - key absent → identity/hint fallback (UID match, Learn ep: hints)
            if let resolved = resolvedSourceIDsByBinding[bid] {
                return resolved.contains(event.sourceID)
            }
            return sourceMatchesBinding(event.sourceID, binding: binding)
        }
        return true
    }

    /// Prefer stable unique IDs when available; name/hint matching is secondary.
    public static func sourceMatchesBinding(_ sourceID: String, binding: MIDISourceBinding) -> Bool {
        MIDISourceIdentity.matches(sourceID: sourceID, binding: binding)
    }

    public static func scopeIsActive(_ scope: AMEMappingScope, context: AMEShowContext) -> Bool {
        switch scope {
        case .project:
            return true
        case .song(let id):
            return context.activeSongID == id
        case .section(let id):
            return context.activeSectionID == id
        }
    }

    public static func scopeSpecificity(_ scope: AMEMappingScope) -> Int {
        switch scope {
        case .project: return 0
        case .song: return 1
        case .section: return 2
        }
    }

    /// Behaviors that acquire held identities and release on physical release edge.
    public static let heldBehaviors: Set<AMETriggerBehavior> = [.momentary, .whileHeld, .heldGate]
}

// MARK: - Safe indexing

private enum AMESafeIndex {
    static func firstWins<T>(_ items: [T], id: (T) -> UUID) -> (map: [UUID: T], duplicateCount: Int) {
        var map: [UUID: T] = [:]
        var dups = 0
        for item in items {
            let key = id(item)
            if map[key] == nil {
                map[key] = item
            } else {
                dups += 1
            }
        }
        return (map, dups)
    }
}

// MARK: - Runtime

/// Headless AME evaluation pipeline (Phase D closeout).
///
/// **Serialization:** all ephemeral evaluation state (held, toggle, debounce/burst, diagnostics)
/// is mutated under a single runtime lock for the duration of `process` / release APIs.
/// Callers receive results and execute actions **outside** this lock.
///
/// **Release rule:** once a held identity is acquired, the physical release edge (or forced
/// release-all / document / context / mode transition) always unwinds it — never blocked by
/// scope, timing, enabled, debounce, burst, or transform gates.
public final class AMERuntime: @unchecked Sendable {
    private let lock = NSLock()

    private var mode: AMEPerformanceMode = .armed
    private var document: AMEProjectDocument = .empty
    private var showContext: AMEShowContext = .empty
    private var timing: AMETimingSnapshot = .internalAvailable
    /// Active section membership from host (mapping sets + localMappingIDs).
    private var activeSectionLocalMappingIDs: [UUID] = []
    private var activeSectionMappingSetIDs: [UUID] = []
    /// Inventory-resolved canonical source IDs per binding (`uid:` / `ep:`), refreshed by host.
    private var resolvedSourceIDsByBinding: [UUID: Set<String>] = [:]

    /// Live (armed) ephemeral state — never shared with dry-run simulation.
    private let liveDomain: EphemeralDomain
    /// Dry-run / simulation ephemeral state.
    private let simDomain: EphemeralDomain

    private var diagnosticRing: [AMEDiagnosticEvent] = []
    private let diagnosticCapacity: Int
    private let sequenceBaseSeed: UInt64

    /// Per-mode ephemeral tables (held, toggle, sequence, rate-limit).
    private final class EphemeralDomain {
        let held = AMEHeldStateTable()
        let toggles = AMEHeldStateTable.ToggleTable()
        let sequences: AMESequenceStateTable
        var lastFireSeconds: [UUID: TimeInterval] = [:]
        var lastBurstSeconds: [UUID: TimeInterval] = [:]

        init(seed: UInt64) {
            sequences = AMESequenceStateTable(seed: seed)
        }

        func clearAllEphemeral() {
            _ = held.releaseAll()
            _ = toggles.clear()
            sequences.clear()
            lastFireSeconds.removeAll()
            lastBurstSeconds.removeAll()
        }
    }

    public init(diagnosticCapacity: Int = 256, sequenceSeed: UInt64 = 0xA11A_5EED) {
        self.diagnosticCapacity = max(16, diagnosticCapacity)
        self.sequenceBaseSeed = sequenceSeed
        self.liveDomain = EphemeralDomain(seed: sequenceSeed)
        self.simDomain = EphemeralDomain(seed: sequenceSeed &+ 0xD00D_F00D)
    }

    /// Replace RNG base seed for deterministic random/shuffle modes (both domains).
    public func setSequenceRNGSeed(_ seed: UInt64) {
        lock.lock()
        liveDomain.sequences.setBaseSeed(seed)
        simDomain.sequences.setBaseSeed(seed &+ 0xD00D_F00D)
        lock.unlock()
    }

    private func domain(for perfMode: AMEPerformanceMode) -> EphemeralDomain {
        switch perfMode {
        case .armed: return liveDomain
        case .dryRun, .edit: return simDomain
        }
    }

    // MARK: Configuration

    /// Current performance mode. **Read-only** — use `setPerformanceMode` so release batches cannot be discarded.
    public var performanceMode: AMEPerformanceMode {
        lock.lock(); defer { lock.unlock() }
        return mode
    }

    /// Change performance mode.
    /// - Leaving `armed` → dryRun/edit: releases **live** holds/toggles with **executable** deactivation.
    /// - Entering `armed` from dryRun/edit: purges simulation state without executing releases.
    @discardableResult
    public func setPerformanceMode(_ newMode: AMEPerformanceMode) -> AMEHeldReleaseBatch {
        lock.lock()
        let old = mode
        mode = newMode
        lock.unlock()

        if old == .armed && newMode != .armed {
            // Unwind live output that was actually armed.
            return releaseDomain(liveDomain, reason: .modeChange, forceExecute: true)
        }
        if old != .armed && newMode == .armed {
            // Simulation must not poison live state.
            lock.lock()
            simDomain.clearAllEphemeral()
            appendDiagnosticsUnlocked([
                AMEDiagnosticEvent(
                    kind: .simulationDomainPurged,
                    message: "Dry-run/edit simulation state purged on arm"
                ),
            ])
            lock.unlock()
        }
        return .empty
    }

    /// Replace AME document. Releases holds with provenance-aware execution; clears both domains.
    ///
    /// Callers should **diff first** and only invoke this when AME content actually changed
    /// (or on intentional full reload). The host (`ControlActionRouter.updateMappings`) does that
    /// so unrelated project edits do not wipe live held/toggle/sequence state.
    @discardableResult
    public func updateDocument(_ document: AMEProjectDocument) -> AMEHeldReleaseBatch {
        // Live holds: execute releases only when they were live-executed (provenance).
        var batch = releaseDomain(liveDomain, reason: .documentChange, forceExecute: nil)
        // Simulation holds: diagnostic-only releases.
        let simBatch = releaseDomain(simDomain, reason: .documentChange, forceExecute: false)
        batch.releasedEntries.append(contentsOf: simBatch.releasedEntries)
        batch.emissions.append(contentsOf: simBatch.emissions)
        batch.diagnostics.append(contentsOf: simBatch.diagnostics)

        lock.lock()
        self.document = document
        liveDomain.clearAllEphemeral()
        simDomain.clearAllEphemeral()
        lock.unlock()
        return batch
    }

    /// Host refreshes resolved binding → canonical live source IDs from MIDI inventory.
    public func setResolvedSourceBindings(_ map: [UUID: Set<String>]) {
        lock.lock()
        resolvedSourceIDsByBinding = map
        lock.unlock()
    }

    /// Advance sequence cursor without firing step actions (lifecycle / control actions).
    @discardableResult
    public func advanceSequence(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let seq = document.sequences.first(where: { $0.id == id }) else { return false }
        let dom = domain(for: mode)
        switch dom.sequences.advanceOnly(sequence: seq, context: showContext) {
        case .success(let cursor):
            appendDiagnosticsUnlocked([
                AMEDiagnosticEvent(
                    kind: .sequenceControlAction,
                    sequenceID: id,
                    stepIndex: cursor,
                    message: "advanceSequence → cursor \(cursor)"
                ),
            ])
            return true
        case .failure:
            return false
        }
    }

    /// Fire step actions without advancing cursor. Returns actions to execute, or nil if invalid.
    public func fireSequenceStepActions(sequenceID: UUID, stepIndex: Int) -> [AuroraAction]? {
        lock.lock()
        defer { lock.unlock() }
        guard let seq = document.sequences.first(where: { $0.id == sequenceID }),
              !seq.steps.isEmpty,
              stepIndex >= 0,
              stepIndex < seq.steps.count
        else { return nil }
        appendDiagnosticsUnlocked([
            AMEDiagnosticEvent(
                kind: .sequenceStepFired,
                sequenceID: sequenceID,
                stepIndex: stepIndex,
                message: "fireSequenceStep \(stepIndex) (executor path)"
            ),
        ])
        return seq.steps[stepIndex].actions
    }

    /// Host provides section membership for mapping-set activation (Wave 4).
    public func updateSectionMembership(localMappingIDs: [UUID], mappingSetIDs: [UUID]) {
        lock.lock()
        activeSectionLocalMappingIDs = localMappingIDs
        activeSectionMappingSetIDs = mappingSetIDs
        lock.unlock()
    }

    /// Update song/section context. Entry-only resets; release inactive-scope holds.
    @discardableResult
    public func updateShowContext(_ context: AMEShowContext) -> AMEHeldReleaseBatch {
        lock.lock()
        let previous = showContext
        showContext = context
        let doc = document
        let perfMode = mode
        var resetDiagnostics: [AMEDiagnosticEvent] = []

        var seqByID: [UUID: AMETriggeredSequence] = [:]
        for s in doc.sequences where seqByID[s.id] == nil {
            seqByID[s.id] = s
        }

        // Entry/start only — exit-to-nil does not reset.
        let enteredSong: UUID? = {
            guard let song = context.activeSongID, previous.activeSongID != song else { return nil }
            return song
        }()
        let enteredSection: UUID? = {
            guard let section = context.activeSectionID, previous.activeSectionID != section else { return nil }
            return section
        }()

        let domains = [liveDomain, simDomain]
        if let songID = enteredSong {
            for seq in doc.sequences where seq.resetPolicy == .onSongStart {
                for dom in domains {
                    dom.sequences.resetDomain(
                        sequence: seq,
                        event: .songStart(songID),
                        context: context
                    )
                }
                resetDiagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .sequenceReset,
                        sequenceID: seq.id,
                        message: "Sequence “\(seq.name)” reset (onSongStart song=\(songID.uuidString.prefix(8)))"
                    )
                )
            }
        }
        if let sectionID = enteredSection {
            for seq in doc.sequences where seq.resetPolicy == .onSectionEntry {
                for dom in domains {
                    dom.sequences.resetDomain(
                        sequence: seq,
                        event: .sectionEntry(sectionID: sectionID, songID: context.activeSongID),
                        context: context
                    )
                }
                resetDiagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .sequenceReset,
                        sequenceID: seq.id,
                        message: "Sequence “\(seq.name)” reset (onSectionEntry)"
                    )
                )
            }
        }
        for dom in domains {
            dom.sequences.pruneRemovedSequences(validSequenceIDs: Set(seqByID.keys))
        }
        appendDiagnosticsUnlocked(resetDiagnostics)
        let activeDomain = domain(for: perfMode)
        lock.unlock()

        // Hold scope release: use wasLiveExecuted provenance per entry.
        let released = activeDomain.held.releaseInactiveScopes(context: context)
        return buildReleaseBatch(
            entries: released,
            reason: .contextChange,
            forceExecute: nil,
            hostTime: .now(),
            latencyID: UUID()
        )
    }

    /// Manual sequence reset for the active domain.
    /// Manual sequence reset. Returns `false` when the sequence is missing or cannot reset in context.
    @discardableResult
    public func resetSequence(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let seq = document.sequences.first(where: { $0.id == id }) else { return false }
        let dom = domain(for: mode)
        guard AMESequenceStateKey.canCreate(sequence: seq, context: showContext) else { return false }
        dom.sequences.reset(sequence: seq, context: showContext)
        appendDiagnosticsUnlocked([
            AMEDiagnosticEvent(
                kind: .sequenceReset,
                sequenceID: id,
                message: "Sequence “\(seq.name)” reset (manual)"
            ),
        ])
        return true
    }

    /// Public sequence cursor snapshot for the active performance domain (diagnostics/tests).
    public struct SequenceCursorSnapshot: Equatable, Sendable {
        public var cursor: Int
        public var direction: Int
        public var shuffleBagRemaining: Int
        public var nextDeterministicFireIndex: Int?
    }

    public func sequenceState(
        sequenceID: UUID,
        context: AMEShowContext? = nil
    ) -> SequenceCursorSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let seq = document.sequences.first(where: { $0.id == sequenceID }) else { return nil }
        let ctx = context ?? showContext
        guard AMESequenceStateKey.canCreate(sequence: seq, context: ctx) else { return nil }
        let key = AMESequenceStateKey.make(sequence: seq, context: ctx)
        let dom = domain(for: mode)
        guard let state = dom.sequences.state(for: key) else { return nil }
        return SequenceCursorSnapshot(
            cursor: state.cursor,
            direction: state.direction,
            shuffleBagRemaining: state.shuffleBag.count,
            nextDeterministicFireIndex: dom.sequences.nextDeterministicFireIndex(
                sequence: seq,
                context: ctx
            )
        )
    }

    public func updateTiming(_ timing: AMETimingSnapshot) {
        lock.lock()
        self.timing = timing
        lock.unlock()
    }

    public func heldSnapshot() -> [AMEHeldEntry] {
        lock.lock(); defer { lock.unlock() }
        return domain(for: mode).held.snapshot()
    }

    /// Live-domain held snapshot (armed holds only).
    public func liveHeldSnapshot() -> [AMEHeldEntry] {
        liveDomain.held.snapshot()
    }

    public func recentDiagnostics(limit: Int = 50) -> [AMEDiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        let n = min(max(0, limit), diagnosticRing.count)
        return Array(diagnosticRing.suffix(n))
    }

    public enum ReleaseReason: Equatable, Sendable {
        case releaseAll
        case documentChange
        case contextChange
        case modeChange
        case physicalEdge
        case sourceDisconnect
    }

    /// Release held/toggle state owned by one MIDI source (device unplug).
    @discardableResult
    public func releaseHeld(forSourceID sourceID: String) -> AMEHeldReleaseBatch {
        lock.lock()
        let perfMode = mode
        lock.unlock()
        // Always unwind live domain for disconnect (dry-run uses sim domain separately).
        var batch = releaseHeldInDomain(liveDomain, sourceID: sourceID, forceExecute: nil)
        let simBatch = releaseHeldInDomain(simDomain, sourceID: sourceID, forceExecute: false)
        batch.releasedEntries.append(contentsOf: simBatch.releasedEntries)
        batch.emissions.append(contentsOf: simBatch.emissions)
        batch.diagnostics.append(contentsOf: simBatch.diagnostics)
        _ = perfMode
        return batch
    }

    private func releaseHeldInDomain(
        _ domain: EphemeralDomain,
        sourceID: String,
        forceExecute: Bool?
    ) -> AMEHeldReleaseBatch {
        let snap = domain.held.snapshot().filter { $0.identity.sourceID == sourceID }
        var released: [AMEHeldEntry] = []
        for entry in snap {
            if let e = domain.held.release(entry.identity) {
                released.append(e)
            }
        }
        var batch = buildReleaseBatch(
            entries: released,
            reason: .sourceDisconnect,
            forceExecute: forceExecute,
            hostTime: .now(),
            latencyID: UUID()
        )
        // Toggle OFF actions owned by this source.
        let toggleOffs = domain.toggles.release(forSourceID: sourceID)
        for (mappingID, record) in toggleOffs {
            let exec = forceExecute ?? record.wasLiveExecuted
            let emissions = makeEmissions(
                actions: record.releaseActions,
                mappingID: mappingID,
                controlValue: 0,
                quantizeBoundary: nil,
                failurePolicy: .cancel,
                shouldExecute: exec,
                isRelease: true,
                hostTime: .now(),
                latencyID: record.activationLatencyID ?? UUID()
            )
            batch.emissions.append(contentsOf: emissions.emissions)
            batch.diagnostics.append(contentsOf: emissions.diagnostics)
        }
        if !toggleOffs.isEmpty || !released.isEmpty {
            batch.diagnostics.append(
                AMEDiagnosticEvent(
                    kind: .heldReleasedBySourceDisconnect,
                    message: "Source \(sourceID) disconnect: held=\(released.count) toggles=\(toggleOffs.count)"
                )
            )
        }
        recordDiagnosticsOutsideLock(batch.diagnostics)
        return batch
    }

    /// Panic / disconnect / MIDI disable: release **live** held gates with executable deactivations.
    @discardableResult
    public func releaseAllHeld(
        reason: ReleaseReason = .releaseAll,
        shouldExecute: Bool? = nil
    ) -> AMEHeldReleaseBatch {
        // Default: live domain with provenance (or forced execute for panic).
        let force: Bool? = shouldExecute
        var batch = releaseDomain(liveDomain, reason: reason, forceExecute: force ?? true)
        // Also clear simulation without executable releases.
        let sim = releaseDomain(simDomain, reason: reason, forceExecute: false)
        batch.releasedEntries.append(contentsOf: sim.releasedEntries)
        batch.emissions.append(contentsOf: sim.emissions)
        batch.diagnostics.append(contentsOf: sim.diagnostics)
        return batch
    }

    public func resetEphemeralState() {
        _ = releaseDomain(liveDomain, reason: .releaseAll, forceExecute: false)
        _ = releaseDomain(simDomain, reason: .releaseAll, forceExecute: false)
        lock.lock()
        liveDomain.clearAllEphemeral()
        simDomain.clearAllEphemeral()
        lock.unlock()
    }

    /// Release one domain's holds/toggles. `forceExecute` overrides per-entry `wasLiveExecuted` when non-nil.
    private func releaseDomain(
        _ domain: EphemeralDomain,
        reason: ReleaseReason,
        forceExecute: Bool?
    ) -> AMEHeldReleaseBatch {
        let released = domain.held.releaseAll()
        let toggleOffs = domain.toggles.clear()
        var batch = buildReleaseBatch(
            entries: released,
            reason: reason,
            forceExecute: forceExecute,
            hostTime: .now(),
            latencyID: UUID()
        )
        for (mappingID, record) in toggleOffs {
            let exec = forceExecute ?? record.wasLiveExecuted
            let emissions = makeEmissions(
                actions: record.releaseActions,
                mappingID: mappingID,
                controlValue: 0,
                quantizeBoundary: nil,
                failurePolicy: .cancel,
                shouldExecute: exec,
                isRelease: true,
                hostTime: .now(),
                latencyID: UUID()
            )
            batch.emissions.append(contentsOf: emissions.emissions)
            batch.diagnostics.append(contentsOf: emissions.diagnostics)
        }
        recordDiagnosticsOutsideLock(batch.diagnostics)
        return batch
    }

    // MARK: Evaluate

    /// Process one normalized performance event.
    /// Entire evaluation (including rate-limit check/reserve) is serialized under the runtime lock.
    @discardableResult
    public func process(
        _ event: AMENormalizedEvent,
        document overrideDocument: AMEProjectDocument? = nil,
        context overrideContext: AMEShowContext? = nil,
        timing overrideTiming: AMETimingSnapshot? = nil,
        mode overrideMode: AMEPerformanceMode? = nil
    ) -> AMEEventResult {
        lock.lock()
        defer { lock.unlock() }

        let doc = overrideDocument ?? document
        let ctx = overrideContext ?? showContext
        let time = overrideTiming ?? timing
        let perfMode = overrideMode ?? mode
        let dom = domain(for: perfMode)

        let normalized = event.normalized()
        let latencyID = normalized.latencyID
        let shouldExecuteArmed = perfMode == .armed

        if perfMode == .edit {
            var result = AMEEventResult.empty(latencyID: latencyID)
            let d = AMEDiagnosticEvent(
                kind: .modeEditSkipped,
                latencyID: latencyID,
                message: "AME edit mode — evaluation skipped",
                hostTime: normalized.hostTime
            )
            result.diagnostics.append(d)
            appendDiagnosticsUnlocked(result.diagnostics)
            return result
        }

        var result = AMEEventResult(latencyID: latencyID)
        result.diagnostics.append(
            AMEDiagnosticEvent(
                kind: .eventReceived,
                latencyID: latencyID,
                message: "\(normalized.messageType.rawValue) ch\(normalized.channel) d1=\(normalized.data1.map(String.init) ?? "-") d2=\(normalized.data2.map(String.init) ?? "-")",
                hostTime: normalized.hostTime
            )
        )

        // Defensive first-wins indexes (never trap on duplicate IDs).
        let bindingIndex = AMESafeIndex.firstWins(doc.sourceBindings, id: \.id)
        let triggerIndex = AMESafeIndex.firstWins(doc.triggers, id: \.id)
        let groupIndex = AMESafeIndex.firstWins(doc.triggerGroups, id: \.id)
        let sequenceIndex = AMESafeIndex.firstWins(doc.sequences, id: \.id)
        let bindings = bindingIndex.map
        let sequencesByID = sequenceIndex.map
        let totalDups = bindingIndex.duplicateCount + triggerIndex.duplicateCount
            + groupIndex.duplicateCount + sequenceIndex.duplicateCount
        if totalDups > 0 {
            result.diagnostics.append(
                AMEDiagnosticEvent(
                    kind: .invalidRuntimeConfiguration,
                    latencyID: latencyID,
                    message: "Duplicate IDs ignored (first-wins): \(totalDups)",
                    hostTime: normalized.hostTime
                )
            )
        }

        // --- Early held release (never blocked by fire-time gates) ---
        if isPhysicalReleaseEdge(normalized) {
            let released = releaseMatchingHoldsUnlocked(
                domain: dom,
                event: normalized,
                latencyID: latencyID
            )
            result.emissions.append(contentsOf: released.emissions)
            result.diagnostics.append(contentsOf: released.diagnostics)
        }

        // Match triggers (strict type for fire path).
        let resolvedBindings = resolvedSourceIDsByBinding
        var matchedTriggerIDs = Set<UUID>()
        for trigger in doc.triggers {
            if AMEMatchEngine.triggerMatches(
                trigger,
                event: normalized,
                bindings: bindings,
                resolvedSourceIDsByBinding: resolvedBindings
            ) {
                matchedTriggerIDs.insert(trigger.id)
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .triggerMatched,
                        latencyID: latencyID,
                        triggerID: trigger.id,
                        message: "Trigger “\(trigger.name)” matched",
                        hostTime: normalized.hostTime
                    )
                )
            }
        }
        result.matchedTriggerIDs = Array(matchedTriggerIDs)

        var matchedGroupIDs = Set<UUID>()
        for group in doc.triggerGroups {
            if group.memberTriggerIDs.contains(where: { matchedTriggerIDs.contains($0) }) {
                matchedGroupIDs.insert(group.id)
            }
        }

        let localIDs = activeSectionLocalMappingIDs
        let setIDs = activeSectionMappingSetIDs
        let effectiveIDs = Self.effectiveMappingIDs(
            document: doc,
            context: ctx,
            localMappingIDs: localIDs,
            mappingSetIDs: setIDs
        )

        // Fire-path candidates only (release already handled).
        var candidates: [AMEMapping] = []
        for mapping in doc.mappings {
            guard effectiveIDs.contains(mapping.id) else {
                if AMEMatchEngine.scopeIsActive(mapping.scope, context: ctx) == false {
                    result.diagnostics.append(
                        AMEDiagnosticEvent(
                            kind: .scopeInactive,
                            latencyID: latencyID,
                            mappingID: mapping.id,
                            message: "Mapping “\(mapping.name)” not effective for context",
                            hostTime: normalized.hostTime
                        )
                    )
                }
                continue
            }

            let triggerHit: Bool
            if let tid = mapping.triggerID {
                triggerHit = matchedTriggerIDs.contains(tid)
            } else if let gid = mapping.triggerGroupID {
                triggerHit = matchedGroupIDs.contains(gid)
            } else {
                triggerHit = false
            }
            guard triggerHit else { continue }

            candidates.append(mapping)
            result.diagnostics.append(
                AMEDiagnosticEvent(
                    kind: .mappingCandidate,
                    latencyID: latencyID,
                    mappingID: mapping.id,
                    message: "Mapping “\(mapping.name)” candidate",
                    hostTime: normalized.hostTime
                )
            )
        }

        let activeEnabled = candidates.filter(\.enabled)
        var suppressed = Set<UUID>()
        for child in activeEnabled {
            if let parent = child.disablesParentID { suppressed.insert(parent) }
            if let parent = child.overrideParentID { suppressed.insert(parent) }
        }

        let ordered = candidates.sorted { a, b in
            let sa = AMEMatchEngine.scopeSpecificity(a.scope)
            let sb = AMEMatchEngine.scopeSpecificity(b.scope)
            if sa != sb { return sa > sb }
            if a.priority != b.priority { return a.priority > b.priority }
            return a.id.uuidString < b.id.uuidString
        }

        let nowSeconds = normalized.hostTime.seconds

        for mapping in ordered {
            if suppressed.contains(mapping.id) {
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .mappingSuppressed,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: "Mapping “\(mapping.name)” suppressed by override/disable child",
                        hostTime: normalized.hostTime
                    )
                )
                continue
            }
            if !mapping.enabled {
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .mappingDisabled,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: "Mapping “\(mapping.name)” disabled (still owns legacy claims)",
                        hostTime: normalized.hostTime
                    )
                )
                continue
            }
            if !time.satisfies(mapping.timingRequirement) {
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .timingRequirementFailed,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: "Timing requirement \(mapping.timingRequirement.rawValue) not met",
                        hostTime: normalized.hostTime
                    )
                )
                continue
            }

            // Atomic rate-limit check + reserve (under process lock, per domain).
            if let hit = rateLimitDecisionUnlocked(domain: dom, mapping: mapping, nowSeconds: nowSeconds) {
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: hit.kind,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: hit.message,
                        hostTime: normalized.hostTime
                    )
                )
                continue
            }

            guard let controlValue = AMEValueTransformEvaluator.apply(
                mapping.transform,
                rawNormalized: normalized.rawNormalizedValue
            ) else {
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .transformRejected,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: "Transform threshold rejected",
                        hostTime: normalized.hostTime
                    )
                )
                continue
            }

            let decision = evaluateFireBehavior(
                domain: dom,
                mapping: mapping,
                event: normalized,
                controlValue: controlValue,
                latencyID: latencyID,
                wasLiveExecuted: shouldExecuteArmed
            )

            switch decision {
            case .skip(let reason):
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .behaviorSkipped,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: reason,
                        hostTime: normalized.hostTime
                    )
                )
                continue

            case .fireActivation(let actions):
                markFiredUnlocked(domain: dom, mappingID: mapping.id, nowSeconds: nowSeconds)
                result.matchedMappingIDs.append(mapping.id)
                var fireActions = actions

                // Stateful sequence step: one qualifying event → one step fire + advance.
                if let seqID = mapping.sequenceID {
                    let seqResult = resolveSequenceTrigger(
                        domain: dom,
                        sequenceID: seqID,
                        sequencesByID: sequencesByID,
                        context: ctx,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        hostTime: normalized.hostTime
                    )
                    fireActions.append(contentsOf: seqResult.actions)
                    result.diagnostics.append(contentsOf: seqResult.diagnostics)
                }

                // Expand sequence control actions embedded in mapping.actions.
                let expanded = expandSequenceControlActions(
                    fireActions,
                    domain: dom,
                    sequencesByID: sequencesByID,
                    context: ctx,
                    latencyID: latencyID,
                    mappingID: mapping.id,
                    hostTime: normalized.hostTime
                )
                fireActions = expanded.actions
                result.diagnostics.append(contentsOf: expanded.diagnostics)

                let built = makeEmissions(
                    actions: fireActions,
                    mappingID: mapping.id,
                    controlValue: controlValue,
                    quantizeBoundary: mapping.quantizeBoundary,
                    failurePolicy: mapping.quantizationFailurePolicy,
                    shouldExecute: shouldExecuteArmed,
                    isRelease: false,
                    hostTime: normalized.hostTime,
                    latencyID: latencyID,
                    musicalTimeAvailable: time.musicalTimeAvailable
                )
                result.emissions.append(contentsOf: built.emissions)
                result.diagnostics.append(contentsOf: built.diagnostics)
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .behaviorFired,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: "Mapping “\(mapping.name)” activated (\(mapping.behavior.rawValue))",
                        hostTime: normalized.hostTime
                    )
                )

            case .fireDeactivation(let actions, let wasLive):
                markFiredUnlocked(domain: dom, mappingID: mapping.id, nowSeconds: nowSeconds)
                result.matchedMappingIDs.append(mapping.id)
                // Deactivation executability follows activation provenance.
                let built = makeEmissions(
                    actions: actions,
                    mappingID: mapping.id,
                    controlValue: controlValue,
                    quantizeBoundary: mapping.quantizeBoundary,
                    failurePolicy: mapping.quantizationFailurePolicy,
                    shouldExecute: wasLive,
                    isRelease: true,
                    hostTime: normalized.hostTime,
                    latencyID: latencyID,
                    musicalTimeAvailable: time.musicalTimeAvailable
                )
                result.emissions.append(contentsOf: built.emissions)
                result.diagnostics.append(contentsOf: built.diagnostics)
                result.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .behaviorFired,
                        latencyID: latencyID,
                        mappingID: mapping.id,
                        message: "Mapping “\(mapping.name)” deactivated (\(mapping.behavior.rawValue))",
                        hostTime: normalized.hostTime
                    )
                )
            }
        }

        _ = triggerIndex
        _ = groupIndex

        appendDiagnosticsUnlocked(result.diagnostics)
        return result
    }

    // MARK: - Sequence integration (Phase E)

    private struct SequenceResolveOutput {
        var actions: [AuroraAction]
        var diagnostics: [AMEDiagnosticEvent]
    }

    private func resolveSequenceTrigger(
        domain: EphemeralDomain,
        sequenceID: UUID,
        sequencesByID: [UUID: AMETriggeredSequence],
        context: AMEShowContext,
        latencyID: UUID,
        mappingID: UUID,
        hostTime: HostTime
    ) -> SequenceResolveOutput {
        guard let seq = sequencesByID[sequenceID] else {
            return SequenceResolveOutput(
                actions: [],
                diagnostics: [
                    AMEDiagnosticEvent(
                        kind: .sequenceMissing,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        sequenceID: sequenceID,
                        message: "Sequence missing — broken reference",
                        hostTime: hostTime
                    ),
                ]
            )
        }
        switch domain.sequences.trigger(sequence: seq, context: context) {
        case .failure(.emptySequence):
            return SequenceResolveOutput(
                actions: [],
                diagnostics: [
                    AMEDiagnosticEvent(
                        kind: .sequenceEmpty,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        sequenceID: sequenceID,
                        message: "Sequence “\(seq.name)” has no steps",
                        hostTime: hostTime
                    ),
                ]
            )
        case .failure(.noContext):
            return SequenceResolveOutput(
                actions: [],
                diagnostics: [
                    AMEDiagnosticEvent(
                        kind: .sequenceNoContext,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        sequenceID: sequenceID,
                        message: "Sequence “\(seq.name)” needs active song/section context",
                        hostTime: hostTime
                    ),
                ]
            )
        case .failure:
            return SequenceResolveOutput(
                actions: [],
                diagnostics: [
                    AMEDiagnosticEvent(
                        kind: .sequenceMissing,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        sequenceID: sequenceID,
                        message: "Sequence trigger failed",
                        hostTime: hostTime
                    ),
                ]
            )
        case .success(let fire):
            return SequenceResolveOutput(
                actions: fire.actions,
                diagnostics: [
                    AMEDiagnosticEvent(
                        kind: .sequenceStepFired,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        sequenceID: fire.sequenceID,
                        stepIndex: fire.stepIndex,
                        message: "Sequence “\(seq.name)” fired step \(fire.stepIndex) “\(fire.stepName)” (\(fire.nextCursorDescription))",
                        hostTime: hostTime
                    ),
                    AMEDiagnosticEvent(
                        kind: .sequenceAdvanced,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        sequenceID: fire.sequenceID,
                        stepIndex: fire.stepIndex,
                        message: "Sequence “\(seq.name)” state \(fire.nextCursorDescription)",
                        hostTime: hostTime
                    ),
                ]
            )
        }
    }

    /// Handle sequence control actions. Control actions inside step payloads are not re-expanded (no recursion).
    private func expandSequenceControlActions(
        _ actions: [AuroraAction],
        domain: EphemeralDomain,
        sequencesByID: [UUID: AMETriggeredSequence],
        context: AMEShowContext,
        latencyID: UUID,
        mappingID: UUID,
        hostTime: HostTime
    ) -> SequenceResolveOutput {
        var outActions: [AuroraAction] = []
        var diags: [AMEDiagnosticEvent] = []
        for action in flatten(actions) {
            switch action {
            case .resetSequence(let id):
                if let seq = sequencesByID[id] {
                    domain.sequences.reset(sequence: seq, context: context)
                    diags.append(
                        AMEDiagnosticEvent(
                            kind: .sequenceReset,
                            latencyID: latencyID,
                            mappingID: mappingID,
                            sequenceID: id,
                            message: "resetSequence “\(seq.name)”",
                            hostTime: hostTime
                        )
                    )
                } else {
                    diags.append(
                        AMEDiagnosticEvent(
                            kind: .sequenceMissing,
                            latencyID: latencyID,
                            mappingID: mappingID,
                            sequenceID: id,
                            message: "resetSequence missing",
                            hostTime: hostTime
                        )
                    )
                }
            case .advanceSequence(let id):
                // Advance state only — do not fire step actions.
                if let seq = sequencesByID[id] {
                    switch domain.sequences.advanceOnly(sequence: seq, context: context) {
                    case .success(let cursor):
                        diags.append(
                            AMEDiagnosticEvent(
                                kind: .sequenceControlAction,
                                latencyID: latencyID,
                                mappingID: mappingID,
                                sequenceID: id,
                                stepIndex: cursor,
                                message: "advanceSequence → cursor \(cursor) (no fire)",
                                hostTime: hostTime
                            )
                        )
                    case .failure(.emptySequence):
                        diags.append(
                            AMEDiagnosticEvent(
                                kind: .sequenceEmpty,
                                latencyID: latencyID,
                                mappingID: mappingID,
                                sequenceID: id,
                                message: "advanceSequence empty",
                                hostTime: hostTime
                            )
                        )
                    case .failure:
                        diags.append(
                            AMEDiagnosticEvent(
                                kind: .sequenceMissing,
                                latencyID: latencyID,
                                mappingID: mappingID,
                                sequenceID: id,
                                message: "advanceSequence failed",
                                hostTime: hostTime
                            )
                        )
                    }
                } else {
                    diags.append(
                        AMEDiagnosticEvent(
                            kind: .sequenceMissing,
                            latencyID: latencyID,
                            mappingID: mappingID,
                            sequenceID: id,
                            message: "advanceSequence missing",
                            hostTime: hostTime
                        )
                    )
                }
            case .fireSequenceStep(let id, let stepIndex):
                if let seq = sequencesByID[id], !seq.steps.isEmpty {
                    guard stepIndex >= 0, stepIndex < seq.steps.count else {
                        diags.append(
                            AMEDiagnosticEvent(
                                kind: .sequenceInvalidStep,
                                latencyID: latencyID,
                                mappingID: mappingID,
                                sequenceID: id,
                                stepIndex: stepIndex,
                                message: "fireSequenceStep index \(stepIndex) out of bounds (count=\(seq.steps.count))",
                                hostTime: hostTime
                            )
                        )
                        break
                    }
                    // Fire without mutating sequence cursor.
                    outActions.append(contentsOf: seq.steps[stepIndex].actions)
                    diags.append(
                        AMEDiagnosticEvent(
                            kind: .sequenceControlAction,
                            latencyID: latencyID,
                            mappingID: mappingID,
                            sequenceID: id,
                            stepIndex: stepIndex,
                            message: "fireSequenceStep \(stepIndex) (cursor unchanged)",
                            hostTime: hostTime
                        )
                    )
                } else {
                    diags.append(
                        AMEDiagnosticEvent(
                            kind: .sequenceMissing,
                            latencyID: latencyID,
                            mappingID: mappingID,
                            sequenceID: id,
                            message: "fireSequenceStep missing/empty",
                            hostTime: hostTime
                        )
                    )
                }
            default:
                outActions.append(action)
            }
        }
        return SequenceResolveOutput(actions: outActions, diagnostics: diags)
    }

    // MARK: - Release helpers

    private func isPhysicalReleaseEdge(_ event: AMENormalizedEvent) -> Bool {
        if event.isNoteOffEdge { return true }
        if event.messageType == .cc, (event.data2 ?? 0) < 64 { return true }
        return false
    }

    private func isPhysicalAcquireEdge(_ event: AMENormalizedEvent) -> Bool {
        if event.isNoteOnEdge { return true }
        if event.messageType == .cc, (event.data2 ?? 0) >= 64 { return true }
        return false
    }

    /// Release holds matching the physical key of this event (source/channel/data1).
    private func releaseMatchingHoldsUnlocked(
        domain: EphemeralDomain,
        event: AMENormalizedEvent,
        latencyID: UUID
    ) -> AMEHeldReleaseBatch {
        var released: [AMEHeldEntry] = []
        for entry in domain.held.snapshot() {
            guard entry.identity.matchesPhysicalKey(of: event) else { continue }
            if let e = domain.held.release(entry.identity) {
                released.append(e)
            }
        }
        return buildReleaseBatch(
            entries: released,
            reason: .physicalEdge,
            forceExecute: nil,
            hostTime: event.hostTime,
            latencyID: latencyID,
            recordDiagnostics: false
        )
    }

    /// Build release emissions. When `forceExecute` is nil, each entry uses `wasLiveExecuted`.
    private func buildReleaseBatch(
        entries: [AMEHeldEntry],
        reason: ReleaseReason,
        forceExecute: Bool?,
        hostTime: HostTime,
        latencyID: UUID,
        recordDiagnostics: Bool = true
    ) -> AMEHeldReleaseBatch {
        var batch = AMEHeldReleaseBatch(releasedEntries: entries)
        let kind: AMEDiagnosticKind
        switch reason {
        case .releaseAll: kind = .heldReleaseAll
        case .documentChange: kind = .heldReleasedByDocumentChange
        case .contextChange: kind = .heldReleasedByContextChange
        case .modeChange: kind = .heldReleasedByModeChange
        case .physicalEdge: kind = .heldReleased
        case .sourceDisconnect: kind = .heldReleasedBySourceDisconnect
        }

        if !entries.isEmpty {
            batch.diagnostics.append(
                AMEDiagnosticEvent(
                    kind: kind,
                    latencyID: latencyID,
                    message: "Released \(entries.count) held gate(s) (\(reason))",
                    hostTime: hostTime
                )
            )
        }

        for entry in entries {
            let exec = forceExecute ?? entry.wasLiveExecuted
            let built = makeEmissions(
                actions: entry.releaseActions,
                mappingID: entry.identity.mappingID,
                controlValue: entry.controlValue,
                quantizeBoundary: nil,
                failurePolicy: .cancel,
                shouldExecute: exec,
                isRelease: true,
                hostTime: hostTime,
                latencyID: entry.activationLatencyID ?? latencyID
            )
            batch.emissions.append(contentsOf: built.emissions)
            for d in built.diagnostics {
                var dd = d
                if d.kind == .armedEmission || d.kind == .dryRunEmission {
                    dd = AMEDiagnosticEvent(
                        kind: .heldReleaseEmission,
                        latencyID: d.latencyID,
                        mappingID: d.mappingID,
                        message: d.message,
                        hostTime: d.hostTime
                    )
                }
                batch.diagnostics.append(dd)
            }
        }

        if recordDiagnostics {
            recordDiagnosticsOutsideLock(batch.diagnostics)
        }
        return batch
    }

    private func recordDiagnosticsOutsideLock(_ events: [AMEDiagnosticEvent]) {
        lock.lock()
        appendDiagnosticsUnlocked(events)
        lock.unlock()
    }

    // MARK: - Behavior (fire path only)

    private enum FireDecision: Equatable {
        case skip(String)
        case fireActivation([AuroraAction])
        case fireDeactivation([AuroraAction], wasLiveExecuted: Bool)
    }

    private func evaluateFireBehavior(
        domain: EphemeralDomain,
        mapping: AMEMapping,
        event: AMENormalizedEvent,
        controlValue: Double,
        latencyID: UUID,
        wasLiveExecuted: Bool
    ) -> FireDecision {
        switch mapping.behavior {
        case .trigger:
            if event.isNoteOffEdge { return .skip("trigger ignores noteOff") }
            if event.messageType == .noteOn || event.messageType == .programChange {
                return .fireActivation(activationActions(mapping))
            }
            if event.messageType == .cc {
                return (event.data2 ?? 0) > 0
                    ? .fireActivation(activationActions(mapping))
                    : .skip("CC zero")
            }
            return .fireActivation(activationActions(mapping))

        case .toggle:
            if event.isNoteOffEdge { return .skip("toggle ignores noteOff") }
            if event.messageType == .cc && (event.data2 ?? 0) == 0 {
                return .skip("toggle ignores CC zero")
            }
            switch domain.toggles.flip(
                mappingID: mapping.id,
                sourceID: event.sourceID,
                channel: event.channel,
                data1: event.data1,
                releaseActions: mapping.releaseActions,
                wasLiveExecuted: wasLiveExecuted,
                activationLatencyID: latencyID
            ) {
            case .activated:
                return .fireActivation(activationActions(mapping))
            case .deactivated(let record):
                return record.releaseActions.isEmpty
                    ? .skip("toggle off (no releaseActions)")
                    : .fireDeactivation(record.releaseActions, wasLiveExecuted: record.wasLiveExecuted)
            }

        case .momentary, .whileHeld, .heldGate:
            if event.isNoteOffEdge || (event.messageType == .cc && (event.data2 ?? 0) < 64) {
                return .skip("release handled on early path")
            }
            guard isPhysicalAcquireEdge(event) || event.messageType == .programChange else {
                return .skip("held behavior needs acquire edge")
            }
            let identity = AMEHeldIdentity.from(mappingID: mapping.id, event: event)
            let entry = AMEHeldEntry(
                identity: identity,
                acquiredHostTime: event.hostTime,
                controlValue: controlValue,
                releaseActions: mapping.releaseActions,
                mappingScope: mapping.scope,
                activationLatencyID: latencyID,
                wasLiveExecuted: wasLiveExecuted
            )
            guard domain.held.acquire(entry) else {
                return .skip("already held")
            }
            return .fireActivation(activationActions(mapping))

        case .continuous:
            if event.isNoteOffEdge { return .skip("continuous ignores noteOff") }
            return .fireActivation(activationActions(mapping))
        }
    }

    private func activationActions(_ mapping: AMEMapping) -> [AuroraAction] {
        mapping.actions
    }

    // Expand sequence step into activation list when sequenceID present.
    // Called from process before evaluateFireBehavior would be cleaner — do it when firing.

    // MARK: - Emissions

    private struct BuiltEmissions {
        var emissions: [AMEActionEmission]
        var diagnostics: [AMEDiagnosticEvent]
    }

    private func makeEmissions(
        actions: [AuroraAction],
        mappingID: UUID,
        controlValue: Double,
        quantizeBoundary: AMEQuantizationBoundary?,
        failurePolicy: AMEQuantizationFailurePolicy,
        shouldExecute: Bool,
        isRelease: Bool,
        hostTime: HostTime,
        latencyID: UUID,
        musicalTimeAvailable: Bool = true
    ) -> BuiltEmissions {
        var out = BuiltEmissions(emissions: [], diagnostics: [])
        for action in flatten(actions) {
            let safety = action.isSafetyCritical
            let liveOK = AMELiveActionSupport.isLiveSupported(action)
            let boundary = quantizeBoundary
            let wantsQuantize = boundary != nil && boundary != .immediate && !safety && !isRelease

            var executeImmediately = safety || isRelease || boundary == nil || boundary == .immediate
            var include = true
            var diagKind: AMEDiagnosticKind = shouldExecute ? .armedEmission : .dryRunEmission

            if !liveOK {
                out.diagnostics.append(
                    AMEDiagnosticEvent(
                        kind: .unsupportedAction,
                        latencyID: latencyID,
                        mappingID: mappingID,
                        message: "Unsupported live action: \(action.storageKey)",
                        hostTime: hostTime
                    )
                )
                out.emissions.append(
                    AMEActionEmission(
                        latencyID: latencyID,
                        mappingID: mappingID,
                        action: action,
                        controlValue: controlValue,
                        quantizeBoundary: boundary,
                        quantizationFailurePolicy: failurePolicy,
                        executeImmediately: true,
                        shouldExecute: false,
                        isLiveSupported: false,
                        isRelease: isRelease,
                        ingressHostTime: hostTime
                    )
                )
                continue
            }

            if wantsQuantize {
                if !musicalTimeAvailable {
                    switch failurePolicy {
                    case .cancel:
                        include = false
                        diagKind = .quantizeCancelled
                    case .executeImmediately:
                        executeImmediately = true
                        diagKind = .quantizeImmediate
                    case .holdUntilTimingAvailable:
                        // Wave 2 / P0-4: emit for MusicalEngine held queue — do not drop.
                        include = true
                        executeImmediately = false
                        diagKind = .quantizeHeld
                    }
                } else {
                    // Host schedules via MusicalEngine; do not force immediate.
                    executeImmediately = false
                    diagKind = .quantizeDeferred
                }
            }
            if safety { executeImmediately = true }

            out.diagnostics.append(
                AMEDiagnosticEvent(
                    kind: diagKind,
                    latencyID: latencyID,
                    mappingID: mappingID,
                    message: "\(action.storageKey) release=\(isRelease) exec=\(shouldExecute && include)",
                    hostTime: hostTime
                )
            )
            guard include else { continue }

            out.emissions.append(
                AMEActionEmission(
                    latencyID: latencyID,
                    mappingID: mappingID,
                    action: action,
                    controlValue: controlValue,
                    quantizeBoundary: boundary,
                    quantizationFailurePolicy: failurePolicy,
                    executeImmediately: executeImmediately,
                    shouldExecute: shouldExecute,
                    isLiveSupported: true,
                    isRelease: isRelease,
                    ingressHostTime: hostTime
                )
            )
        }
        return out
    }

    private func flatten(_ actions: [AuroraAction]) -> [AuroraAction] {
        var out: [AuroraAction] = []
        for a in actions {
            if case .compound(let inner) = a {
                out.append(contentsOf: flatten(inner))
            } else {
                out.append(a)
            }
        }
        return out
    }

    // MARK: - Rate limit (must be called under lock)

    private struct RateLimitHit {
        var kind: AMEDiagnosticKind
        var message: String
    }

    private func rateLimitDecisionUnlocked(
        domain: EphemeralDomain,
        mapping: AMEMapping,
        nowSeconds: TimeInterval
    ) -> RateLimitHit? {
        if let burstMs = mapping.burstSuppressionMilliseconds, burstMs > 0 {
            if let last = domain.lastBurstSeconds[mapping.id],
               (nowSeconds - last) * 1000.0 < burstMs {
                return RateLimitHit(kind: .burstSuppressed, message: "Burst suppressed (\(burstMs) ms)")
            }
        }
        if mapping.debounceMilliseconds > 0 {
            if let last = domain.lastFireSeconds[mapping.id],
               (nowSeconds - last) * 1000.0 < mapping.debounceMilliseconds {
                return RateLimitHit(
                    kind: .debounceSuppressed,
                    message: "Debounce (\(mapping.debounceMilliseconds) ms)"
                )
            }
        }
        return nil
    }

    private func markFiredUnlocked(domain: EphemeralDomain, mappingID: UUID, nowSeconds: TimeInterval) {
        domain.lastBurstSeconds[mappingID] = nowSeconds
        domain.lastFireSeconds[mappingID] = nowSeconds
    }

    private func appendDiagnosticsUnlocked(_ events: [AMEDiagnosticEvent]) {
        for e in events {
            diagnosticRing.append(e)
            if diagnosticRing.count > diagnosticCapacity {
                diagnosticRing.removeFirst(diagnosticRing.count - diagnosticCapacity)
            }
        }
    }
}

// MARK: - Ownership helpers for dual-path hosts

public enum AMERuntimeOwnership {
    public static func filterLegacyMappings(
        _ mappings: [MIDIMapping],
        document: AMEProjectDocument
    ) -> [MIDIMapping] {
        let claimed = AMELegacyOwnership.claimedLegacyMappingIDs(in: document)
        return mappings.filter { !claimed.contains($0.id) }
    }

    public static func filterLegacyRules(
        _ rules: [MIDIRule],
        document: AMEProjectDocument
    ) -> [MIDIRule] {
        let claimed = AMELegacyOwnership.claimedLegacyRuleIDs(in: document)
        return rules.filter { !claimed.contains($0.id) }
    }
}

extension AMERuntime {
    /// Additive effective mapping activation (Wave 4):
    /// scope-active mappings ∪ section localMappingIDs ∪ members of active mapping sets.
    public static func effectiveMappingIDs(
        document: AMEProjectDocument,
        context: AMEShowContext,
        localMappingIDs: [UUID],
        mappingSetIDs: [UUID]
    ) -> Set<UUID> {
        var ids = Set<UUID>()
        for m in document.mappings {
            if AMEMatchEngine.scopeIsActive(m.scope, context: context) {
                ids.insert(m.id)
            }
        }
        for id in localMappingIDs {
            ids.insert(id)
        }
        var setsByID: [UUID: AMEMappingSet] = [:]
        for s in document.mappingSets where setsByID[s.id] == nil {
            setsByID[s.id] = s
        }
        for sid in mappingSetIDs {
            if let set = setsByID[sid] {
                for mid in set.mappingIDs {
                    ids.insert(mid)
                }
            }
        }
        return ids
    }
}
