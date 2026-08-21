import AuroraEngine
import AuroraMIDI
import AuroraModel
import AuroraMusical
import Foundation

/// Thread-safe flag for MIDI learn arming (readable from CoreMIDI callbacks).
final class MIDILearnFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _armed = false
    var isArmed: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _armed }
        set { lock.lock(); _armed = newValue; lock.unlock() }
    }
}

/// Token for a control-event UI observer subscription (UI-GATE-1).
struct ControlEventObserverToken: Hashable, Sendable {
    let id: UUID
}

enum ControlActionSourceType: String, Sendable {
    case localUI = "local_ui"
    case remote
    case conductor
    case midi
    case musicEngine = "music_engine"
    case automation
    case bridge
    case system
}

struct ControlActionOrigin: Sendable, Equatable {
    var sourceType: ControlActionSourceType
    var nodeID: String?
    var instanceID: String?
    var sessionID: String?
    var principalID: String?
    var commandID: String?
    var displayName: String?

    static let localUI = ControlActionOrigin(sourceType: .localUI)
}

/// Unified show-control dispatcher for MIDI / OSC / UI / remote (P1-9 / UI-GATE-1).
///
/// Live paths avoid MainActor. `fireCueIndex` targets the **active** playback list,
/// not `cueLists.first`.
///
/// Dual-path MIDI (Phase D): AME evaluates first; legacy mappings/rules run only when
/// not claimed by `claimsLegacyMappingID` / `claimsLegacyRuleID` (ownership, not event-wide suppression).
///
/// UI observation is multi-subscriber: installing a second observer never replaces the first.
final class ControlActionRouter: @unchecked Sendable {
    private let lock = NSLock()
    private weak var engine: LightingEngine?
    private var mappings: [MIDIMapping] = []
    private var rules: [MIDIRule] = []
    private var project: ShowProject = .empty()
    private var selectedFixtureIDs: Set<UUID> = []
    private var orderedFixtureIDs: [UUID] = []
    private var songSectionLabel: String?
    private var activeSongID: UUID?
    private var activeSectionID: UUID?
    private var ameTiming = AMETimingSnapshot.internalAvailable
    private let safety = MIDISafetyLimiter(maxEventsPerSecond: 250, debounceSeconds: 0)
    /// Multi-observer map (replaces single replaceable callback).
    private var uiObservers: [UUID: @Sendable (ShowAction, String) -> Void] = [:]
    /// Headless AME pipeline (Phase D+).
    private let ameRuntime = AMERuntime()
    /// Musical Engine for quantized AME emissions (Phase G). Optional until wired.
    private var musicalEngine: MusicalEngine?
    private let actionTokens = AuroraActionTokenRegistry()
    /// Host navigation callbacks (song/section). Wired by ShowControlController.
    private var hostCallbacks = AuroraActionHostCallbacks()
    /// Recent AME diagnostics for the MIDI Engine window monitor (Phase F).
    private var monitorRing: [AMEDiagnosticEvent] = []
    private let monitorCapacity = 200
    /// Live MIDI inventory for Learn binding durability (names, not ephemeral ep: IDs).
    private var sourceInventory: [MIDISourceIdentity.InventorySource] = []
    private var lastControlOrigin: ControlActionOrigin = .localUI

    init(engine: LightingEngine) {
        self.engine = engine
    }

    /// Publish current CoreMIDI inventory for Learn metadata capture.
    func setSourceInventory(_ inventory: [MIDISourceIdentity.InventorySource]) {
        lock.lock()
        sourceInventory = inventory
        lock.unlock()
    }

    /// Install product navigation hooks so song/section actions are never silent no-ops.
    func setHostCallbacks(_ callbacks: AuroraActionHostCallbacks) {
        lock.lock()
        hostCallbacks = callbacks
        lock.unlock()
    }

    /// Attach Musical Engine for quantization + timing snapshots.
    func attachMusicalEngine(_ engine: MusicalEngine) {
        lock.lock()
        musicalEngine = engine
        lock.unlock()
        engine.setScheduleFireHandler { [weak self] scheduled in
            self?.handleScheduledFire(scheduled)
        }
        engine.setScheduleCancelHandler { [weak self] canceled in
            for action in canceled {
                if case .auroraActionToken(let token, _) = action.command {
                    _ = self?.actionTokens.consume(token)
                }
            }
        }
    }

