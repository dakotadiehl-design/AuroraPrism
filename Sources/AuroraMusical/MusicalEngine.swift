import Foundation

/// Snapshot / timeline observer token.
public struct MusicalEngineObserverToken: Hashable, Sendable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

/// Fired scheduled work delivered to the integration layer (Engine/App resolves tokens).
public typealias MusicalScheduleFireHandler = @Sendable (ScheduledMusicalAction) -> Void
/// Canceled/removed scheduled payloads for ephemeral token cleanup.
public typealias MusicalScheduleCancelHandler = @Sendable ([ScheduledMusicalAction]) -> Void

/// Authoritative Musical Engine runtime (Phase B closeout + Pass 2).
///
/// Lock order when nested: **engine lock → scheduler lock** (never reverse).
/// External callbacks always fire after releasing the engine lock.
public final class MusicalEngine: @unchecked Sendable {
    public static let internalSourceID = "internal"

    private let lock = NSLock()
    private let clock: HostClock
    private var _state = MusicalState.initial
    /// Bounded diagnostic ring (newest at end).
    private var timelineRing: [MusicalTimelineEvent] = []
    private let timelineRingCapacity: Int
    private var tapEstimator = TapTempoEstimator()
    private var clockEstimator: ClockEstimator
    /// Encapsulated: production callers must use `schedule` / `cancelScheduled` (safety cannot bypass).
    private let scheduler: MusicalScheduler

    /// Project/engine baseline used when song metadata is cleared (not hard-coded only 120/4-4).
    private var projectDefaultTempoBPM: Double = 120
    private var projectDefaultMeter: MusicalMeter = .fourFour

    /// Configured internal tempo retained while external clock is active (fallback baseline).
    private struct InternalTimingBaseline: Equatable {
        var tempoBPM: Double
        var provenance: MusicalValueProvenance
    }
    private var internalBaseline: InternalTimingBaseline
    private var observedSPPFromActiveSource = false

    // Anchor-based timeline: tick cadence is resolution only, not elapsed-time authority.
    private var anchorHostTime: HostTime?
    private var anchorQuarterPosition: Double = 0
    private var anchorBPM: Double = 120

    private var stateObservers: [UUID: @Sendable (MusicalState) -> Void] = [:]
    private var timelineObservers: [UUID: @Sendable (MusicalTimelineEvent) -> Void] = [:]
    private var fireHandler: MusicalScheduleFireHandler?
    private var cancelHandler: MusicalScheduleCancelHandler?

    public init(
        clock: HostClock = SystemHostClock(),
        schedulerConfig: MusicalScheduler.Config = .init(),
        timelineRingCapacity: Int = 256,
        projectDefaultTempoBPM: Double = 120,
        projectDefaultMeter: MusicalMeter = .fourFour,
        clockEstimatorConfig: ClockEstimatorConfig = .default
    ) {
        self.clock = clock
        self.scheduler = MusicalScheduler(config: schedulerConfig)
        self.timelineRingCapacity = max(16, timelineRingCapacity)
        self.clockEstimator = ClockEstimator(config: clockEstimatorConfig)
        let bpm = MusicalNumeric.isValidBPM(projectDefaultTempoBPM) ? projectDefaultTempoBPM : 120
        self.projectDefaultTempoBPM = bpm
        self.projectDefaultMeter = projectDefaultMeter
        self.internalBaseline = InternalTimingBaseline(tempoBPM: bpm, provenance: .projectDefault)

        _state.timing.tempoBPM = bpm
        _state.timing.tempoProvenance = .projectDefault
        _state.timing.meter = projectDefaultMeter
        _state.timing.meterProvenance = .projectDefault
        _state.timing.quarterNotePosition = .must(0)
        _state.timing.quarterNotePhase = 0
        _state.timing.barBeat = MusicalMeterMath.barBeat(at: .must(0), meter: projectDefaultMeter)
        _state.timing.timingPolicy = .internalOnly
        _state.timing.activeSourceID = Self.internalSourceID
        _state.timing.selectedSourceID = Self.internalSourceID
        _state.timing.sourceHealth = .healthy
        _state.timing.sync = .unlocked
        _state.timing.activeSourceCapabilities = .internalSource
        _state.timing.fallback = .notApplicable
        _state.timing.positionProvenance = .internalTiming
        anchorBPM = bpm
    }

    // MARK: - Reads

    public var state: MusicalState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public func nextBoundary(_ boundary: MusicalBoundary) -> QuarterNotePosition? {
        lock.lock()
        defer { lock.unlock() }
        return MusicalBoundaryMath.resolve(
            boundary,
            from: _state.timing.quarterNotePosition,
            meter: _state.timing.meter,
            transport: _state.timing.transport
        )
    }

    public func drainTimelineEvents() -> [MusicalTimelineEvent] {
        lock.lock()
        defer { lock.unlock() }
        let e = timelineRing
        timelineRing.removeAll(keepingCapacity: true)
        return e
    }

    // MARK: - Observation

    @discardableResult
    public func addStateObserver(_ handler: @escaping @Sendable (MusicalState) -> Void) -> MusicalEngineObserverToken {
        let token = MusicalEngineObserverToken()
        lock.lock()
        stateObservers[token.id] = handler
        let snap = _state
        lock.unlock()
        handler(snap)
        return token
    }

