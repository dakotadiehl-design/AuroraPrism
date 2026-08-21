import AuroraDiagnostics
import AuroraModel
import AuroraOutput
import Foundation

/// Real-time lighting engine: fixed-rate tick, cue playback, merge, output flush, snapshots.
///
/// Threading contract (Post-C6 audit):
/// - `lock` protects snapshots, config, project indexes, and small control state.
/// - `frameQueue` serializes the **complete** frame pipeline (evaluate → write → flush → publish).
/// - Scheduler ticks and forced frames (panic / unfreeze / clear / test) all enter via `frameQueue`.
/// - Panic/unfreeze use synchronous `sync` so physical output is updated before return.
/// - After `stop()` returns, no prior frame may still flush (barrier on `frameQueue`).
/// - Playback / Programmer / EffectRunner own their internal locks; they are not whole-frame atomic alone.
public final class LightingEngine: @unchecked Sendable {
    public typealias EffectClockSnapshotProvider = @Sendable (TimeInterval) -> [EffectClockSource: EffectClockSnapshot]
    private let output: OutputManager
    private let clock: EngineClock
    private let scheduler = EngineScheduler()
    private let lock = NSLock()
    /// Serializes complete frame bodies (scheduler + forced frames).
    private let frameQueue = DispatchQueue(
        label: "com.aurora.engine.frames",
        qos: .userInteractive
    )

    private var configuration: EngineConfiguration
    private var project: ShowProject = .empty(name: "Engine")
    /// Immutable runtime indexes + channel write plans (P1-12).
    private var compiledShow: CompiledShow = .empty
    /// Cached validation issues (P1-11) — not recomputed on the 40 Hz path.
    private var cachedResolutionIssues: [ResolutionIssue] = []
    private var manualLook: ActiveLook?
    private var frameIndex: UInt64 = 0
    private var snapshot = EngineFrameSnapshot.idle
    private var resolvedSnapshot = ResolvedShowSnapshot.empty
    /// Semantic look held while freeze is active (matches physical frozenLevels).
    private var frozenPresentationLook: ActiveLook?
    private var lastSnapshotPublishTime: TimeInterval = 0
    private var startedOutput = false
    /// When false, frame bodies no-op (post-stop barrier).
    private var framesEnabled = false

    /// Debug/test: overlapping frame bodies must never exceed 1.
    private let concurrentFrameCounter = ConcurrentFrameCounter()

    public let playback = PlaybackController()
    public let programmer = Programmer()
    /// Live effects between playback and programmer (PR22).
    public let effects = EffectRunner()
    private let effectTiming = EffectTimingCoordinator()
    private let effectPreviewTiming = EffectTimingCoordinator()
    private var effectClockSnapshotProvider: EffectClockSnapshotProvider?
    /// MIDI behavior envelopes (after effects, before programmer) — P0-J.
    public let midiBehaviors = MIDIBehaviorRuntime()
    /// Frame timing samples (PR30).
    public let frameMetrics = FrameMetricsRecorder()
    /// Global Master / Blackout / Freeze / Blind / MIDI enable (P0-I).
    private var globalControl = GlobalShowControlState.default
    /// Held DMX frame while freeze is active (physical + preview presentation).
    private var frozenLevels: [UInt16: [UInt8]]?

    public init(
        output: OutputManager,
        configuration: EngineConfiguration = .default,
        clock: EngineClock = ContinuousEngineClock()
    ) {
        self.output = output
        self.configuration = configuration
        self.clock = clock
        frameQueue.setSpecific(key: Self.frameQueueKey, value: 1)
    }

    /// Peak concurrent frame bodies observed (tests assert == 1).
    public var maxConcurrentFramesObserved: Int {
        concurrentFrameCounter.maxObserved
    }

    public func resetConcurrentFrameStatsForTesting() {
        concurrentFrameCounter.reset()
    }

    public var globalShowControl: GlobalShowControlState {
        lock.lock(); defer { lock.unlock() }
        return globalControl
    }

    public func setEffectClockSnapshotProvider(_ provider: EffectClockSnapshotProvider?) {
        lock.lock()
        effectClockSnapshotProvider = provider
        lock.unlock()
    }