    /// Presentation-only timing snapshot refresh (driver owns harvest cadence).
    func refreshAMETimingFromMusicalEngine() {
        lock.lock()
        let me = musicalEngine
        lock.unlock()
        guard let me else { return }
        updateAMETiming(AMETimingSnapshot.from(musical: me.state))
    }

    /// Backward-compatible alias: prefer dedicated driver for ticks; this only refreshes AME timing.
    func tickMusicalEngine() {
        refreshAMETimingFromMusicalEngine()
    }

    var ameRuntimeForDiagnostics: AMERuntime { ameRuntime }

    // MARK: AME Learn (Wave 5)

    private var ameLearnArmed = false
    private var ameLearnPendingName: String = "Learned Trigger"

    var isAMELearning: Bool {
        lock.lock(); defer { lock.unlock() }
        return ameLearnArmed
    }

    func beginAMELearn(name: String = "Learned Trigger") {
        lock.lock()
        ameLearnArmed = true
        ameLearnPendingName = name
        lastAMELearnProposal = nil
        lock.unlock()
    }

    /// Cancel armed Learn and discard any uncommitted proposal (window close / user cancel).
    func cancelAMELearn() {
        lock.lock()
        ameLearnArmed = false
        lastAMELearnProposal = nil
        lock.unlock()
    }

    /// Capture first channel-voice event into AME trigger + mapping via session callback is handled by host.
    /// Returns a proposed document fragment for the host to commit with undo commands.
    struct AMELearnProposal: Sendable {
        var binding: MIDISourceBinding?
        var trigger: AMETriggerDefinition
        var mapping: AMEMapping
    }

    func handleAMELearnEvents(_ events: [MIDIEvent]) {
        lock.lock()
        guard ameLearnArmed else { lock.unlock(); return }
        let name = ameLearnPendingName
        let inventory = sourceInventory
        lock.unlock()
        guard let event = events.first, let normalized = Self.ameNormalized(from: event) else { return }
        // Resolve inventory metadata so we never persist ephemeral ep: as the name hint.
        let meta = inventory.first(where: { $0.id == normalized.sourceID })
        switch Self.makeLearnProposal(from: normalized, name: name, sourceMetadata: meta) {
        case .success(let proposal):
            lock.lock()
            ameLearnArmed = false
            lastAMELearnProposal = proposal
            lock.unlock()
            recordMonitor([
                AMEDiagnosticEvent(
                    kind: .triggerMatched,
                    message: "AME Learn captured \(normalized.messageType.rawValue) ch\(normalized.channel)"
                ),
            ])
        case .failure(let reason):
            // Stay armed so the operator can retry once inventory is available; no orphan commit.
            recordMonitor([
                AMEDiagnosticEvent(
                    kind: .learnCaptureFailed,
                    message: "AME Learn failed: \(reason). Still learning — hit again when source is known."
                ),
            ])
        }
    }

    private var lastAMELearnProposal: AMELearnProposal?

    func consumeAMELearnProposal() -> AMELearnProposal? {
        lock.lock(); defer { lock.unlock() }
        let p = lastAMELearnProposal
        lastAMELearnProposal = nil
        return p
    }

    enum LearnProposalResult: Sendable {
        case success(AMELearnProposal)
        case failure(reason: String)
    }

    /// Build Learn proposal with durable binding metadata.
    ///
    /// - UID sources store CoreMIDI UniqueID + friendly inventory name/manufacturer.
    /// - Non-UID sources store actual endpoint name as `endpointNameHint`, **never** `ep:…`.
    /// - Non-UID `ep:` without inventory name **fails** — no orphan binding commit.
    static func makeLearnProposal(
        from event: AMENormalizedEvent,
        name: String,
        sourceMetadata: MIDISourceIdentity.InventorySource? = nil
    ) -> LearnProposalResult {
        switch MIDISourceIdentity.makeDurableBinding(
            runtimeSourceID: event.sourceID,
            inventory: sourceMetadata
        ) {
        case .unavailable(let reason):
            return .failure(reason: reason)
        case .binding(let binding):
            let trigger = AMETriggerDefinition(
                name: name,
                friendlyName: name,
                sourceBindingID: binding.id,
                channel: event.channel,
                messageType: event.messageType,
                data1Min: event.data1,
                data1Max: event.data1
            )
            let mapping = AMEMapping(
                name: name,
                triggerID: trigger.id,
                actions: [.go]
            )
            return .success(AMELearnProposal(binding: binding, trigger: trigger, mapping: mapping))
        }
    }

