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

    /// Rebuilds the engine working set from a show document.
    public func load(project: ShowProject) {
        lock.lock()
        self.project = project
        lock.unlock()

        // Drop removed universes after intentional blackout (P0-5).
        let live = Set(project.universes.map(\.number))
        output.reconcileUniverses(to: live, blackoutRemoved: true)
        for universe in project.universes {
            output.ensureUniverse(universe.number, channelCount: Int(universe.channelCount))
        }

        // Keep playback list content in sync when possible.
        if let current = playback.snapshot().listID,
           let list = project.cueLists.first(where: { $0.id == current }) {
            playback.load(list: list, project: project)
        } else if let first = project.cueLists.first {
            playback.load(list: first, project: project)
        } else {
            playback.load(list: nil, project: project)
        }
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
        let look = programmer.apply(onPlayback: effectedLook, project: project)
        let playbackSnap = playback.snapshot()

        let levels = MergeStub.merge(project: project, look: look, channelCount: config.channelCount)

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
            // Surface project reference issues without blocking output (P1-11).
            let issues = project.validateReferences()
            let snap = EngineFrameSnapshot(
                frameIndex: index,
                time: time,
                frameRateHz: config.frameRateHz,
                universeLevels: levels,
                isRunning: running || publishSnapshotAlways,
                playback: playbackSnap,
                resolutionIssues: issues
            )
            lock.lock()
            snapshot = snap
            lock.unlock()
        }

        frameMetrics.record(durationSeconds: CFAbsoluteTimeGetCurrent() - frameStart)
    }
}