    public func removeStateObserver(_ token: MusicalEngineObserverToken) {
        lock.lock()
        stateObservers[token.id] = nil
        lock.unlock()
    }

    @discardableResult
    public func addTimelineObserver(_ handler: @escaping @Sendable (MusicalTimelineEvent) -> Void) -> MusicalEngineObserverToken {
        let token = MusicalEngineObserverToken()
        lock.lock()
        timelineObservers[token.id] = handler
        lock.unlock()
        return token
    }

    public func removeTimelineObserver(_ token: MusicalEngineObserverToken) {
        lock.lock()
        timelineObservers[token.id] = nil
        lock.unlock()
    }

    public func setScheduleFireHandler(_ handler: MusicalScheduleFireHandler?) {
        lock.lock()
        fireHandler = handler
        lock.unlock()
    }

    public func setScheduleCancelHandler(_ handler: MusicalScheduleCancelHandler?) {
        lock.lock()
        cancelHandler = handler
        lock.unlock()
    }

    // MARK: - Schedule diagnostics (no public scheduler handle)

    public var pendingScheduledCount: Int { scheduler.pendingCount }

    public func pendingScheduleSnapshotForDiagnostics() -> [MusicalScheduler.PendingEntry] {
        scheduler.snapshotPending
    }

    /// Update project baseline defaults (used when song leaves no metadata).
    /// Idempotent: no-op when tempo and meter already match stored project defaults.
    public func setProjectDefaults(tempoBPM: Double, meter: MusicalMeter) {
        guard MusicalNumeric.isValidBPM(tempoBPM) else { return }
        let now = clock.now()
        lock.lock()
        // Skip when nothing meaningful would change (avoids re-anchor on unrelated project edits).
        if abs(projectDefaultTempoBPM - tempoBPM) < 1e-9, projectDefaultMeter == meter {
            lock.unlock()
            return
        }
        projectDefaultTempoBPM = tempoBPM
        projectDefaultMeter = meter
        if internalBaseline.provenance == .projectDefault || _state.timing.activeSourceID == Self.internalSourceID {
            // Update baseline when project is the configured baseline provenance
            if internalBaseline.provenance == .projectDefault {
                internalBaseline.tempoBPM = tempoBPM
            }
        }
        if _state.timing.tempoProvenance == .projectDefault {
            internalBaseline = InternalTimingBaseline(tempoBPM: tempoBPM, provenance: .projectDefault)
            if isExternalActiveLocked() {
                // Keep displaying external tempo; baseline updated for future fallback
            } else {
                _state.timing.tempoBPM = tempoBPM
                if _state.timing.transport == .running,
                   _state.timing.activeSourceID == Self.internalSourceID {
                    reanchorLocked(at: now, keepPosition: true)
                }
            }
        }
        if _state.timing.meterProvenance == .projectDefault {
            _state.timing.meter = meter
            refreshBarBeatLocked()
        }
        let snap = _state
        let obs = Array(stateObservers.values)
        lock.unlock()
        notifyState(snap, obs)
    }