    func handleMIDISourceDisconnected(_ sourceID: String) {
        // AME held + source-owned toggles.
        let batch = ameRuntime.releaseHeld(forSourceID: sourceID)
        applyAMEReleaseBatch(batch)
        // Sustained MIDI behaviors for this device (envelopes release at current engine time).
        lock.lock()
        let eng = engine
        lock.unlock()
        let now = eng?.currentResolvedSnapshot().timestamp ?? 0
        let behaviorReleased = eng?.midiBehaviors.releaseAll(forDeviceID: sourceID, at: now) ?? 0
        if batch.diagnostics.isEmpty && behaviorReleased == 0 {
            recordMonitor([
                AMEDiagnosticEvent(
                    kind: .heldReleasedBySourceDisconnect,
                    message: "Source disconnected \(sourceID); nothing held/toggled/behaviors"
                ),
            ])
        } else {
            recordMonitor(batch.diagnostics)
            if behaviorReleased > 0 {
                recordMonitor([
                    AMEDiagnosticEvent(
                        kind: .heldReleasedBySourceDisconnect,
                        message: "Source \(sourceID) released \(behaviorReleased) MIDI behavior(s)"
                    ),
                ])
            }
        }
    }

    func recentAMEMonitorEvents(limit: Int = 50) -> [AMEDiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        let n = min(max(0, limit), monitorRing.count)
        return Array(monitorRing.suffix(n))
    }

    private func recordMonitor(_ events: [AMEDiagnosticEvent]) {
        lock.lock()
        monitorRing.append(contentsOf: events)
        if monitorRing.count > monitorCapacity {
            monitorRing.removeFirst(monitorRing.count - monitorCapacity)
        }
        lock.unlock()
    }

    private func handleScheduledFire(_ scheduled: ScheduledMusicalAction) {
        guard case .auroraActionToken(let token, _) = scheduled.command else {
            if case .panicBypass = scheduled.command {
                lock.lock()
                let eng = engine
                lock.unlock()
                eng?.panic()
            }
            return
        }
        guard let record = actionTokens.consume(token) else { return }
        let payload = record.payload
        lock.lock()
        let eng = engine
        let proj = project
        let observers = Array(uiObservers.values)
        lock.unlock()
        guard let eng else { return }

        let ordered = payload.orderedFixtureIDs ?? []
        let selection = Set(ordered)
        _ = executeAuroraAction(
            payload.action,
            controlValue: payload.controlValue ?? 0,
            orderedFixtureIDs: ordered,
            selectedFixtureIDs: selection,
            latencyID: payload.latencyID,
            engine: eng,
            project: proj,
            observers: observers,
            summaryTag: "AME_QUANTIZED"
        )
    }

    /// Single host execution path for immediate **and** quantized AME actions.
    @discardableResult
    private func executeAuroraAction(
        _ action: AuroraAction,
        controlValue: Double,
        orderedFixtureIDs: [UUID],
        selectedFixtureIDs: Set<UUID>,
        latencyID: UUID?,
        engine: LightingEngine,
        project: ShowProject,
        observers: [@Sendable (ShowAction, String) -> Void],
        summaryTag: String
    ) -> AuroraActionExecutionOutcome {
        let executor = makeExecutor(lighting: engine, project: project)
        let ctx = AuroraActionExecutionContext(
            controlValue: controlValue,
            orderedFixtureIDs: orderedFixtureIDs,
            selectedFixtureIDs: selectedFixtureIDs,
            latencyID: latencyID
        )
        let outcome = executor.execute(action, context: ctx)
        switch outcome {
        case .executed:
            if let showAction = action.asShowAction {
                for notify in observers {
                    notify(showAction, "\(summaryTag) \(action.storageKey)")
                }
            } else {
                for notify in observers {
                    notify(.go, "\(summaryTag) \(action.storageKey)")
                }
            }
        case .unsupported:
            for notify in observers {
                notify(.stop, "AME_UNSUPPORTED \(action.storageKey)")
            }
        case .partial:
            if let showAction = action.asShowAction {
                applyLive(
                    showAction,
                    engine: engine,
                    project: project,
                    control: MIDIControlValue(normalized: controlValue, isTrigger: false),
                    selection: selectedFixtureIDs,
                    orderedSelection: orderedFixtureIDs
                )
                for notify in observers {
                    notify(showAction, "\(summaryTag)_PARTIAL \(action.storageKey)")
                }
            } else {
                for notify in observers {
                    notify(.stop, "AME_PARTIAL \(action.storageKey)")
                }
            }
        }
        return outcome
    }

