import AuroraCore
import AuroraDiagnostics
import AuroraEngine
import AuroraMIDI
import AuroraModel
import AuroraMusical
import AuroraOutput
import Foundation

/// Engine transport, action dispatch, programmer, song, performance presentation (Stage C).
@MainActor
final class ShowControlController: ObservableObject {
    let engine: LightingEngine
    let songDirector = SongDirector()
    let controlRouter: ControlActionRouter
    /// Shared Musical Engine for AME quantization + show musical context (Phase G/H).
    let musicalEngine = MusicalEngine()
    /// Non-UI high-resolution driver for schedule harvest (audit Wave 1).
    let musicalDriver = MusicalEngineRuntimeDriver()
    /// Routes CoreMIDI System Real-Time / SPP into MusicalEngine (independent of Learn).
    let clockAdapter: MIDIClockTimingAdapter

    @Published private(set) var engineStatus: String = "Engine stopped"
    @Published var songStatus: String = ""
    @Published private(set) var performance: PerformanceSnapshot = .empty
    /// Protocol-neutral observation epoch / revision. Advances only at semantic commits.
    private(set) var authorityEpoch: UInt64 = 1
    private(set) var stateRevision: UInt64 = 0
    var onSemanticCommit: (() -> Void)?

    private var statusTimer: Timer?
    /// Last inventory used for external source binding resolution.
    private var lastMIDIInventory: [MIDISourceIdentity.InventorySource] = []
    /// Last applied Musical Engine project configuration (diff gate for P0-1).
    private var lastAppliedMusicalConfig: MusicalAppliedProjectConfig?
    /// Last show-context snapshot applied (avoid re-layering on every edit).
    private var lastAppliedShowContext: ShowMusicalContext?
    /// Last advertised values at a semantic commit. External MIDI/OSC/AME
    /// actions execute off MainActor, then reconcile against this projection.
    private var lastCommittedRACPProjection: PrismRACPStateSnapshot?

    init(output: OutputManager) {
        self.engine = LightingEngine(output: output)
        self.controlRouter = ControlActionRouter(engine: engine)
        self.controlRouter.attachMusicalEngine(musicalEngine)
        self.clockAdapter = MIDIClockTimingAdapter(sink: musicalEngine)
        self.musicalDriver.setEngine(musicalEngine)
        let effectMusicalEngine = self.musicalEngine
        self.engine.setEffectClockSnapshotProvider { [weak effectMusicalEngine] time in
            guard let state = effectMusicalEngine?.state else { return [:] }
            var clocks: [EffectClockSource: EffectClockSnapshot] = [
                .musicEngine: EffectClockSnapshot(musicalState: state, source: .musicEngine, monotonicTime: time),
                .ame: EffectClockSnapshot(musicalState: state, source: .ame, monotonicTime: time),
            ]
            if let activeSourceID = state.timing.activeSourceID,
               activeSourceID != MusicalEngine.internalSourceID,
               state.timing.timingPolicy != .internalOnly {
                clocks[.midiClock] = EffectClockSnapshot(musicalState: state, source: .midiClock, monotonicTime: time)
            }
            return clocks
        }
        installHostNavigationCallbacks()
    }

    /// Wire authoritative song/section navigation into the AME action executor.
    private func installHostNavigationCallbacks() {
        // Capture weakly; callbacks may run off MainActor (MIDI path).
        controlRouter.setHostCallbacks(AuroraActionHostCallbacks(
            selectSong: { [weak self] songID in
                Self.runOnMainSync {
                    guard let self else { return .unsupported }
                    return self.hostSelectSong(songID)
                }
            },
            enterSection: { [weak self] sectionID in
                Self.runOnMainSync {
                    guard let self else { return .unsupported }
                    return self.hostEnterSection(sectionID)
                }
            },
            nextSection: { [weak self] in
                Self.runOnMainSync {
                    guard let self else { return .unsupported }
                    return self.hostNextSection()
                }
            },
            previousSection: { [weak self] in
                Self.runOnMainSync {
                    guard let self else { return .unsupported }
                    return self.hostPreviousSection()
                }
            }
        ))
    }