    /// Register preferred external timing source. Changing selection is an authority transition.
    public func selectExternalTimingSource(_ sourceID: String?) {
        var timeline: [MusicalTimelineEvent] = []
        var fireNow: [ScheduledMusicalAction] = []
        var canceled: [ScheduledMusicalAction] = []
        var releaseHeldNow = false

        lock.lock()
        let oldSelected = _state.timing.selectedSourceID
        guard oldSelected != sourceID else {
            lock.unlock()
            return
        }
        let hadAuthority = hasUsableTimingAuthorityLocked()
        let oldActive = _state.timing.activeSourceID
        _state.timing.selectedSourceID = sourceID
        clockEstimator.resetForNewSource()
        observedSPPFromActiveSource = false

        switch _state.timing.timingPolicy {
        case .internalOnly:
            break
        case .externalMIDI:
            // Retire previous external authority immediately
            _state.timing.activeSourceID = nil
            _state.timing.activeSourceCapabilities = .init()
            _state.timing.sourceHealth = sourceID == nil ? .unavailable : .acquiring
            _state.timing.sync = sourceID == nil ? .unlocked : .acquiring
            anchorHostTime = nil
            if oldActive != nil {
                let ev = MusicalTimelineEvent.sourceChanged(from: oldActive, to: nil)
                appendTimelineLocked(ev)
                timeline.append(ev)
            }
            if hadAuthority {
                let resolution = scheduler.timingBecameUnavailable()
                fireNow = resolution.fireImmediately
                canceled = resolution.canceled
            }
        case .externalPreferredFallback:
            // Fall back to internal while new source acquires
            _state.timing.activeSourceID = Self.internalSourceID
            _state.timing.activeSourceCapabilities = .internalSource
            _state.timing.sourceHealth = .healthy
            _state.timing.fallback = .active
            _state.timing.sync = .fallback
            restoreInternalBaselineTempoLocked(at: clock.now())
            if oldActive != Self.internalSourceID {
                let ev = MusicalTimelineEvent.sourceChanged(from: oldActive, to: Self.internalSourceID)
                appendTimelineLocked(ev)
                timeline.append(ev)
            }
            releaseHeldNow = true
        }

        let pos = _state.timing.quarterNotePosition ?? .must(0)
        let meter = _state.timing.meter
        let transport = _state.timing.transport
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)
        deliverFires(fireNow)
        deliverCancels(canceled)
        if releaseHeldNow {
            deliverFires(scheduler.releaseHeld(position: pos, meter: meter, transport: transport))
        }
    }

    // MARK: - Show context

    public func setShowContext(_ context: ShowMusicalContext) {
        lock.lock()
        _state.context = context
        applySongMetadataLocked(from: context)
        let snap = _state
        let obs = Array(stateObservers.values)
        lock.unlock()
        notifyState(snap, obs)
    }

    /// When provenance is songMetadata and new song omits a field, fall back to project defaults.
    private func applySongMetadataLocked(from context: ShowMusicalContext) {
        // Tempo baseline always tracks song/project for future fallback.
        if let bpm = context.songDefaultTempoBPM, MusicalNumeric.isValidBPM(bpm) {
            internalBaseline = InternalTimingBaseline(tempoBPM: bpm, provenance: .songMetadata)
            if !isExternalActiveLocked() {
                _state.timing.tempoBPM = bpm
                _state.timing.tempoProvenance = .songMetadata
                reanchorLocked(at: clock.now(), keepPosition: true)
            }
        } else if internalBaseline.provenance == .songMetadata || _state.timing.tempoProvenance == .songMetadata {
            internalBaseline = InternalTimingBaseline(tempoBPM: projectDefaultTempoBPM, provenance: .projectDefault)
            if !isExternalActiveLocked() {
                _state.timing.tempoBPM = projectDefaultTempoBPM
                _state.timing.tempoProvenance = .projectDefault
                reanchorLocked(at: clock.now(), keepPosition: true)
            }
        }

        // Meter
        if let meter = context.songDefaultMeter {
            _state.timing.meter = meter
            _state.timing.meterProvenance = .songMetadata
            refreshBarBeatLocked()
        } else if _state.timing.meterProvenance == .songMetadata {
            _state.timing.meter = projectDefaultMeter
            _state.timing.meterProvenance = .projectDefault
            refreshBarBeatLocked()
        }
    }

    // MARK: - Timing policy

    /// Update clock estimator freewheel / lock tuning (e.g. from project AME musical settings).
    /// Idempotent: no-op when config is unchanged.
    public func setClockEstimatorConfig(_ config: ClockEstimatorConfig) {
        lock.lock()
        guard clockEstimator.config != config else {
            lock.unlock()
            return
        }
        clockEstimator.config = config
        lock.unlock()
    }

    public var clockEstimatorConfig: ClockEstimatorConfig {
        lock.lock(); defer { lock.unlock() }
        return clockEstimator.config
    }

    /// Update timing source policy.
    /// Idempotent: no-op when policy is already active (preserves lock/authority/queued work).
    public func setTimingPolicy(_ policy: TimingSourcePolicy) {
        var timeline: [MusicalTimelineEvent] = []
        var fireNow: [ScheduledMusicalAction] = []
        var canceled: [ScheduledMusicalAction] = []
        var releaseHeldNow = false

        lock.lock()
        if _state.timing.timingPolicy == policy {
            lock.unlock()
            return
        }
        let oldActive = _state.timing.activeSourceID
        let hadAuthority = hasUsableTimingAuthorityLocked()
        _state.timing.timingPolicy = policy

        switch policy {
        case .internalOnly:
            _state.timing.selectedSourceID = Self.internalSourceID
            _state.timing.activeSourceID = Self.internalSourceID
            _state.timing.activeSourceCapabilities = .internalSource
            _state.timing.sourceHealth = .healthy
            _state.timing.fallback = .notApplicable
            _state.timing.sync = _state.timing.transport == .running ? .internalRunning : .unlocked
            if _state.timing.transport == .running {
                reanchorLocked(at: clock.now(), keepPosition: true)
            }

        case .externalMIDI:
            // Strict external: no internal authority until Phase C locks a provider.
            // Preserve selectedSourceID if already set by selectExternalTimingSource.
            _state.timing.activeSourceID = nil
            _state.timing.activeSourceCapabilities = .init()
            _state.timing.sourceHealth = .unavailable
            _state.timing.fallback = .notApplicable
            _state.timing.sync = .unlocked
            anchorHostTime = nil

        case .externalPreferredFallback:
            // Option A: before first external lock, internal is active fallback.
            _state.timing.activeSourceID = Self.internalSourceID
            _state.timing.activeSourceCapabilities = .internalSource
            _state.timing.sourceHealth = .healthy
            _state.timing.fallback = .active
            _state.timing.sync = .fallback
            if _state.timing.transport == .running {
                reanchorLocked(at: clock.now(), keepPosition: true)
            }
        }

        let newActive = _state.timing.activeSourceID
        if oldActive != newActive {
            let ev = MusicalTimelineEvent.sourceChanged(from: oldActive, to: newActive)
            appendTimelineLocked(ev)
            timeline.append(ev)
        }

        let hasAuthority = hasUsableTimingAuthorityLocked()
        if hadAuthority && !hasAuthority {
            let resolution = scheduler.timingBecameUnavailable()
            fireNow = resolution.fireImmediately
            canceled = resolution.canceled
        } else if !hadAuthority && hasAuthority {
            releaseHeldNow = true
        }

        let pos = _state.timing.quarterNotePosition ?? .must(0)
        let meter = _state.timing.meter
        let transport = _state.timing.transport
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)
        deliverFires(fireNow)
        deliverCancels(canceled)
        if releaseHeldNow {
            let released = scheduler.releaseHeld(position: pos, meter: meter, transport: transport)
            deliverFires(released)
        }
    }

    // MARK: - Tempo / meter

    public func setTempoBPM(_ bpm: Double, provenance: MusicalValueProvenance = .user) {
        guard MusicalNumeric.isValidBPM(bpm) else { return }
        lock.lock()
        // Always update internal baseline for non-external provenance.
        if provenance != .midiClock && provenance != .freewheel {
            internalBaseline = InternalTimingBaseline(tempoBPM: bpm, provenance: provenance)
        }
        if isExternalActiveLocked() && provenance != .midiClock {
            // Keep displaying external tempo; baseline stored for fallback.
        } else {
            _state.timing.tempoBPM = bpm
            _state.timing.tempoProvenance = provenance
            reanchorLocked(at: clock.now(), keepPosition: true)
        }
        let snap = _state
        let obs = Array(stateObservers.values)
        lock.unlock()
        notifyState(snap, obs)
    }

    public func setMeter(_ meter: MusicalMeter, provenance: MusicalValueProvenance = .user) {
        lock.lock()
        _state.timing.meter = meter
        _state.timing.meterProvenance = provenance
        refreshBarBeatLocked()
        let snap = _state
        let obs = Array(stateObservers.values)
        lock.unlock()
        notifyState(snap, obs)
    }

    // MARK: - Transport (host-time aware)

    /// Manual UI start: resets to origin. Prefer `receiveTransportStart` for MIDI Start.
    public func startTransport() {
        startTransport(at: clock.now(), resetToOrigin: true, emitStarted: true)
    }

    /// Manual continue from current position.
    public func continueTransport() {
        continueTransport(at: clock.now())
    }

    public func stopTransport(applyFailurePolicies: Bool = true) {
        stopTransport(at: clock.now(), applyFailurePolicies: applyFailurePolicies)
    }

    public func seek(to position: QuarterNotePosition) {
        reposition(
            to: position,
            at: clock.now(),
            provenance: .user,
            reanchor: true
        )
    }

    private func startTransport(at hostTime: HostTime, resetToOrigin: Bool, emitStarted: Bool) {
        var timeline: [MusicalTimelineEvent] = []
        var fireNow: [ScheduledMusicalAction] = []
        lock.lock()

        let wasRunning = _state.timing.transport == .running
        if wasRunning && !resetToOrigin {
            // Idempotent continue-like no-op for startFromOrigin only when already running without reset
        }

        if resetToOrigin {
            let oldPos = _state.timing.quarterNotePosition
            _state.timing.transport = .running
            applyPositionLocked(.must(0), provenance: .internalTiming)
            reanchorLocked(at: hostTime, position: 0)
            if emitStarted {
                if !wasRunning || resetToOrigin {
                    appendTimelineLocked(.started)
                    timeline.append(.started)
                }
                let jumped = MusicalTimelineEvent.positionJumped(old: oldPos, new: .must(0))
                appendTimelineLocked(jumped)
                timeline.append(jumped)
            }
        } else {
            _state.timing.transport = .running
            reanchorLocked(at: hostTime, keepPosition: true)
            if emitStarted {
                appendTimelineLocked(.started)
                timeline.append(.started)
            }
        }

        updateSyncForActiveSourceLocked()
        let pos = _state.timing.quarterNotePosition ?? .must(0)
        let meter = _state.timing.meter
        let transport = _state.timing.transport
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()

        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)

        fireNow.append(contentsOf: scheduler.releaseHeld(position: pos, meter: meter, transport: transport))
        fireNow.append(contentsOf: scheduler.harvestDue(at: pos))
        deliverFires(fireNow)
    }

    private func continueTransport(at hostTime: HostTime) {
        var timeline: [MusicalTimelineEvent] = []
        lock.lock()
        if _state.timing.transport == .running {
            // Idempotent: already running
            lock.unlock()
            return
        }
        _state.timing.transport = .running
        reanchorLocked(at: hostTime, keepPosition: true)
        updateSyncForActiveSourceLocked()
        appendTimelineLocked(.continued)
        timeline.append(.continued)
        let pos = _state.timing.quarterNotePosition ?? .must(0)
        let meter = _state.timing.meter
        let transport = _state.timing.transport
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)
        let released = scheduler.releaseHeld(position: pos, meter: meter, transport: transport)
        deliverFires(released)
    }

    private func stopTransport(at hostTime: HostTime, applyFailurePolicies: Bool) {
        _ = hostTime
        var timeline: [MusicalTimelineEvent] = []
        lock.lock()
        if _state.timing.transport == .stopped {
            lock.unlock()
            return // idempotent
        }
        _state.timing.transport = .stopped
        updateSyncForActiveSourceLocked()
        anchorHostTime = nil
        appendTimelineLocked(.stopped)
        timeline.append(.stopped)
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)

        if applyFailurePolicies {
            let resolution = scheduler.timingBecameUnavailable()
            deliverFires(resolution.fireImmediately)
            deliverCancels(resolution.canceled)
        }
    }

    // MARK: - Tap

    @discardableResult
    public func tapTempo(at hostTime: HostTime? = nil) -> Double? {
        let t = (hostTime ?? clock.now()).seconds
        lock.lock()
        let bpm = tapEstimator.tap(at: t)
        if let bpm {
            internalBaseline = InternalTimingBaseline(tempoBPM: bpm, provenance: .tapTempo)
            if !isExternalActiveLocked() {
                _state.timing.tempoBPM = bpm
                _state.timing.tempoProvenance = .tapTempo
                reanchorLocked(at: hostTime ?? clock.now(), keepPosition: true)
            }
        }
        let snap = _state
        let obs = Array(stateObservers.values)
        lock.unlock()
        notifyState(snap, obs)
        return bpm
    }

    public func resetTapTempo() {
        lock.lock()
        tapEstimator.reset()
        lock.unlock()
    }

    // MARK: - Scheduling (linearized with engine lock)

    @discardableResult
    public func schedule(_ action: ScheduledMusicalAction) -> ScheduleEnqueueResult {
        // Safety: always fire synchronously; never queue; never depend on capacity/tick.
        if action.isSafetyCritical {
            deliverFires([action])
            return .accepted(action.id)
        }

        // `.immediate` is wall-clock/API-immediate: no musical timing dependency.
        if action.targetBoundary.isImmediate {
            deliverFires([action])
            return .accepted(action.id)
        }

        lock.lock()
        let transport = _state.timing.transport
        let position = _state.timing.quarterNotePosition
        let meter = _state.timing.meter
        let timingUsable = hasUsableTimingAuthorityLocked() && transport == .running

        if !timingUsable {
            switch action.failurePolicy {
            case .cancel:
                lock.unlock()
                return .rejectedInvalid
            case .executeImmediately:
                lock.unlock()
                deliverFires([action])
                return .accepted(action.id)
            case .holdUntilTimingAvailable:
                let r = scheduler.enqueue(action, targetPosition: nil, hold: true)
                lock.unlock()
                return r
            }
        }

        guard let target = MusicalBoundaryMath.resolve(
            action.targetBoundary,
            from: position,
            meter: meter,
            transport: transport
        ) else {
            switch action.failurePolicy {
            case .cancel:
                lock.unlock()
                return .rejectedInvalid
            case .executeImmediately:
                lock.unlock()
                deliverFires([action])
                return .accepted(action.id)
            case .holdUntilTimingAvailable:
                let r = scheduler.enqueue(action, targetPosition: nil, hold: true)
                lock.unlock()
                return r
            }
        }
        let result = scheduler.enqueue(action, targetPosition: target, hold: false)
        lock.unlock()
        return result
    }

    @discardableResult
    public func cancelScheduled(id: UUID) -> ScheduledMusicalAction? {
        let removed = scheduler.cancel(id: id)
        if let removed {
            deliverCancels([removed])
        }
        return removed
    }

    @discardableResult
    public func cancelAllScheduled() -> [ScheduledMusicalAction] {
        let removed = scheduler.cancelAll()
        deliverCancels(removed)
        return removed
    }

    // MARK: - Tick (anchor-based)

    /// Refresh snapshot from host clock. Elapsed musical time is anchor-based (not tick-dt integration).
    /// Also evaluates external clock freewheel/loss when active source is external.
    public func tick(now hostTime: HostTime? = nil) {
        let now = hostTime ?? clock.now()
        var timeline: [MusicalTimelineEvent] = []
        var fireNow: [ScheduledMusicalAction] = []
        var canceled: [ScheduledMusicalAction] = []
        var releaseHeldNow = false

        lock.lock()
        guard _state.timing.transport == .running else {
            lock.unlock()
            return
        }

        let active = _state.timing.activeSourceID
        if active == Self.internalSourceID {
            advanceFromAnchorLocked(at: now, provenance: .internalTiming)
            // Preferred mode may still be acquiring external — evaluate acquisition timeout only
            if _state.timing.timingPolicy == .externalPreferredFallback,
               let selected = _state.timing.selectedSourceID, selected != Self.internalSourceID {
                clockEstimator.evaluateDropout(at: now)
            }
        } else if let active, active != Self.internalSourceID {
            let prevSync = clockEstimator.sync
            clockEstimator.evaluateDropout(at: now)
            applyExternalEstimatorSyncLocked(timeline: &timeline, prevSync: prevSync, at: now)
            updatePulseDiagnosticsLocked(at: now)

            if clockEstimator.sync == .freewheeling {
                advanceFromAnchorLocked(at: now, provenance: .freewheel)
            }

            if clockEstimator.sync == .lost {
                handleExternalLostLocked(at: now, timeline: &timeline, fireNow: &fireNow, canceled: &canceled, releaseHeldNow: &releaseHeldNow)
            }
        } else {
            // Strict external, no authority: still run acquisition timeout on estimator if selected
            if _state.timing.selectedSourceID != nil {
                clockEstimator.evaluateDropout(at: now)
            }
            updatePulseDiagnosticsLocked(at: now)
        }

        let pos = _state.timing.quarterNotePosition ?? .must(0)
        let meter = _state.timing.meter
        let transport = _state.timing.transport
        let snap = _state
        let obs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, obs)
        notifyTimeline(timeline, timeObs)
        deliverFires(fireNow)
        deliverCancels(canceled)
        if releaseHeldNow {
            deliverFires(scheduler.releaseHeld(position: pos, meter: meter, transport: transport))
        }
        deliverFires(scheduler.harvestDue(at: pos))
    }

    public func replaceTimingForTesting(_ timing: MusicalTimingState) {
        lock.lock()
        _state.timing = timing
        if timing.activeSourceID == Self.internalSourceID, timing.transport == .running {
            reanchorLocked(at: clock.now(), keepPosition: true)
        }
        let snap = _state
        let obs = Array(stateObservers.values)
        lock.unlock()
        notifyState(snap, obs)
    }

    // MARK: - MusicalTimingSink (source-aware; preserves event HostTime)

    public func receiveClockPulse(from sourceID: String, at hostTime: HostTime) {
        var timeline: [MusicalTimelineEvent] = []
        let fireNow: [ScheduledMusicalAction] = []
        let canceled: [ScheduledMusicalAction] = []
        var releaseHeldNow = false

        lock.lock()
        guard acceptsTimingEventLocked(from: sourceID) else {
            lock.unlock()
            return
        }

        let hadAuthority = hasUsableTimingAuthorityLocked()
        let prevSync = clockEstimator.sync
        let prevActive = _state.timing.activeSourceID
        clockEstimator.receivePulse(at: hostTime)

        // Handoff authority only when estimator is usable (locked), not on first pulse.
        if _state.timing.selectedSourceID == sourceID, clockEstimator.sync == .locked {
            if _state.timing.activeSourceID != sourceID {
                _state.timing.activeSourceID = sourceID
                var caps = TimingSourceCapabilities.midiClock
                caps.suppliesSongPosition = observedSPPFromActiveSource
                _state.timing.activeSourceCapabilities = caps
                _state.timing.sourceHealth = .healthy
                _state.timing.sync = .locked
                if _state.timing.timingPolicy == .externalPreferredFallback {
                    _state.timing.fallback = .armed
                }
                if prevActive != sourceID {
                    let ev = MusicalTimelineEvent.sourceChanged(from: prevActive, to: sourceID)
                    appendTimelineLocked(ev)
                    timeline.append(ev)
                }
                // Continuous position; reanchor for freewheel at current pos
                reanchorLocked(at: hostTime, keepPosition: true)
            }
        }

        applyExternalEstimatorSyncLocked(timeline: &timeline, prevSync: prevSync, at: hostTime)

        // Display external tempo only while external is active authority.
        if isExternalActiveLocked(), let bpm = clockEstimator.tempoBPM, MusicalNumeric.isValidBPM(bpm) {
            _state.timing.tempoBPM = bpm
            _state.timing.tempoProvenance = .midiClock
            anchorBPM = bpm
        }

        // Advance position only when external owns authority and transport running.
        if _state.timing.transport == .running,
           _state.timing.activeSourceID == sourceID,
           clockEstimator.sync == .locked || clockEstimator.sync == .freewheeling {
            // While locked: advance by pulse. Freewheel advances via tick anchor.
            if clockEstimator.sync == .locked {
                let cur = _state.timing.quarterNotePosition?.quarters ?? 0
                // Re-lock continuity: never jump backward; do not double-count freewheel gap.
                let newQ = cur + ClockEstimator.quartersPerPulse
                applyPositionLocked(.must(newQ), provenance: .midiClock)
                // Phase must match position (estimator already stepped)
                clockEstimator.alignPhase(to: .must(newQ))
                reanchorLocked(at: hostTime, position: newQ)
            }
        }

        updatePulseDiagnosticsLocked(at: hostTime)

        // Usable authority gained → release held (initial lock or recovery)
        let hasAuthority = hasUsableTimingAuthorityLocked()
        if !hadAuthority && hasAuthority {
            releaseHeldNow = true
        }
        if (prevSync == .freewheeling || prevSync == .lost), clockEstimator.sync == .locked {
            let ev = MusicalTimelineEvent.syncRecovered
            appendTimelineLocked(ev)
            timeline.append(ev)
            releaseHeldNow = true
            // Continuity: reanchor at current position without seeking backward
            reanchorLocked(at: hostTime, keepPosition: true)
        }

        let pos = _state.timing.quarterNotePosition ?? .must(0)
        let meter = _state.timing.meter
        let transport = _state.timing.transport
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)
        deliverFires(fireNow)
        deliverCancels(canceled)
        if releaseHeldNow {
            deliverFires(scheduler.releaseHeld(position: pos, meter: meter, transport: transport))
        }
        deliverFires(scheduler.harvestDue(at: pos))
    }

    public func receiveTransportStart(from sourceID: String, at hostTime: HostTime) {
        lock.lock()
        let ok = acceptsTimingEventLocked(from: sourceID)
        if ok {
            clockEstimator.resetPhaseForStart()
        }
        lock.unlock()
        guard ok else { return }
        startTransport(at: hostTime, resetToOrigin: true, emitStarted: true)
    }

    public func receiveTransportStop(from sourceID: String, at hostTime: HostTime) {
        lock.lock()
        let ok = acceptsTimingEventLocked(from: sourceID)
        lock.unlock()
        guard ok else { return }
        stopTransport(at: hostTime, applyFailurePolicies: true)
    }

    public func receiveTransportContinue(from sourceID: String, at hostTime: HostTime) {
        lock.lock()
        let ok = acceptsTimingEventLocked(from: sourceID)
        lock.unlock()
        guard ok else { return }
        continueTransport(at: hostTime)
    }

    public func receiveSongPosition(
        _ position: QuarterNotePosition,
        from sourceID: String,
        at hostTime: HostTime
    ) {
        lock.lock()
        let ok = acceptsTimingEventLocked(from: sourceID)
        if ok {
            clockEstimator.alignPhase(to: position)
            if _state.timing.selectedSourceID == sourceID {
                observedSPPFromActiveSource = true
                if isExternalActiveLocked() || _state.timing.activeSourceID == sourceID {
                    var caps = _state.timing.activeSourceCapabilities
                    caps.suppliesSongPosition = true
                    caps.supportsSongPositionInput = true
                    _state.timing.activeSourceCapabilities = caps
                }
            }
        }
        lock.unlock()
        guard ok else { return }
        reposition(
            to: position,
            at: hostTime,
            provenance: .midiSongPosition,
            reanchor: true
        )
    }
}