    private func makeExecutor(lighting: LightingEngine?, project: ShowProject) -> AuroraActionExecutor {
        lock.lock()
        let me = musicalEngine
        let host = hostCallbacks
        lock.unlock()
        return AuroraActionExecutor(
            lighting: lighting,
            musical: me,
            ame: ameRuntime,
            project: project,
            host: host
        )
    }

    /// AME performance mode: `edit` skips evaluation; `dryRun` evaluates without executing; `armed` executes.
    /// Leaving armed unwinds live holds with executable deactivation (via `setPerformanceMode` batch).
    var amePerformanceMode: AMEPerformanceMode {
        get { ameRuntime.performanceMode }
        set {
            // Always use batch-returning API so live release emissions cannot be discarded.
            let batch = ameRuntime.setPerformanceMode(newValue)
            applyAMEReleaseBatch(batch)
        }
    }

    /// Register a UI/diagnostics observer. Returns a token for later removal.
    /// Multiple observers fire for each live action; none overwrites another.
    @discardableResult
    func addUIObserver(_ handler: @escaping @Sendable (ShowAction, String) -> Void) -> ControlEventObserverToken {
        let id = UUID()
        lock.lock()
        uiObservers[id] = handler
        lock.unlock()
        return ControlEventObserverToken(id: id)
    }

    func removeUIObserver(_ token: ControlEventObserverToken) {
        lock.lock()
        uiObservers[token.id] = nil
        lock.unlock()
    }

    /// Compatibility: clears existing observers and installs a single handler.
    /// Prefer `addUIObserver` so MIDI status and show-control both stay subscribed.
    func setUINotify(_ handler: @escaping @Sendable (ShowAction, String) -> Void) {
        lock.lock()
        uiObservers = [UUID(): handler]
        lock.unlock()
    }

    func updateMappings(_ mappings: [MIDIMapping], project: ShowProject) {
        lock.lock()
        let previousAME = self.project.ame
        let previousMaps = self.mappings
        let previousRules = self.rules
        self.mappings = mappings
        self.rules = project.midiRules
        self.project = project
        lock.unlock()
        // Only treat as AME document replacement when AME payload actually changed.
        // Unrelated project edits must not clear live held/toggle state.
        if previousAME != project.ame {
            let batch = ameRuntime.updateDocument(project.ame)
            applyAMEReleaseBatch(batch)
        } else if previousMaps != mappings || previousRules != project.midiRules {
            // Legacy mapping/rule-only change — no AME ephemeral wipe.
        }
    }

    /// Explicit AME document apply (always updates runtime document; release if changed).
    func updateAMEConfiguration(_ ame: AMEProjectDocument) {
        lock.lock()
        project.ame = ame
        lock.unlock()
        let batch = ameRuntime.updateDocument(ame)
        applyAMEReleaseBatch(batch)
    }

    /// Inventory-resolved binding IDs for AME performance matching.
    func setResolvedSourceBindings(_ map: [UUID: Set<String>]) {
        ameRuntime.setResolvedSourceBindings(map)
    }

    func updateSongSectionContext(_ label: String?) {
        lock.lock()
        songSectionLabel = label
        lock.unlock()
    }

    /// Structural show context for AME scope evaluation (song/section UUIDs).
    /// Prefer `transitionAMEShowContext` for full Phase H lifecycle (onExit/onEnter + sequence reset).
    func updateAMEShowContext(songID: UUID?, sectionID: UUID?, sectionLabel: String? = nil) {
        lock.lock()
        activeSongID = songID
        activeSectionID = sectionID
        if let sectionLabel {
            songSectionLabel = sectionLabel
        }
        lock.unlock()
        let batch = ameRuntime.updateShowContext(
            AMEShowContext(activeSongID: songID, activeSectionID: sectionID)
        )
        applyAMEReleaseBatch(batch)
    }

