import AuroraModel
import AuroraOutput
import Foundation

/// Real-time lighting engine: fixed-rate tick, cue playback, merge, output flush, snapshots.
public final class LightingEngine: @unchecked Sendable {
    private let output: OutputManager
    private let clock: EngineClock
    private let scheduler = EngineScheduler()
    private let lock = NSLock()

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

    public let playback = PlaybackController()
    public let programmer = Programmer()
    /// Live effects between playback and programmer (PR22).
    public let effects = EffectRunner()
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
    }

    public var globalShowControl: GlobalShowControlState {
        lock.lock(); defer { lock.unlock() }
        return globalControl
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
            processFrame(publishSnapshotAlways: true)
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
        processFrame(publishSnapshotAlways: true)
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
        processFrame(publishSnapshotAlways: true)
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
        reconcileOutputUniverses(for: project)
        playback.updateProject(project)
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
    }

    public func back() {
        playback.back(at: clock.now())
    }

    public func stopPlayback() {
        playback.stop(at: clock.now())
    }

    public func fire(cueID: UUID) {
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
        startedOutput = true

        let period = configurationSnapshot.framePeriod
        scheduler.start(period: period) { [weak self] in
            self?.processFrame(publishSnapshotAlways: false)
        }

        processFrame(publishSnapshotAlways: true)
    }

    public func stop() {
        scheduler.stop()
        if startedOutput {
            output.stopAll()
            startedOutput = false
        }
        lock.lock()
        snapshot.isRunning = false
        lock.unlock()
    }

    /// Synchronous single frame for unit tests.
    public func stepForTesting() {
        processFrame(publishSnapshotAlways: true)
    }

    private func processFrame(publishSnapshotAlways: Bool) {
        let frameStart = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let project = self.project
        let compiled = self.compiledShow
        let cachedIssues = self.cachedResolutionIssues
        let manual = self.manualLook
        let config = self.configuration
        frameIndex &+= 1
        let index = frameIndex
        let time = clock.now()
        let running = scheduler.isRunning
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
        let effectedLook = effects.apply(on: playbackLook, time: time)
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