    /// Private, non-output evaluation through the same timing and semantic path
    /// as live frames. This method never mutates the live Effects stack.
    public func evaluateEffectPreview(
        _ effect: EffectInstance,
        time: TimeInterval,
        baseLook: ActiveLook = .empty
    ) -> EffectEvaluationResult {
        lock.lock()
        let distributionContext = effectDistributionContext(for: project)
        lock.unlock()
        let compiled = PrismEffectCompiler.compile(effect, context: distributionContext)
        lock.lock()
        let provider = effectClockSnapshotProvider
        lock.unlock()
        let clocks = provider?(time) ?? [:]
        let samples = effectPreviewTiming.samples(for: [compiled], clocks: clocks, monotonicTime: time)
        return PrismEffectEvaluator.evaluateOrdered(
            baseLook: baseLook,
            context: .init(legacyTime: time, timingSamples: samples),
            effects: [compiled]
        )
    }

    public func setMasterIntensity(_ value: Double) {
        lock.lock()
        globalControl.masterIntensity = min(1, max(0, value))
        // Master changes while frozen update the held frame scaling path on next unfreeze;
        // while frozen we keep held presentation (plan: hold presentation).
        lock.unlock()
    }

    public func setBlackout(_ on: Bool) {
        lock.lock()
        globalControl.blackout = on
        lock.unlock()
    }

    public func toggleBlackout() {
        lock.lock()
        globalControl.blackout.toggle()
        lock.unlock()
    }

    /// Freeze holds physical/preview presentation; playback timeline may continue.
    /// Unfreeze snaps immediately to current resolved state (approved default).
    public func setFreeze(_ on: Bool) {
        lock.lock()
        if on {
            if !globalControl.freeze {
                globalControl.freeze = true
                // Capture current DMX + semantic presentation so Stage and output stay aligned.
                if !snapshot.universeLevels.isEmpty {
                    frozenLevels = snapshot.universeLevels
                }
                if frozenPresentationLook == nil {
                    frozenPresentationLook = resolvedSnapshot.presentationLook
                }
            }
        } else {
            globalControl.freeze = false
            frozenLevels = nil
            frozenPresentationLook = nil
        }
        lock.unlock()
        if !on {
            // Snap: force a frame so output leaves held state immediately.
            runFrame(publishSnapshotAlways: true, wait: true)
        }
    }

    public func toggleFreeze() {
        let next: Bool
        lock.lock()
        next = !globalControl.freeze
        lock.unlock()
        setFreeze(next)
    }

    public func setBlind(_ on: Bool) {
        lock.lock()
        globalControl.blind = on
        lock.unlock()
        programmer.setBlind(on)
    }

    public func toggleBlind() {
        lock.lock()
        globalControl.blind.toggle()
        let on = globalControl.blind
        lock.unlock()
        programmer.setBlind(on)
    }

    public func setMIDIPerformanceEnabled(_ on: Bool) {
        lock.lock()
        globalControl.midiPerformanceEnabled = on
        lock.unlock()
    }

    public func toggleMIDIPerformance() {
        lock.lock()
        globalControl.midiPerformanceEnabled.toggle()
        lock.unlock()
    }

    /// Panic: clear temporary performance state (programmer values, blackout, freeze, blind off).
    public func panic() {
        lock.lock()
        globalControl.blackout = false
        globalControl.freeze = false
        globalControl.blind = false
        globalControl.masterIntensity = 1
        frozenLevels = nil
        frozenPresentationLook = nil
        lock.unlock()
        programmer.clearAll()
        programmer.setBlind(false)
        programmer.setHighlight(false)
        midiBehaviors.panic()
        runFrame(publishSnapshotAlways: true, wait: true)
    }

    /// Clear temporary overrides without full panic (keeps master; clears programmer/highlight/blackout/freeze/blind).
    public func clearOverrides() {
        lock.lock()
        globalControl.blackout = false
        globalControl.freeze = false
        globalControl.blind = false
        frozenLevels = nil
        frozenPresentationLook = nil
        lock.unlock()
        programmer.clearAll()
        programmer.setBlind(false)
        programmer.setHighlight(false)
        midiBehaviors.clear()
        runFrame(publishSnapshotAlways: true, wait: true)
    }

    public var isRunning: Bool { scheduler.isRunning }