    /// Atomic section/song transition (Phase H): exit actions → context → sequence reset → enter actions.
    @discardableResult
    func transitionAMEShowContext(
        songID: UUID?,
        sectionID: UUID?,
        sectionLabel: String? = nil
    ) -> AMESectionTransition.Result {
        lock.lock()
        let prevSong = activeSongID
        let prevSection = activeSectionID
        let proj = project
        let eng = engine
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let observers = Array(uiObservers.values)
        lock.unlock()

        let plan = AMESectionTransition.plan(
            .init(
                previousSongID: prevSong,
                previousSectionID: prevSection,
                nextSongID: songID,
                nextSectionID: sectionID,
                project: proj
            )
        )

        // 1. Exit actions (unified executor; skip lighting when engine missing)
        if let eng {
            for action in plan.exitActions {
                _ = executeAuroraAction(
                    action,
                    controlValue: 0,
                    orderedFixtureIDs: ordered,
                    selectedFixtureIDs: selection,
                    latencyID: nil,
                    engine: eng,
                    project: proj,
                    observers: observers,
                    summaryTag: "AME_SECTION_EXIT"
                )
            }
        }

        // 2–3. Context + sequence resets + section membership for mapping sets
        lock.lock()
        activeSongID = songID
        activeSectionID = sectionID
        if let sectionLabel {
            songSectionLabel = sectionLabel
        } else if let name = plan.enterSectionName {
            songSectionLabel = name
        }
        lock.unlock()
        if let sectionID,
           let section = proj.songs.flatMap(\.sections).first(where: { $0.id == sectionID }) {
            ameRuntime.updateSectionMembership(
                localMappingIDs: section.localMappingIDs,
                mappingSetIDs: section.mappingSetIDs
            )
        } else {
            ameRuntime.updateSectionMembership(localMappingIDs: [], mappingSetIDs: [])
        }
        let heldBatch = ameRuntime.updateShowContext(plan.nextContext)
        applyAMEReleaseBatch(heldBatch)

        // 4. Enter actions
        if let eng {
            for action in plan.enterActions {
                _ = executeAuroraAction(
                    action,
                    controlValue: 0,
                    orderedFixtureIDs: ordered,
                    selectedFixtureIDs: selection,
                    latencyID: nil,
                    engine: eng,
                    project: proj,
                    observers: observers,
                    summaryTag: "AME_SECTION_ENTER"
                )
            }
        }

        // Musical show-context only — never overwrite project defaults with song metadata.
        lock.lock()
        let me = musicalEngine
        lock.unlock()
        if let me {
            let defaults = AMESectionTransition.musicalDefaults(forSongID: songID, project: proj)
            me.setShowContext(
                ShowMusicalContext(
                    activeSongID: songID,
                    activeSectionID: sectionID,
                    songDefaultTempoBPM: defaults.tempoBPM,
                    songDefaultMeter: defaults.meter.flatMap { try? MusicalMeterBridge.musical(from: $0) }
                )
            )
        }

        return plan
    }

    func updateAMETiming(_ timing: AMETimingSnapshot) {
        lock.lock()
        ameTiming = timing
        lock.unlock()
        ameRuntime.updateTiming(timing)
    }

    /// Release held AME gates (panic / disconnect / MIDI disable) and execute snapshotted release actions.
    @discardableResult
    func releaseAMEHeldState() -> AMEHeldReleaseBatch {
        let batch = ameRuntime.releaseAllHeld(reason: .releaseAll)
        applyAMEReleaseBatch(batch)
        return batch
    }