// MARK: - Private helpers

extension MusicalEngine {
    /// Usable musical timing for quantization.
    private func hasUsableTimingAuthorityLocked() -> Bool {
        guard let active = _state.timing.activeSourceID else { return false }
        if active == Self.internalSourceID { return true }
        // External only when locked or freewheeling (not mere acquiring).
        return clockEstimator.sync == .locked || clockEstimator.sync == .freewheeling
    }

    private func isExternalActiveLocked() -> Bool {
        guard let active = _state.timing.activeSourceID else { return false }
        return active != Self.internalSourceID
    }

    private func restoreInternalBaselineTempoLocked(at hostTime: HostTime) {
        _state.timing.tempoBPM = internalBaseline.tempoBPM
        // Provenance shows fallback activation while value is the configured internal baseline.
        _state.timing.tempoProvenance = .fallback
        reanchorLocked(at: hostTime, keepPosition: true)
    }

    private func updatePulseDiagnosticsLocked(at hostTime: HostTime) {
        var ageMs: Double?
        if let last = clockEstimator.lastPulseHostTime, hostTime.nanoseconds >= last.nanoseconds {
            ageMs = Double(hostTime.nanoseconds - last.nanoseconds) / 1_000_000.0
        }
        _state.timing.diagnostics = MusicalTimingDiagnostics(
            estimatedJitterMilliseconds: clockEstimator.estimatedJitterMilliseconds,
            lastPulseAgeMilliseconds: ageMs,
            pulsesReceived: clockEstimator.pulsesReceived,
            lastError: nil
        )
    }

