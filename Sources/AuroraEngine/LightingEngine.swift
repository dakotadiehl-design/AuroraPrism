import AuroraModel
import AuroraOutput
import Foundation

/// Real-time lighting engine: fixed-rate tick, merge stub, output flush, UI snapshots.
public final class LightingEngine: @unchecked Sendable {
    private let output: OutputManager
    private let clock: EngineClock
    private let scheduler = EngineScheduler()
    private let lock = NSLock()

    private var configuration: EngineConfiguration
    private var project: ShowProject = .empty(name: "Engine")
    private var look: ActiveLook = .empty
    private var frameIndex: UInt64 = 0
    private var snapshot = EngineFrameSnapshot.idle
    private var lastSnapshotPublishTime: TimeInterval = 0
    private var startedOutput = false

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

    public func updateConfiguration(_ configuration: EngineConfiguration) {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
        if isRunning {
            stop()
            try? start()
        }
    }

    /// Rebuilds the engine working set from a show document.
    public func load(project: ShowProject) {
        lock.lock()
        self.project = project
        lock.unlock()

        for universe in project.universes {
            output.ensureUniverse(universe.number, channelCount: Int(universe.channelCount))
        }
    }

    public func setLook(_ look: ActiveLook) {
        lock.lock()
        self.look = look
        lock.unlock()
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

        // Publish an initial frame immediately.
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

    /// Synchronous single frame for unit tests (does not require `start()`).
    public func stepForTesting() {
        processFrame(publishSnapshotAlways: true)
    }

    private func processFrame(publishSnapshotAlways: Bool) {
        lock.lock()
        let project = self.project
        let look = self.look
        let config = self.configuration
        frameIndex &+= 1
        let index = frameIndex
        let time = clock.now()
        let running = scheduler.isRunning
        lock.unlock()

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
            let snap = EngineFrameSnapshot(
                frameIndex: index,
                time: time,
                frameRateHz: config.frameRateHz,
                universeLevels: levels,
                isRunning: running || publishSnapshotAlways
            )
            lock.lock()
            snapshot = snap
            lock.unlock()
        }
    }
}