    /// Apply AME emissions that should execute on the live control plane.
    /// Quantized emissions (Phase G) are scheduled through Musical Engine when attached.
    private func applyAMEEmissions(
        _ emissions: [AMEActionEmission],
        engine: LightingEngine,
        project: ShowProject,
        selection: Set<UUID>,
        ordered: [UUID],
        observers: [@Sendable (ShowAction, String) -> Void],
        summaryPrefix: String
    ) -> Bool {
        var any = false
        lock.lock()
        let me = musicalEngine
        lock.unlock()

        for emission in emissions {
            guard emission.shouldExecute, emission.isLiveSupported else {
                if !emission.isLiveSupported {
                    for notify in observers {
                        notify(.stop, "AME_UNSUPPORTED \(emission.action.storageKey) \(summaryPrefix)")
                    }
                }
                continue
            }

            // Phase G: schedule quantized non-safety emissions.
            if AMEQuantizationBridge.shouldSchedule(emission), let me {
                do {
                    let boundary = AMEQuantizationBridge.musicalBoundary(from: emission.quantizeBoundary)
                    let policy = AMEQuantizationBridge.failurePolicy(from: emission.quantizationFailurePolicy)
                    let scheduled = try actionTokens.schedulePayload(
                        for: emission.action,
                        targetBoundary: boundary,
                        origin: .ameMapping(emission.mappingID),
                        failurePolicy: policy,
                        controlValue: emission.controlValue,
                        latencyID: emission.latencyID,
                        ingressHostTime: emission.ingressHostTime,
                        mappingID: emission.mappingID,
                        orderedFixtureIDs: ordered
                    )
                    let result = me.schedule(scheduled)
                    switch result {
                    case .accepted:
                        any = true
                        for notify in observers {
                            notify(.go, "AME_SCHEDULED \(emission.action.storageKey) \(summaryPrefix)")
                        }
                    case .rejectedQueueFull, .rejectedInvalid:
                        if case .auroraActionToken(let token, _) = scheduled.command {
                            _ = actionTokens.consume(token)
                        }
                        for notify in observers {
                            notify(.stop, "AME_SCHEDULE_REJECT \(emission.action.storageKey) \(summaryPrefix)")
                        }
                    }
                } catch {
                    for notify in observers {
                        notify(.stop, "AME_SCHEDULE_ERR \(emission.action.storageKey)")
                    }
                }
                continue
            }

            // Immediate path: same generalized executor as quantized fires.
            let tag = emission.isRelease ? "AME_RELEASE" : "AME"
            let outcome = executeAuroraAction(
                emission.action,
                controlValue: emission.controlValue,
                orderedFixtureIDs: ordered,
                selectedFixtureIDs: selection,
                latencyID: emission.latencyID,
                engine: engine,
                project: project,
                observers: observers,
                summaryTag: "\(tag) \(summaryPrefix)"
            )
            // Only true execution counts as AME-fired (suppresses legacy). Unsupported no-ops do not.
            switch outcome {
            case .executed, .partial:
                any = true
            case .unsupported:
                break
            }
        }
        return any
    }

    private func applyAMEReleaseBatch(_ batch: AMEHeldReleaseBatch) {
        guard !batch.emissions.isEmpty else { return }
        lock.lock()
        let eng = engine
        let proj = project
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let observers = Array(uiObservers.values)
        lock.unlock()
        guard let eng else { return }
        _ = applyAMEEmissions(
            batch.emissions,
            engine: eng,
            project: proj,
            selection: selection,
            ordered: ordered,
            observers: observers,
            summaryPrefix: "held-release"
        )
    }

    func updateSelection(_ fixtureIDs: Set<UUID>) {
        lock.lock()
        selectedFixtureIDs = fixtureIDs
        if orderedFixtureIDs.isEmpty || Set(orderedFixtureIDs) != fixtureIDs {
            orderedFixtureIDs = fixtureIDs.sorted { $0.uuidString < $1.uuidString }
        }
        lock.unlock()
    }

    func updateOrderedSelection(_ ids: [UUID]) {
        lock.lock()
        orderedFixtureIDs = ids
        selectedFixtureIDs = Set(ids)
        lock.unlock()
    }

