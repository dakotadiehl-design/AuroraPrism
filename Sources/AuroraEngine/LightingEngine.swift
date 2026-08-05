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
    private var lastSnapshotPublishTime: TimeInterval = 0
    private var startedOutput = false

    public let playback = PlaybackController()
    public let programmer = Programmer()
    /// Live effects between playback and programmer (PR22).
    public let effects = EffectRunner()
    /// Frame timing samples (PR30).
    public let frameMetrics = FrameMetricsRecorder()

    public init(
        output: OutputManager,
        configuration: EngineConfiguration = .default,
        clock: EngineClock = ContinuousEngineClock()
    ) {
        self.output = output
        self.configuration = configuration
        self.clock = clock
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

        let playbackLook: ActiveLook
        if let manual {
            playbackLook = manual
        } else {
            playbackLook = playback.look(at: time)
        }
        // Layer order: playback → effects → programmer (§7.3 / PR22).
        let effectedLook = effects.apply(on: playbackLook, time: time)
        let look = programmer.apply(onPlayback: effectedLook, compiled: compiled)
        let playbackSnap = playback.snapshot()

        let levels = MergeStub.merge(compiled: compiled, look: look, channelCount: config.channelCount)

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
            lock.lock()
            snapshot = snap
            lock.unlock()
        }

        frameMetrics.record(durationSeconds: CFAbsoluteTimeGetCurrent() - frameStart)
    }
}