    public var configurationSnapshot: EngineConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    public func updateConfiguration(_ configuration: EngineConfiguration) throws {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
        if isRunning {
            stop()
            try start()
        }
    }

    /// Snapshot of the last compiled runtime show (for tests / diagnostics).
    public var compiledShowSnapshot: CompiledShow {
        lock.lock()
        defer { lock.unlock() }
        return compiledShow
    }

    /// Destructive show load: resets playback and reconciles universes.
    /// Use for New / Open / replacing the entire document.
    public func load(project: ShowProject) {
        let compiled = CompiledShow.compile(project)
        let issues = ProjectValidator.validate(project).issues
        lock.lock()
        self.project = project
        self.compiledShow = compiled
        self.cachedResolutionIssues = issues
        lock.unlock()

        reconcileOutputUniverses(for: project)

        midiBehaviors.load(definitions: project.midiBehaviors, drums: project.drumProfiles)
        midiBehaviors.clear()
        effects.setCompilationContext(effectDistributionContext(for: project))
        effects.load(definitions: project.effects)

        // Destructive: always reset runtime playback for a full show replacement.
        if let first = project.cueLists.first {
            playback.load(list: first, project: project)
        } else {
            playback.load(list: nil, project: project)
        }
    }

    /// Non-destructive model update: keeps active playback and stage look.
    /// Use for ordinary document edits (rename, MIDI map, notes, unrelated cues).
    public func updateProject(_ project: ShowProject) {
        let compiled = CompiledShow.compile(project)
        let issues = ProjectValidator.validate(project).issues
        lock.lock()
        self.project = project
        self.compiledShow = compiled
        self.cachedResolutionIssues = issues
        lock.unlock()

        midiBehaviors.load(definitions: project.midiBehaviors, drums: project.drumProfiles)
        effects.setCompilationContext(effectDistributionContext(for: project))
        reconcileOutputUniverses(for: project)
        playback.updateProject(project)
    }

    private func effectDistributionContext(for project: ShowProject) -> EffectDistributionContext {
        let fixtureNumbers = Dictionary(uniqueKeysWithValues: project.fixtures.enumerated().map { ($0.element.id, $0.offset + 1) })
        let universeOrder = Dictionary(uniqueKeysWithValues: project.universes.enumerated().map { ($0.element.id, $0.offset) })
        let addresses = Dictionary(uniqueKeysWithValues: project.fixtures.map { fixture in
            let universe = universeOrder[fixture.universeId] ?? Int.max / 1024
            return (fixture.id, universe * 513 + Int(fixture.address))
        })
        let paletteColors = Dictionary(uniqueKeysWithValues: project.palettes.compactMap { palette -> (UUID, EffectColor)? in
            guard palette.type == .color || palette.type == .general else { return nil }
            let red = palette.values["colorR"] ?? palette.values["red"] ?? 0
            let green = palette.values["colorG"] ?? palette.values["green"] ?? 0
            let blue = palette.values["colorB"] ?? palette.values["blue"] ?? 0
            return (palette.id, EffectColor(red: red, green: green, blue: blue))
        })
        let definitions = Dictionary(uniqueKeysWithValues: project.fixtureDefinitions.map { ($0.id, $0) })
        let elementIDs = Dictionary(uniqueKeysWithValues: project.fixtures.map { fixture in
            (fixture.id, definitions[fixture.definitionId]?.elements.map(\.id) ?? [])
        })
        return EffectDistributionContext(
            stagePlacements: project.stageLayout.fixtures,
            fixtureNumbers: fixtureNumbers,
            dmxAddresses: addresses,
            paletteColors: paletteColors,
            fixtureElementIDs: elementIDs,
            fixtureGroups: Dictionary(uniqueKeysWithValues: project.groups.map { ($0.id, Set($0.fixtureIds)) })
        )
    }

    /// Last validation snapshot from load/update (not frame-rate revalidated).
    public var resolutionIssues: [ResolutionIssue] {
        lock.lock()
        defer { lock.unlock() }
        return cachedResolutionIssues
    }