    /// External sink admission: Musical Engine retains selected vs active authority.
    private func acceptsTimingEventLocked(from sourceID: String) -> Bool {
        switch _state.timing.timingPolicy {
        case .internalOnly:
            return false
        case .externalMIDI:
            guard let selected = _state.timing.selectedSourceID, !selected.isEmpty else {
                return false
            }
            return sourceID == selected
        case .externalPreferredFallback:
            if let selected = _state.timing.selectedSourceID, !selected.isEmpty {
                return sourceID == selected
            }
            // No external selected: internal fallback owns timing; ignore external events.
            return false
        }
    }

    private func updateSyncForActiveSourceLocked() {
        if _state.timing.activeSourceID == Self.internalSourceID {
            if _state.timing.timingPolicy == .externalPreferredFallback,
               _state.timing.fallback == .active || _state.timing.fallback == .armed {
                _state.timing.sync = _state.timing.transport == .running ? .fallback : .unlocked
                _state.timing.fallback = .active
            } else if _state.timing.transport == .running {
                _state.timing.sync = .internalRunning
            } else {
                _state.timing.sync = .unlocked
            }
            _state.timing.sourceHealth = .healthy
            _state.timing.activeSourceCapabilities = .internalSource
        } else if let active = _state.timing.activeSourceID, active != Self.internalSourceID {
            _state.timing.activeSourceCapabilities = .midiClock
            switch clockEstimator.sync {
            case .locked:
                _state.timing.sync = .locked
                _state.timing.sourceHealth = .healthy
            case .acquiring:
                _state.timing.sync = .acquiring
                _state.timing.sourceHealth = .acquiring
            case .freewheeling:
                _state.timing.sync = .freewheeling
                _state.timing.sourceHealth = .degraded
            case .lost:
                _state.timing.sync = .lost
                _state.timing.sourceHealth = .lost
            case .unlocked:
                _state.timing.sync = .unlocked
                _state.timing.sourceHealth = .unavailable
            }
        } else if _state.timing.activeSourceID == nil {
            _state.timing.sync = .unlocked
            _state.timing.sourceHealth = .unavailable
        }
    }