    /// Hop to MainActor for SongDirector mutations; safe from MIDI callback threads.
    private static func runOnMainSync<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }

    private func hostSelectSong(_ songID: UUID) -> AuroraActionExecutionOutcome {
        let before = racpStateSnapshot()
        let project = controlRouterProject()
        guard songDirector.selectSong(id: songID, project: project, engine: engine) else {
            return .unsupported
        }
        let section = songDirector.activeSection(project: project)
        enterAMESection(songID: songID, sectionID: section?.id, sectionLabel: section?.name)
        songStatus = project.songs.first(where: { $0.id == songID })?.title ?? ""
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
        return .executed
    }

    private func hostEnterSection(_ sectionID: UUID) -> AuroraActionExecutionOutcome {
        let before = racpStateSnapshot()
        let project = controlRouterProject()
        guard songDirector.enterSection(sectionID: sectionID, project: project) else {
            return .unsupported
        }
        let songID = songDirector.songID
        let section = songDirector.activeSection(project: project)
        enterAMESection(songID: songID, sectionID: section?.id ?? sectionID, sectionLabel: section?.name)
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
        return .executed
    }

    private func hostNextSection() -> AuroraActionExecutionOutcome {
        let before = racpStateSnapshot()
        let project = controlRouterProject()
        guard songDirector.nextSection(project: project) else { return .partial }
        let section = songDirector.activeSection(project: project)
        enterAMESection(
            songID: songDirector.songID,
            sectionID: section?.id,
            sectionLabel: section?.name
        )
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
        return .executed
    }

    private func hostPreviousSection() -> AuroraActionExecutionOutcome {
        let before = racpStateSnapshot()
        let project = controlRouterProject()
        guard songDirector.previousSection(project: project) else { return .partial }
        let section = songDirector.activeSection(project: project)
        enterAMESection(
            songID: songDirector.songID,
            sectionID: section?.id,
            sectionLabel: section?.name
        )
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
        return .executed
    }

    /// Project mirror held by the router (updated on load/apply).
    private func controlRouterProject() -> ShowProject {
        // Router holds the live document copy used for AME; prefer session via performance path.
        // Fall back through a lightweight read: transition uses the same project the router has.
        // ShowControl does not own DocumentSession — callers update router via applyProjectUpdate.
        // Use engine's last-known project via a snapshot on controlRouter is not public;
        // reconstruct from songDirector + empty is insufficient. Expose via updateMappings.
        //
        // Practical approach: keep a local mirror.
        projectMirror
    }

    private var projectMirror: ShowProject = .empty()

    func startEngineIfPossible() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            musicalDriver.start()
            refreshEngineStatus()
            PrismLog.notice(.engineShow, "engine.show.started", "The show engine is running.")
        } catch {
            engineStatus = "Engine start failed"
            PrismLog.error(
                .engineShow,
                "engine.show.start_failed",
                "Prism couldn't start the show engine.",
                technical: String(reflecting: error)
            )
        }
    }

    func stopTimers() {
        statusTimer?.invalidate()
        statusTimer = nil
        musicalDriver.stop()
        engine.stop()
        PrismLog.notice(.engineShow, "engine.show.stopped", "The show engine is stopped.")
    }

    func startStatusPolling(outputStatus: @escaping () -> String, project: @escaping () -> ShowProject, isDirty: @escaping () -> Bool) {
        statusTimer?.invalidate()
        // Presentation only — timing harvest is MusicalEngineRuntimeDriver (not 250ms).
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.controlRouter.refreshAMETimingFromMusicalEngine()
                self?.refreshPresentation(
                    project: project(),
                    isDirty: isDirty(),
                    outputStatusLine: outputStatus()
                )
            }
        }
        musicalDriver.start()
    }

    func reloadFromProject(_ project: ShowProject, orderedSelection: [UUID]) {
        projectMirror = project
        engine.setLook(nil)
        engine.load(project: project)
        engine.effects.load(definitions: project.effects)
        controlRouter.updateMappings(project.midiMappings, project: project)
        controlRouter.updateOrderedSelection(orderedSelection)
        applyMusicalEngineFromProject(project, availableSources: lastMIDIInventory)
        lastCommittedRACPProjection = normalizedRACPProjection()
        objectWillChange.send()
    }

    func applyProjectUpdate(_ project: ShowProject, orderedSelection: [UUID]) {
        projectMirror = project
        engine.updateProject(project)
        engine.effects.load(definitions: project.effects)
        controlRouter.updateMappings(project.midiMappings, project: project)
        controlRouter.updateOrderedSelection(orderedSelection)
        applyMusicalEngineFromProject(project, availableSources: lastMIDIInventory)
        objectWillChange.send()
    }

    /// Update live MIDI inventory used for external source binding resolution.
    func updateMIDIInventory(_ devices: [MIDIDeviceInfo]) {
        lastMIDIInventory = devices.map {
            MIDISourceIdentity.InventorySource(id: $0.id, name: $0.name, manufacturer: $0.manufacturer)
        }
        // Always refresh AME performance binding resolution against inventory.
        refreshResolvedSourceBindings(project: projectMirror, inventory: lastMIDIInventory)
        applyMusicalEngineFromProject(projectMirror, availableSources: lastMIDIInventory)
    }

    /// Apply persisted AME musical settings only when they actually change (P0-1).
    func applyMusicalEngineFromProject(
        _ project: ShowProject,
        availableSources: [MIDISourceIdentity.InventorySource] = []
    ) {
        let settings = project.ame.musicalSettings
        let meter = (try? MusicalMeterBridge.musical(from: settings.defaultMeter)) ?? .fourFour
        let policy: TimingSourcePolicy
        switch settings.timingPolicy {
        case .internalOnly: policy = .internalOnly
        case .externalMIDI: policy = .externalMIDI
        case .externalPreferredFallback: policy = .externalPreferredFallback
        }
        let sourceID = Self.resolveExternalSourceID(
            settings: settings,
            bindings: project.ame.sourceBindings,
            inventory: availableSources
        )
        let desired = MusicalAppliedProjectConfig(
            tempo: settings.defaultTempoBPM,
            meter: meter,
            freewheelSeconds: settings.freewheelSeconds,
            timingPolicy: policy,
            selectedSourceID: sourceID
        )
        let previous = lastAppliedMusicalConfig

        // Production reconciler (unit-tested — do not reimplement these rules in tests).
        MusicalTimingConfigReconciler.applyTransition(
            previous: previous,
            desired: desired,
            to: musicalEngine,
            setPreferredSource: { [weak clockAdapter] id in
                clockAdapter?.setPreferredSourceID(id)
            }
        )

        lastAppliedMusicalConfig = desired
        // Keep Learn enrichment inventory in sync with the host snapshot.
        controlRouter.setSourceInventory(availableSources)
        refreshResolvedSourceBindings(project: project, inventory: availableSources)

        // Show context only when song/section/song defaults change.
        let songID = songDirector.songID
        let sectionID = songDirector.sectionID
        let defaults = AMESectionTransition.musicalDefaults(forSongID: songID, project: project)
        let showCtx = ShowMusicalContext(
            activeSongID: songID,
            activeSectionID: sectionID,
            songDefaultTempoBPM: defaults.tempoBPM,
            songDefaultMeter: defaults.meter.flatMap { try? MusicalMeterBridge.musical(from: $0) }
        )
        if lastAppliedShowContext != showCtx {
            musicalEngine.setShowContext(showCtx)
            lastAppliedShowContext = showCtx
        }

        controlRouter.refreshAMETimingFromMusicalEngine()
    }

    /// Publish inventory-resolved binding IDs for AME performance trigger matching (P1-3).
    private func refreshResolvedSourceBindings(
        project: ShowProject,
        inventory: [MIDISourceIdentity.InventorySource]
    ) {
        var map: [UUID: Set<String>] = [:]
        for binding in project.ame.sourceBindings where binding.enabled {
            switch MIDISourceIdentity.resolve(binding: binding, inventory: inventory) {
            case .resolved(let id):
                map[binding.id] = [id]
            case .ambiguous:
                // Fail closed — empty set present means do not match either endpoint.
                map[binding.id] = []
            case .unresolved:
                // Leave absent so identity/hint fallback still applies for Learn-shaped bindings.
                break
            }
        }
        controlRouter.setResolvedSourceBindings(map)
    }

    /// Resolve persisted external source binding against live inventory → canonical runtime ID.
    static func resolveExternalSourceID(
        settings: MusicalEngineProjectSettings,
        bindings: [MIDISourceBinding],
        inventory: [MIDISourceIdentity.InventorySource]
    ) -> String? {
        guard let bid = settings.selectedExternalSourceBindingID,
              let binding = bindings.first(where: { $0.id == bid })
        else { return nil }
        switch MIDISourceIdentity.resolve(binding: binding, inventory: inventory) {
        case .resolved(let id):
            return id
        case .unresolved, .ambiguous:
            // Do not silently compare display names to canonical ep:/uid: IDs.
            return nil
        }
    }

    /// Authoritative song/section transition for AME + navigation (Wave 4).
    func enterAMESection(songID: UUID?, sectionID: UUID?, sectionLabel: String? = nil) {
        _ = controlRouter.transitionAMEShowContext(
            songID: songID,
            sectionID: sectionID,
            sectionLabel: sectionLabel
        )
        objectWillChange.send()
    }

    func noteAuthoritativeCommit(replacingUniverse: Bool = false) {
        if replacingUniverse {
            authorityEpoch += 1
            stateRevision = 1
        } else {
            stateRevision += 1
        }
        lastCommittedRACPProjection = normalizedRACPProjection()
        onSemanticCommit?()
    }

    /// Called after a router-originated action that bypassed the typed local
    /// methods (MIDI, OSC, or AME). It commits only if advertised state changed.
    func reconcileExternalRACPMutation() {
        let current = normalizedRACPProjection()
        guard let previous = lastCommittedRACPProjection else {
            lastCommittedRACPProjection = current
            return
        }
        guard current != previous else { return }
        refreshSemanticPresentation()
        noteAuthoritativeCommit()
        refreshEngineStatus()
        objectWillChange.send()
    }

    @discardableResult
    func go(origin: ControlActionOrigin = .localUI) -> Bool {
        let before = engine.playback.snapshot()
        controlRouter.dispatch(.go, origin: origin)
        let after = engine.playback.snapshot()
        let advanced = after.cueID != before.cueID || after.cueIndex != before.cueIndex
        refreshSemanticPresentation()
        if advanced { noteAuthoritativeCommit() }
        refreshEngineStatus()
        objectWillChange.send()
        return advanced
    }

    /// Rebuild presentation immediately from the playback controller after a
    /// semantic transport command. The frame snapshot is intentionally
    /// throttled and can still describe the prior cue when an observer reads the
    /// resulting revision.
    private func refreshSemanticPresentation() {
        var engineSnapshot = engine.currentSnapshot()
        engineSnapshot.playback = engine.playback.snapshot()
        engineSnapshot.isRunning = engine.isRunning
        performance = PerformanceSnapshot.build(
            project: projectMirror,
            isDirty: performance.isDirty,
            engineSnap: engineSnapshot,
            song: songDirector.snapshot(project: projectMirror),
            outputStatusLine: performance.outputStatusLine,
            global: engine.globalShowControl
        )
    }

    /// Single authoritative cue projection for control admission and state observation.
    /// This deliberately reads PlaybackController directly; the engine frame
    /// snapshot and SwiftUI presentation snapshot are both throttled views.
    func authoritativeCueState() -> (current: PerformanceCueSummary, next: PerformanceCueSummary) {
        let song = songDirector.snapshot(project: projectMirror)
        return PerformanceCuePresentation.resolveCues(
            project: projectMirror,
            playback: engine.playback.snapshot(),
            song: SongCueResolveContext(
                songID: song.songID,
                entryIndex: song.entryIndex,
                entryCount: song.entryCount,
                currentEntryLabel: song.currentEntryLabel,
                nextEntryLabel: song.nextEntryLabel
            )
        )
    }

    /// Immutable projection consumed by the rACP service. Protocol publication
    /// remains downstream of this authoritative application snapshot.
    func racpStateSnapshot() -> PrismRACPStateSnapshot {
        let cues = authoritativeCueState()
        let playback = engine.playback.snapshot()
        let global = engine.globalShowControl
        return PrismRACPStateSnapshot(
            authorityEpoch: authorityEpoch,
            revision: stateRevision,
            engineRunning: engine.isRunning,
            playbackPhase: playback.phase.rawValue,
            currentCue: cues.current,
            nextCue: cues.next,
            song: songDirector.snapshot(project: projectMirror),
            sectionID: songDirector.sectionID,
            sectionName: songDirector.activeSection(project: projectMirror)?.name,
            grandMaster: global.masterIntensity,
            blackout: global.blackout
        )
    }

    /// Compares only advertised semantic state. Authority metadata is restored
    /// before comparison because it describes the commit rather than its value.
    private func noteCommitIfRACPStateChanged(from before: PrismRACPStateSnapshot) {
        var after = racpStateSnapshot()
        after.authorityEpoch = before.authorityEpoch
        after.revision = before.revision
        guard after != before else { return }
        refreshSemanticPresentation()
        noteAuthoritativeCommit()
        refreshEngineStatus()
    }

    private func normalizedRACPProjection() -> PrismRACPStateSnapshot {
        var projection = racpStateSnapshot()
        projection.authorityEpoch = 0
        projection.revision = 0
        return projection
    }

    @discardableResult
    func back(origin: ControlActionOrigin = .localUI) -> Bool {
        let before = engine.playback.snapshot()
        guard before.cueIndex > 0 else { return false }
        controlRouter.dispatch(.back, origin: origin)
        let changed = engine.playback.snapshot() != before
        refreshSemanticPresentation()
        if changed { noteAuthoritativeCommit() }
        refreshEngineStatus()
        objectWillChange.send()
        return changed
    }

    @discardableResult
    func stopPlayback(origin: ControlActionOrigin = .localUI) -> Bool {
        let before = engine.playback.snapshot()
        controlRouter.dispatch(.stop, origin: origin)
        let changed = engine.playback.snapshot() != before
        refreshSemanticPresentation()
        if changed { noteAuthoritativeCommit() }
        refreshEngineStatus()
        objectWillChange.send()
        return changed
    }

    @discardableResult
    func setMasterIntensity(_ value: Double, origin: ControlActionOrigin = .localUI) -> Bool {
        let before = engine.globalShowControl.masterIntensity
        controlRouter.dispatch(
            .masterIntensity,
            control: MIDIControlValue(normalized: value, isTrigger: false),
            origin: origin
        )
        let changed = engine.globalShowControl.masterIntensity != before
        refreshSemanticPresentation()
        if changed { noteAuthoritativeCommit() }
        objectWillChange.send()
        return changed
    }

    @discardableResult
    func setBlackout(_ enabled: Bool, origin: ControlActionOrigin = .localUI) -> Bool {
        let before = engine.globalShowControl.blackout
        controlRouter.dispatch(
            enabled ? .blackout : .blackoutOff,
            notifySummary: "Blackout",
            origin: origin
        )
        let changed = engine.globalShowControl.blackout != before
        refreshSemanticPresentation()
        if changed { noteAuthoritativeCommit() }
        objectWillChange.send()
        return changed
    }

    @discardableResult
    func toggleBlackout(origin: ControlActionOrigin = .localUI) -> Bool {
        setBlackout(!engine.globalShowControl.blackout, origin: origin)
    }

    // MARK: - Authoritative remote command boundary

    func executeRemoteGo(origin: ControlActionOrigin) -> PrismRACPCommandOutcome {
        go(origin: origin) ? .executed : .noNextCue
    }

    func executeRemoteBack(origin: ControlActionOrigin) -> PrismRACPCommandOutcome {
        guard engine.playback.snapshot().cueIndex > 0 else { return .noPreviousCue }
        return back(origin: origin) ? .executed : .unchanged
    }

    func executeRemoteStop(origin: ControlActionOrigin) -> PrismRACPCommandOutcome {
        stopPlayback(origin: origin) ? .executed : .unchanged
    }

    func executeRemoteGrandMaster(value: Double, origin: ControlActionOrigin) -> PrismRACPCommandOutcome {
        guard value.isFinite, (0 ... 1).contains(value) else { return .invalidValue }
        return setMasterIntensity(value, origin: origin) ? .executed : .unchanged
    }

    func executeRemoteBlackout(enabled: Bool, origin: ControlActionOrigin) -> PrismRACPCommandOutcome {
        setBlackout(enabled, origin: origin) ? .executed : .unchanged
    }

    func executeRemoteSongSelection(id: UUID, origin: ControlActionOrigin) -> PrismRACPCommandOutcome {
        guard projectMirror.songs.contains(where: { $0.id == id }) else { return .invalidTarget }
        guard songDirector.songID != id else { return .unchanged }
        switch controlRouter.dispatchSongSelection(id: id, origin: origin) {
        case .executed:
            return .executed
        case .unsupported, .partial:
            return .unavailable
        }
    }

    @discardableResult
    func fireCue(id: UUID, origin: ControlActionOrigin = .localUI) -> Bool {
        let playback = engine.playback.snapshot()
        guard let listID = playback.listID,
              let list = projectMirror.cueLists.first(where: { $0.id == listID }),
              list.cues.contains(where: { $0.id == id })
        else { return false }
        controlRouter.dispatch(.fireCue(id), origin: origin)
        let applied = engine.playback.snapshot().cueID == id
        guard applied else { return false }
        refreshSemanticPresentation()
        noteAuthoritativeCommit()
        refreshEngineStatus()
        objectWillChange.send()
        return true
    }

    func perform(action: ShowAction, project: ShowProject, orderedSelection: [UUID], midiValue: UInt8? = nil) {
        controlRouter.updateOrderedSelection(orderedSelection)
        controlRouter.updateMappings(project.midiMappings, project: project)
        controlRouter.dispatch(action, midiValue: midiValue)
        reconcileExternalRACPMutation()
        refreshEngineStatus()
        objectWillChange.send()
    }

    func commitEffects(to session: DocumentSession) throws {
        let definitions = engine.effects.exportDefinitions()
        try session.perform(SetEffectsCommand(effects: definitions))
    }

    func loadSong(_ song: Song, project: ShowProject) {
        let before = racpStateSnapshot()
        projectMirror = project
        songDirector.load(song: song, project: project, engine: engine)
        songStatus = song.title
        enterAMESection(
            songID: song.id,
            sectionID: songDirector.sectionID,
            sectionLabel: songDirector.activeSection(project: project)?.name
        )
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
    }

    func songNext(project: ShowProject) {
        let before = racpStateSnapshot()
        projectMirror = project
        songDirector.next(project: project, engine: engine)
        syncAMEContextFromSongDirector(project: project)
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
    }

    func songPrevious(project: ShowProject) {
        let before = racpStateSnapshot()
        projectMirror = project
        songDirector.previous(project: project, engine: engine)
        syncAMEContextFromSongDirector(project: project)
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
    }

    func sectionNext(project: ShowProject) {
        projectMirror = project
        _ = hostNextSection()
    }

    func sectionPrevious(project: ShowProject) {
        projectMirror = project
        _ = hostPreviousSection()
    }

    func resetSong() {
        let before = racpStateSnapshot()
        songDirector.reset()
        songStatus = ""
        enterAMESection(songID: nil, sectionID: nil, sectionLabel: nil)
        noteCommitIfRACPStateChanged(from: before)
        objectWillChange.send()
    }

    /// Keep AME song/section IDs aligned with SongDirector cursor (authoritative section, not always first).
    private func syncAMEContextFromSongDirector(project: ShowProject) {
        guard let songID = songDirector.songID,
              project.songs.contains(where: { $0.id == songID })
        else {
            enterAMESection(songID: nil, sectionID: nil, sectionLabel: nil)
            return
        }
        // If section cursor empty, park on first ordered section.
        if songDirector.sectionID == nil {
            if let song = project.songs.first(where: { $0.id == songID }) {
                let first = song.sections.sorted { $0.order < $1.order }.first
                if let first {
                    _ = songDirector.enterSection(sectionID: first.id, project: project)
                }
            }
        }
        let section = songDirector.activeSection(project: project)
        enterAMESection(songID: songID, sectionID: section?.id, sectionLabel: section?.name)
        songStatus = project.songs.first(where: { $0.id == songID })?.title ?? ""
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
        let previousStatus = engineStatus
        refreshEngineStatus()
        let song = songDirector.snapshot(project: project)
        let next = PerformanceSnapshot.build(
            project: project,
            isDirty: isDirty,
            engineSnap: engine.currentSnapshot(),
            song: song,
            outputStatusLine: outputStatusLine,
            global: engine.globalShowControl
        )
        // Skip publish when nothing visible changed (avoids 4 Hz Settings/shell thrash).
        // frameIndex still advances while engine runs — status bar needs that; Settings
        // tab chrome is isolated from AppModel observation separately.
        guard next != performance || engineStatus != previousStatus else { return }
        performance = next
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