    private func reconcileOutputUniverses(for project: ShowProject) {
        let live = Set(project.universes.map(\.number))
        output.reconcileUniverses(to: live, blackoutRemoved: true)
        for universe in project.universes {
            output.ensureUniverse(universe.number, channelCount: Int(universe.channelCount))
        }
        output.setUniverseRoutes(from: project.universes)
    }

    /// Optional override look (tests). When set, ignores playback until cleared.
    public func setLook(_ look: ActiveLook?) {
        lock.lock()
        self.manualLook = look
        lock.unlock()
    }

    public func go() {
        playback.go(at: clock.now())
        PrismLog.notice(.engineCues, "engine.cues.go", "Prism fired GO.")
    }

    public func back() {
        playback.back(at: clock.now())
    }

    public func stopPlayback() {
        playback.stop(at: clock.now())
    }

    /// Fire a cue by ID. Returns whether the cue was found and a transition began.
    @discardableResult
    public func fire(cueID: UUID) -> Bool {
        playback.fire(cueID: cueID, at: clock.now())
    }

    public func loadCueList(_ list: CueList?) {
        lock.lock()
        let project = self.project
        lock.unlock()
        playback.load(list: list, project: project)
    }

    public func currentSnapshot() -> EngineFrameSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    /// Authoritative semantic frame for Stage Preview / diagnostics (Pass-1 A5).
    public func currentResolvedSnapshot() -> ResolvedShowSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return resolvedSnapshot
    }

    public func start() throws {
        guard !isRunning else { return }
        try output.startAll()
        lock.lock()
        startedOutput = true
        framesEnabled = true
        lock.unlock()

        let period = configurationSnapshot.framePeriod
        scheduler.start(period: period) { [weak self] in
            // Async enqueue — never nest sync onto frameQueue from the frame queue itself.
            self?.runFrame(publishSnapshotAlways: false, wait: false)
        }

        runFrame(publishSnapshotAlways: true, wait: true)
    }

    public func stop() {
        // Disable new frames first so any in-flight/enqueued work no-ops after barrier.
        lock.lock()
        framesEnabled = false
        lock.unlock()

        scheduler.stop()

        // Barrier: wait until every previously enqueued frame body finishes.
        frameQueue.sync(flags: .barrier) {}

        lock.lock()
        let wasStarted = startedOutput
        startedOutput = false
        snapshot.isRunning = false
        lock.unlock()

        if wasStarted {
            output.stopAll()
        }
    }

    /// Synchronous single frame for unit tests.
    public func stepForTesting() {
        // Tests may step without start(); temporarily enable frame execution.
        lock.lock()
        let prior = framesEnabled
        framesEnabled = true
        lock.unlock()
        runFrame(publishSnapshotAlways: true, wait: true)
        lock.lock()
        framesEnabled = prior
        lock.unlock()
    }

    // MARK: - Frame entry

    /// All frame work enters here. `wait: true` runs synchronously on the frame queue
    /// (panic/unfreeze). Scheduler uses `wait: false` to avoid blocking the timer thread
    /// when already on the frame path... actually scheduler is a different queue, so either
    /// is fine; async keeps timer responsive if a forced sync frame is in progress.
    private func runFrame(publishSnapshotAlways: Bool, wait: Bool) {
        let body: () -> Void = { [weak self] in
            self?.processFrameBody(publishSnapshotAlways: publishSnapshotAlways)
        }
        if wait {
            // Avoid deadlock if already on frameQueue (should not happen for public API).
            if DispatchQueue.getSpecific(key: Self.frameQueueKey) != nil {
                body()
            } else {
                frameQueue.sync(execute: body)
            }
        } else {
            frameQueue.async(execute: body)
        }
    }

    private static let frameQueueKey = DispatchSpecificKey<UInt8>()

    private func processFrameBody(publishSnapshotAlways: Bool) {
        // After stop, refuse frames. `stepForTesting` temporarily enables framesEnabled.
        lock.lock()
        let allow = framesEnabled
        lock.unlock()
        guard allow else { return }
        _ = publishSnapshotAlways

        concurrentFrameCounter.enter()
        defer { concurrentFrameCounter.leave() }

        let frameStart = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let compiled = self.compiledShow
        let cachedIssues = self.cachedResolutionIssues
        let manual = self.manualLook
        let config = self.configuration
        frameIndex &+= 1
        let index = frameIndex
        let time = clock.now()
        let running = scheduler.isRunning
        let effectClockProvider = effectClockSnapshotProvider
        lock.unlock()

        lock.lock()
        let gctrl = globalControl
        lock.unlock()

        let playbackLook: ActiveLook
        if let manual {
            playbackLook = manual
        } else {
            playbackLook = playback.look(at: time)
        }
        // Layer order: playback → effects → MIDI behaviors → programmer → global (P0-I / P0-J).
        let compiledEffects = effects.compiledSnapshot()
        let effectClocks = effectClockProvider?(time) ?? [:]
        let timingSamples = effectTiming.samples(for: compiledEffects, clocks: effectClocks, monotonicTime: time)
        let effectedLook = effects.apply(
            on: playbackLook,
            context: EffectEvaluationContext(legacyTime: time, timingSamples: timingSamples),
            compiledEffects: compiledEffects
        )
        let midiLook = midiBehaviors.apply(on: effectedLook, time: time)
        // Blind: also force programmer blind when global blind is on.
        if gctrl.blind {
            programmer.setBlind(true)
        }
        let programmed = programmer.apply(onPlayback: midiLook, compiled: compiled)
        let look = GlobalShowControl.applyToLook(programmed, state: gctrl)
        let playbackSnap = playback.snapshot()

        var levels = MergeStub.merge(compiled: compiled, look: look, channelCount: config.channelCount)
        var presentationLook = look

        // Freeze: hold presentation (DMX + semantic) while timeline may advance.
        if gctrl.freeze {
            lock.lock()
            if frozenLevels == nil || frozenLevels?.isEmpty == true {
                frozenLevels = levels
            }
            if frozenPresentationLook == nil {
                frozenPresentationLook = look
            }
            if let held = frozenLevels, !held.isEmpty {
                levels = held
            }
            presentationLook = frozenPresentationLook ?? look
            lock.unlock()
        } else {
            lock.lock()
            frozenLevels = nil
            frozenPresentationLook = nil
            lock.unlock()
        }

        // Re-check enable before physical flush (stop may have raced after we began).
        lock.lock()
        let stillEnabled = framesEnabled
        lock.unlock()
        guard stillEnabled else {
            frameMetrics.record(durationSeconds: CFAbsoluteTimeGetCurrent() - frameStart)
            return
        }

        for (universeNumber, channels) in levels {
            output.ensureUniverse(universeNumber, channelCount: channels.count)
            output.setLevels(universe: universeNumber, values: channels)
        }
        output.flushAll()

        let shouldPublish: Bool
        if publishSnapshotAlways {
            shouldPublish = true
        } else {
            lock.lock()
            let elapsed = time - lastSnapshotPublishTime
            let period = 1.0 / config.snapshotThrottleHz
            shouldPublish = elapsed >= period || lastSnapshotPublishTime == 0
            if shouldPublish {
                lastSnapshotPublishTime = time
            }
            lock.unlock()
        }

        if shouldPublish {
            // Use cached validation — never re-scan project on the frame path (P1-11).
            let snap = EngineFrameSnapshot(
                frameIndex: index,
                time: time,
                frameRateHz: config.frameRateHz,
                universeLevels: levels,
                isRunning: running || publishSnapshotAlways,
                playback: playbackSnap,
                resolutionIssues: cachedIssues
            )
            let resolved = ResolvedShowSnapshot(
                frameIndex: index,
                timestamp: time,
                look: look,
                programmerLook: programmed,
                presentationLook: presentationLook,
                playback: playbackSnap,
                global: gctrl,
                universeLevels: levels
            )
            lock.lock()
            snapshot = snap
            resolvedSnapshot = resolved
            lock.unlock()
        }

        frameMetrics.record(durationSeconds: CFAbsoluteTimeGetCurrent() - frameStart)
    }
}

// MARK: - Concurrent frame counter (testability)

private final class ConcurrentFrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var maxSeen = 0

    var maxObserved: Int {
        lock.lock(); defer { lock.unlock() }
        return maxSeen
    }

    func enter() {
        lock.lock()
        current += 1
        maxSeen = max(maxSeen, current)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        current = max(0, current - 1)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        current = 0
        maxSeen = 0
        lock.unlock()
    }
}