    private func advanceFromAnchorLocked(at now: HostTime, provenance: MusicalValueProvenance) {
        guard let anchorH = anchorHostTime, MusicalNumeric.isValidBPM(anchorBPM) else {
            reanchorLocked(at: now, keepPosition: true)
            return
        }
        if now.nanoseconds >= anchorH.nanoseconds {
            let dt = Double(now.nanoseconds - anchorH.nanoseconds) / 1_000_000_000.0
            let newQ = anchorQuarterPosition + dt * (anchorBPM / 60.0)
            applyPositionLocked(.must(newQ), provenance: provenance)
        }
    }

    private func applyExternalEstimatorSyncLocked(
        timeline: inout [MusicalTimelineEvent],
        prevSync: ClockEstimatorSync,
        at hostTime: HostTime
    ) {
        _ = hostTime
        updateSyncForActiveSourceLocked()
        if prevSync == .locked && clockEstimator.sync == .freewheeling {
            let ev = MusicalTimelineEvent.freewheelBegan
            appendTimelineLocked(ev)
            timeline.append(ev)
            // Anchor at last known for freewheel advance
            if let last = clockEstimator.lastPulseHostTime {
                reanchorLocked(at: last, keepPosition: true)
            }
        }
        if prevSync != .lost && clockEstimator.sync == .lost {
            let ev = MusicalTimelineEvent.syncLost
            appendTimelineLocked(ev)
            timeline.append(ev)
        }
    }