    /// Called from MIDI callback thread (not MainActor).
    func handleMIDIEvents(_ events: [MIDIEvent]) {
        lock.lock()
        let maps = mappings
        let ruleList = rules
        let section = songSectionLabel
        let eng = engine
        let observers = Array(uiObservers.values)
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let proj = project
        let songID = activeSongID
        let sectionID = activeSectionID
        let timing = ameTiming
        let midiEnabled = eng?.globalShowControl.midiPerformanceEnabled ?? true
        lock.unlock()
        guard let eng else { return }
        if !midiEnabled {
            let batch = ameRuntime.releaseAllHeld(reason: .releaseAll)
            applyAMEReleaseBatch(batch)
            return
        }

        let now = eng.currentResolvedSnapshot().timestamp
        let orderedSel = ordered.isEmpty ? Array(selection) : ordered
        let ameDoc = proj.ame
        let showCtx = AMEShowContext(activeSongID: songID, activeSectionID: sectionID)

        // Ownership dual-path: suppress only claimed legacy IDs (disabled AME still claims).
        let legacyMaps = AMERuntimeOwnership.filterLegacyMappings(maps, document: ameDoc)
        let legacyRules = AMERuntimeOwnership.filterLegacyRules(ruleList, document: ameDoc)

        for event in events {
            // Physical release always admitted (Note Off / note-on vel 0) so holds/behaviors unwind
            // even when the flood limiter is saturated. Use monotonic event timestamp, not wall clock.
            guard safety.allow(event: event, now: event.timestamp) else { continue }
            let control = MIDIActionResolver.controlValue(for: event)

            // --- AME path (Phase D closeout) ---
            var ameFired = false
            if let ameEvent = Self.ameNormalized(from: event) {
                let ameResult = ameRuntime.process(
                    ameEvent,
                    document: ameDoc,
                    context: showCtx,
                    timing: timing
                )
                recordMonitor(ameResult.diagnostics)
                // Apply all emissions (activation + release); unsupported are logged without forging .go.
                ameFired = applyAMEEmissions(
                    ameResult.emissions,
                    engine: eng,
                    project: proj,
                    selection: selection,
                    ordered: ordered,
                    observers: observers,
                    summaryPrefix: event.summary
                )
                if ameRuntime.performanceMode == .dryRun, !ameResult.emissions.isEmpty {
                    for notify in observers {
                        notify(.stop, "AME_DRYRUN \(event.summary) emissions=\(ameResult.emissions.count)")
                    }
                }
            }

            // Advanced MIDI behaviors (drum roles + envelopes).
            var behaviorFired = false
            switch event {
            case .noteOn(let ch, let note, let vel, let src, _):
                let before = eng.midiBehaviors.liveCount
                eng.midiBehaviors.noteOn(
                    note: note,
                    velocity: vel,
                    channel: ch,
                    deviceID: src,
                    songSection: section,
                    time: now,
                    selection: orderedSel
                )
                behaviorFired = eng.midiBehaviors.liveCount > before
                if behaviorFired {
                    for notify in observers {
                        notify(.go, "BEHAVIOR note \(note) \(event.summary)")
                    }
                }
            case .noteOff(let ch, let note, _, let src, _):
                eng.midiBehaviors.noteOff(note: note, channel: ch, deviceID: src, time: now)
            default:
                break
            }

            // --- Legacy path (unclaimed only) ---
            var actions = MIDIActionResolver.matchAll(event: event, mappings: legacyMaps)
            actions.append(contentsOf: MIDIActionResolver.matchRules(
                event: event,
                rules: legacyRules,
                songSection: section
            ))
            if actions.isEmpty && !behaviorFired && !ameFired {
                for notify in observers {
                    notify(.stop, "UNMATCHED \(event.summary)") // re-use notify path for log only
                }
                // Don't apply stop — observers filter by summary.
                continue
            }
            for action in actions {
                // Never run panic-disabling MIDI when disabled (already returned).
                applyLive(
                    action,
                    engine: eng,
                    project: proj,
                    control: control,
                    selection: selection,
                    orderedSelection: ordered
                )
                for notify in observers {
                    notify(action, event.summary)
                }
            }
        }
    }

    /// Convert channel-voice MIDIEvent → AME normalized performance event.
    /// Preserves the monotonic ingress timestamp from `MIDIEvent.timestamp` (never re-stamps with wall/callback time).
    static func ameNormalized(from event: MIDIEvent, hostTime: HostTime? = nil) -> AMENormalizedEvent? {
        let ht = hostTime
            ?? HostTime.fromLegacyMonotonicSeconds(event.timestamp)
            ?? HostTime.now() // defensive only
        let usedFallback = hostTime == nil && HostTime.fromLegacyMonotonicSeconds(event.timestamp) == nil
        let type: AMEMIDIMessageType
        switch event.messageTypeKey {
        case "noteOn": type = .noteOn
        case "noteOff": type = .noteOff
        case "cc": type = .cc
        case "programChange": type = .programChange
        case "pitchBend": type = .pitchBend
        case "channelPressure": type = .channelPressure
        case "polyPressure": type = .polyPressure
        default: return nil
        }
        var data1 = event.data1
        var data2 = event.data2
        if case .pitchBend(_, let v14, _, _) = event {
            data1 = UInt8(v14 & 0x7F)
            data2 = UInt8(min(127, v14 >> 7))
        }
        _ = usedFallback // router may log via AME process diagnostics when integrating later
        return AMENormalizedEvent(
            messageType: type,
            channel: event.channel,
            data1: data1,
            data2: data2,
            sourceID: event.sourceID,
            hostTime: ht,
            latencyID: UUID()
        )
    }

