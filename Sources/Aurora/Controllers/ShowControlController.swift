import AuroraCore
import AuroraEngine
import AuroraMIDI
import AuroraModel
import AuroraOutput
import Foundation

/// Engine transport, action dispatch, programmer, song, performance presentation (Stage C).
@MainActor
final class ShowControlController: ObservableObject {
    let engine: LightingEngine
    let songDirector = SongDirector()
    let controlRouter: ControlActionRouter

    @Published private(set) var engineStatus: String = "Engine stopped"
    @Published var songStatus: String = ""
    @Published private(set) var performance: PerformanceSnapshot = .empty

    private var statusTimer: Timer?

    init(output: OutputManager) {
        self.engine = LightingEngine(output: output)
        self.controlRouter = ControlActionRouter(engine: engine)
    }

    func startEngineIfPossible() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            refreshEngineStatus()
        } catch {
            engineStatus = "Engine start failed"
        }
    }

    func stopTimers() {
        statusTimer?.invalidate()
        statusTimer = nil
        engine.stop()
    }

    func startStatusPolling(outputStatus: @escaping () -> String, project: @escaping () -> ShowProject, isDirty: @escaping () -> Bool) {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPresentation(
                    project: project(),
                    isDirty: isDirty(),
                    outputStatusLine: outputStatus()
                )
            }
        }
    }

    func reloadFromProject(_ project: ShowProject, orderedSelection: [UUID]) {
        engine.setLook(nil)
        engine.load(project: project)
        engine.effects.load(definitions: project.effects)
        controlRouter.updateMappings(project.midiMappings, project: project)
        controlRouter.updateOrderedSelection(orderedSelection)
        objectWillChange.send()
    }

    func applyProjectUpdate(_ project: ShowProject, orderedSelection: [UUID]) {
        engine.updateProject(project)
        engine.effects.load(definitions: project.effects)
        controlRouter.updateMappings(project.midiMappings, project: project)
        controlRouter.updateOrderedSelection(orderedSelection)
        objectWillChange.send()
    }

    func go() {
        engine.go()
        refreshEngineStatus()
        objectWillChange.send()
    }

    func back() {
        engine.back()
        refreshEngineStatus()
        objectWillChange.send()
    }

    func stopPlayback() {
        engine.stopPlayback()
        refreshEngineStatus()
        objectWillChange.send()
    }

    func fireCue(id: UUID) {
        engine.fire(cueID: id)
        refreshEngineStatus()
        objectWillChange.send()
    }

    func perform(action: ShowAction, project: ShowProject, orderedSelection: [UUID], midiValue: UInt8? = nil) {
        controlRouter.updateOrderedSelection(orderedSelection)
        controlRouter.updateMappings(project.midiMappings, project: project)
        controlRouter.dispatch(action, midiValue: midiValue)
        refreshEngineStatus()
        objectWillChange.send()
    }

    func commitEffects(to session: DocumentSession) throws {
        let definitions = engine.effects.exportDefinitions()
        try session.perform(SetEffectsCommand(effects: definitions))
    }

    func loadSong(_ song: Song, project: ShowProject) {
        songDirector.load(song: song, project: project, engine: engine)
        songStatus = song.title
        objectWillChange.send()
    }

    func songNext(project: ShowProject) {
        songDirector.next(project: project, engine: engine)
        objectWillChange.send()
    }

    func songPrevious(project: ShowProject) {
        songDirector.previous(project: project, engine: engine)
        objectWillChange.send()
    }

    func resetSong() {
        songDirector.reset()
        songStatus = ""
        objectWillChange.send()
    }

    func refreshEngineStatus() {
        let snap = engine.currentSnapshot()
        let pb = snap.playback
        let cueLabel: String
        if pb.cueIndex >= 0 {
            cueLabel = " · cue \(pb.cueIndex + 1) \(pb.phase.rawValue)"
        } else {
            cueLabel = " · idle"
        }
        if snap.isRunning || engine.isRunning {
            engineStatus = String(
                format: "Engine %.0f Hz · frame %llu%@",
                snap.frameRateHz,
                snap.frameIndex,
                cueLabel
            )
        } else {
            engineStatus = "Engine stopped"
        }
    }

    func refreshPresentation(project: ShowProject, isDirty: Bool, outputStatusLine: String) {
        refreshEngineStatus()
        let song = songDirector.snapshot(project: project)
        performance = PerformanceSnapshot.build(
            project: project,
            isDirty: isDirty,
            engineSnap: engine.currentSnapshot(),
            song: song,
            outputStatusLine: outputStatusLine
        )
        objectWillChange.send()
    }

    /// Adds a show-control presentation observer without replacing MIDI log observers (UI-GATE-1).
    @discardableResult
    func addUIObserver(_ handler: @escaping @Sendable (ShowAction, String) -> Void) -> ControlEventObserverToken {
        controlRouter.addUIObserver(handler)
    }

    /// Compatibility — prefer `addUIObserver`.
    func setUINotify(_ handler: @escaping @Sendable (ShowAction, String) -> Void) {
        controlRouter.setUINotify(handler)
    }
}