    private func handleExternalLostLocked(
        at now: HostTime,
        timeline: inout [MusicalTimelineEvent],
        fireNow: inout [ScheduledMusicalAction],
        canceled: inout [ScheduledMusicalAction],
        releaseHeldNow: inout Bool
    ) {
        let prevActive = _state.timing.activeSourceID
        // Clear pre-dropout lock evidence for reacquisition
        // (consecutiveStable already cleared in estimator when entering lost)
        switch _state.timing.timingPolicy {
        case .externalPreferredFallback:
            _state.timing.activeSourceID = Self.internalSourceID
            _state.timing.fallback = .active
            _state.timing.sync = .fallback
            _state.timing.sourceHealth = .healthy
            _state.timing.activeSourceCapabilities = .internalSource
            restoreInternalBaselineTempoLocked(at: now)
            if prevActive != Self.internalSourceID {
                let ev = MusicalTimelineEvent.sourceChanged(from: prevActive, to: Self.internalSourceID)
                appendTimelineLocked(ev)
                timeline.append(ev)
            }
            let fb = MusicalTimelineEvent.fallbackActivated
            appendTimelineLocked(fb)
            timeline.append(fb)
            releaseHeldNow = true
        case .externalMIDI:
            _state.timing.activeSourceID = nil
            _state.timing.sourceHealth = .lost
            _state.timing.sync = .lost
            _state.timing.activeSourceCapabilities = .init()
            anchorHostTime = nil
            if prevActive != nil {
                let ev = MusicalTimelineEvent.sourceChanged(from: prevActive, to: nil)
                appendTimelineLocked(ev)
                timeline.append(ev)
            }
            let resolution = scheduler.timingBecameUnavailable()
            fireNow.append(contentsOf: resolution.fireImmediately)
            canceled.append(contentsOf: resolution.canceled)
        case .internalOnly:
            break
        }
    }