    /// Dispatch a show action from any control surface (MIDI/OSC/UI/remote).
    /// Safe from non-MainActor threads (UI-GATE-2).
    func dispatch(
        _ action: ShowAction,
        control: MIDIControlValue? = nil,
        midiValue: UInt8? = nil,
        notifySummary: String? = nil,
        origin: ControlActionOrigin = .localUI
    ) {
        lock.lock()
        lastControlOrigin = origin
        let eng = engine
        let proj = project
        let selection = selectedFixtureIDs
        let ordered = orderedFixtureIDs
        let observers = Array(uiObservers.values)
        lock.unlock()
        guard let eng else { return }

        let resolved: MIDIControlValue?
        if let control {
            resolved = control
        } else if let midiValue {
            resolved = MIDIControlValue(normalized: MIDIActionResolver.ccNormalized(midiValue), isTrigger: false)
        } else {
            resolved = nil
        }

        applyLive(
            action,
            engine: eng,
            project: proj,
            control: resolved,
            selection: selection,
            orderedSelection: ordered
        )

        if let summary = notifySummary {
            for notify in observers {
                notify(action, summary)
            }
        }
    }

    func controlOriginSnapshot() -> ControlActionOrigin {
        lock.lock()
        defer { lock.unlock() }
        return lastControlOrigin
    }

    /// Live actions that must not require MainActor.
    func applyLive(
        _ action: ShowAction,
        engine: LightingEngine,
        project: ShowProject? = nil,
        control: MIDIControlValue? = nil,
        midiValue: UInt8? = nil,
        selection: Set<UUID> = [],
        orderedSelection: [UUID] = []
    ) {
        let proj: ShowProject
        if let project {
            proj = project
        } else {
            lock.lock()
            proj = self.project
            lock.unlock()
        }

        let scalar: Double
        if let control {
            scalar = control.normalized
        } else if let midiValue {
            scalar = MIDIActionResolver.ccNormalized(midiValue)
        } else {
            scalar = 0
        }

        switch action {
        case .go:
            engine.go()
        case .stop:
            engine.stopPlayback()
        case .back:
            engine.back()
        case .fireCue(let id):
            engine.fire(cueID: id)
        case .fireCueIndex(let index):
            if let list = activeCueList(project: proj, engine: engine),
               list.cues.indices.contains(index) {
                engine.fire(cueID: list.cues[index].id)
            }
        case .programmerAttribute(let attr):
            let targets = orderedSelection.isEmpty ? Array(selection) : orderedSelection
            for id in targets {
                engine.programmer.set(fixtureID: id, attribute: attr, value: scalar)
            }
        case .blackout:
            engine.setBlackout(true)
        case .blackoutOff:
            engine.setBlackout(false)
        case .toggleBlackout:
            engine.toggleBlackout()
        case .freeze:
            engine.setFreeze(true)
        case .freezeOff:
            engine.setFreeze(false)
        case .toggleFreeze:
            engine.toggleFreeze()
        case .blind:
            engine.setBlind(true)
        case .blindOff:
            engine.setBlind(false)
        case .toggleBlind:
            engine.toggleBlind()
        case .masterIntensity:
            engine.setMasterIntensity(scalar)
        case .panic:
            engine.panic()
            let batch = ameRuntime.releaseAllHeld(reason: .releaseAll)
            // Deactivation emissions already safe to apply (panic cleared overrides).
            applyAMEReleaseBatch(batch)
        case .clearOverrides:
            engine.clearOverrides()
        case .toggleMIDIPerformance:
            engine.toggleMIDIPerformance()
            if !engine.globalShowControl.midiPerformanceEnabled {
                let batch = ameRuntime.releaseAllHeld(reason: .releaseAll)
                applyAMEReleaseBatch(batch)
            }
        }
    }

    /// Active playback list, falling back to first list only when nothing is loaded.
    private func activeCueList(project: ShowProject, engine: LightingEngine) -> CueList? {
        if let listID = engine.playback.snapshot().listID,
           let list = project.cueLists.first(where: { $0.id == listID }) {
            return list
        }
        return project.cueLists.first
    }
}