    private func applyPositionLocked(_ position: QuarterNotePosition, provenance: MusicalValueProvenance) {
        _state.timing.quarterNotePosition = position
        var phase = position.quarters - floor(position.quarters)
        if phase >= 1 { phase = 0 }
        _state.timing.quarterNotePhase = phase
        _state.timing.positionProvenance = provenance
        refreshBarBeatLocked()
    }

    /// Single atomic reposition: position + provenance + jump event + one snapshot.
    private func reposition(
        to position: QuarterNotePosition,
        at hostTime: HostTime,
        provenance: MusicalValueProvenance,
        reanchor: Bool
    ) {
        var timeline: [MusicalTimelineEvent] = []
        lock.lock()
        let old = _state.timing.quarterNotePosition
        applyPositionLocked(position, provenance: provenance)
        if reanchor, _state.timing.transport == .running,
           _state.timing.activeSourceID == Self.internalSourceID {
            reanchorLocked(at: hostTime, position: position.quarters)
        }
        let jumped = MusicalTimelineEvent.positionJumped(old: old, new: position)
        appendTimelineLocked(jumped)
        timeline.append(jumped)
        let snap = _state
        let stateObs = Array(stateObservers.values)
        let timeObs = Array(timelineObservers.values)
        lock.unlock()
        notifyState(snap, stateObs)
        notifyTimeline(timeline, timeObs)
    }

    private func reanchorLocked(at hostTime: HostTime, keepPosition: Bool = false, position: Double? = nil) {
        let pos: Double
        if let position {
            pos = position
        } else if keepPosition {
            pos = _state.timing.quarterNotePosition?.quarters ?? 0
        } else {
            pos = 0
        }
        anchorHostTime = hostTime
        anchorQuarterPosition = pos
        anchorBPM = _state.timing.tempoBPM ?? projectDefaultTempoBPM
    }

    private func refreshBarBeatLocked() {
        if let pos = _state.timing.quarterNotePosition, let meter = _state.timing.meter {
            _state.timing.barBeat = MusicalMeterMath.barBeat(at: pos, meter: meter)
        }
    }

    private func appendTimelineLocked(_ event: MusicalTimelineEvent) {
        timelineRing.append(event)
        if timelineRing.count > timelineRingCapacity {
            timelineRing.removeFirst(timelineRing.count - timelineRingCapacity)
        }
    }

    private func notifyState(_ snap: MusicalState, _ observers: [@Sendable (MusicalState) -> Void]) {
        for o in observers { o(snap) }
    }

    private func notifyTimeline(_ events: [MusicalTimelineEvent], _ observers: [@Sendable (MusicalTimelineEvent) -> Void]) {
        for e in events {
            for o in observers { o(e) }
        }
    }

    private func deliverFires(_ actions: [ScheduledMusicalAction]) {
        guard !actions.isEmpty else { return }
        lock.lock()
        let handler = fireHandler
        lock.unlock()
        for a in actions {
            handler?(a)
        }
    }

    private func deliverCancels(_ actions: [ScheduledMusicalAction]) {
        guard !actions.isEmpty else { return }
        lock.lock()
        let handler = cancelHandler
        lock.unlock()
        handler?(actions)
    }
}

extension MusicalEngine: MusicalTimingSink {}
