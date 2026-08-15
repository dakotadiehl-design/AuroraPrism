import AppKit
import AuroraCore
import AuroraEngine
import AuroraFixtureLib
import AuroraMIDI
import AuroraModel
import AuroraDiagnostics
import AuroraOutput
import AuroraRemote
import AuroraUI
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Composition root (Stage C / P1-15). Owns controllers; forwards menu/API facades.
///
/// Views should prefer focused stores (`document`, `showControl`, `output`, …) rather than
/// treating this type as a god-object. `notifyUI()` replaces the old global revision bump.
@MainActor
final class AppModel: ObservableObject {
    // MARK: - Controllers (owned state)

    let document: ProjectController
    let workspace: WorkspaceController
    let showControl: ShowControlController
    let input: InputController
    let output: OutputController
    let remote: RemoteController
    let diagnostics: DiagnosticsController
    let settings: AppSettingsStore
    let autosave = AutosaveController()
    /// UI-03: derived Programmer attribute presentation (projection only).
    let programmerPresentation = ProgrammerPresentationStore()
    /// Unified external-control monitor (P0-K).
    let externalControl = ExternalControlLog()
    /// Process-launch splash (once per app process).
    let launchSplash = LaunchSplashController()

    /// In-process plugin registry (PR29 / P3-4 protocol surfaces).
    let pluginHost = PluginHost()

    private var cancellables = Set<AnyCancellable>()
    private var controlEventObserver: ControlEventObserverToken?

    // MARK: - Compatibility facades (menus / panels still use these names)

    var session: DocumentSession { document.session }
    var layout: WorkspaceLayout {
        get { workspace.layout }
        set { workspace.layout = newValue; notifyUI() }
    }
    var documentURL: URL? { document.documentURL }
    var statusMessage: String {
        get { document.statusMessage }
        set { document.statusMessage = newValue; notifyUI() }
    }
    var engineStatus: String { showControl.engineStatus }
    var midiStatus: String { input.midiStatus }
    var midiHealth: MIDIHealthSnapshot { input.midiHealth }
    var lastMIDIEvent: String { input.lastMIDIEvent }
    var isMIDILearning: Bool { input.isMIDILearning }
    var songStatus: String {
        get { showControl.songStatus }
        set { showControl.songStatus = newValue; notifyUI() }
    }
    var artNetConfig: ArtNetConfig {
        get { output.artNetConfig }
        set { output.artNetConfig = newValue; notifyUI() }
    }
    var sacnConfig: SACNConfig {
        get { output.sacnConfig }
        set { output.sacnConfig = newValue; notifyUI() }
    }
    var outputStatus: String { output.outputStatus }
    var midiLog: [String] { input.midiLog }
    var consoleLog: [String] { diagnostics.consoleLog }
    var oscStatus: String { input.oscStatus }
    var isOSCEnabled: Bool { input.isOSCEnabled }
    var remoteStatus: String { remote.remoteStatus }
    var remoteHost: RemoteHost { remote.remoteHost }
    var remoteWeb: RemoteWebServer? { remote.remoteWeb }
    var engine: LightingEngine { showControl.engine }
    var songDirector: SongDirector { showControl.songDirector }
    var midiLearn: MIDILearnSession { input.midiLearn }
    var rtpMIDI: RTPMIDISession { input.rtpMIDI }
    var performance: PerformanceSnapshot { showControl.performance }

    init(project: ShowProject = .empty(name: "Untitled Show")) {
        let document = ProjectController(project: project)
        let settings = AppSettingsStore()
        let output = OutputController(settings: settings)
        let showControl = ShowControlController(output: output.outputManager)
        let input = InputController()
        let remote = RemoteController()
        let diagnostics = DiagnosticsController()
        let workspace = WorkspaceController()

        self.document = document
        self.output = output
        self.showControl = showControl
        self.input = input
        self.remote = remote
        self.diagnostics = diagnostics
        self.workspace = workspace
        self.settings = settings

        // Cascade child observation so EnvironmentObject AppModel still refreshes UI.
        for publisher in [
            document.objectWillChange,
            workspace.objectWillChange,
            showControl.objectWillChange,
            input.objectWillChange,
            output.objectWillChange,
            remote.objectWillChange,
            diagnostics.objectWillChange,
            settings.objectWillChange,
            programmerPresentation.objectWillChange,
            externalControl.objectWillChange,
            launchSplash.objectWillChange,
        ] as [ObservableObjectPublisher] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] (_: Void) in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        // Structured external-control monitor from unified router (MIDI/UI/remote).
        controlEventObserver = showControl.controlRouter.addUIObserver { [weak self] action, summary in
            Task { @MainActor in
                guard let self else { return }
                let isUnmatched = summary.hasPrefix("UNMATCHED")
                self.externalControl.record(
                    source: "control",
                    event: summary,
                    mapping: action.storageKey,
                    result: isUnmatched ? "no match" : "ok",
                    isError: isUnmatched
                )
            }
        }

        document.onLog = { [weak self] msg in self?.diagnostics.log(msg) }
        document.onProjectModified = { [weak self] in
            guard let self else { return }
            self.applyProjectUpdate()
            self.refreshProgrammerPresentation()
            // CR-05: keep loaded song cursor identity coherent after entry edits.
            self.songDirector.reconcile(project: self.session.project)
        }
        document.onSelectionChanged = { [weak self] snap in
            guard let self else { return }
            self.engine.programmer.setHighlightSelection(snap.fixtureIDs)
            self.showControl.controlRouter.updateOrderedSelection(snap.orderedFixtureIDs)
            self.refreshProgrammerPresentation()
        }

        // —— Launch bootstrap milestones (splash status only; no parallel subsystem) ——
        launchSplash.note(.loadingFixtureLibrary)
        // Seed log from library load
        if !document.statusMessage.isEmpty {
            diagnostics.log(document.statusMessage)
        }
        if document.fixtureLibrary == nil,
           document.statusMessage.localizedCaseInsensitiveContains("failed") {
            launchSplash.markFailed(document.statusMessage)
        }

        launchSplash.note(.startingEngine)
        reloadEngine()
        showControl.startEngineIfPossible()

        launchSplash.note(.startingOutput)
        // UI-08 A1: only start Local DMX if configured device is present and requested.
        if settings.localDMX.requestedEnabled {
            output.setLocalDMXEnabled(true, engineRunning: engine.isRunning) { [weak self] msg in
                self?.diagnostics.log(msg)
            }
        } else {
            output.startLocalDMXIfNeeded()
        }

        launchSplash.note(.startingMIDI)
        // UI-GATE-1: multi-observer — MIDI log and show-control both subscribe; neither replaces the other.
        input.startMIDI(
            router: showControl.controlRouter,
            session: { [weak self] in self?.document.session ?? DocumentSession(project: .empty()) },
            onLog: { [weak self] msg in self?.diagnostics.log(msg, subsystem: .midi) }
        )
        _ = showControl.addUIObserver { [weak self] action, _ in
            Task { @MainActor in
                self?.showControl.refreshEngineStatus()
                if case .programmerAttribute = action {
                    self?.refreshProgrammerPresentation()
                    self?.notifyUI()
                }
            }
        }
        input.applySavedRTPMIDI { [weak self] msg in self?.diagnostics.log(msg, subsystem: .midi) }

        launchSplash.note(.preparingWorkspace)
        showControl.startStatusPolling(
            outputStatus: { [weak self] in
                // PRE-UI-1: re-read driver health each poll (not a stale cached string).
                self?.output.presentationSnapshot().statusLine ?? "Output: Null"
            },
            project: { [weak self] in self?.document.session.project ?? .empty() },
            isDirty: { [weak self] in self?.document.isDirty ?? false }
        )
        output.refreshOutputStatus()
        // PRE-UI-2: app frame-rate preference drives the real engine scheduler.
        applyPreferredFrameRate(settings.preferredFrameRateHz, persist: false)
        autosave.onAutosave = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.performBackgroundAutosave()
            }
        }
        autosave.start()
        // REM-04: restore remote from persisted settings after composition is ready.
        if settings.remoteAccessEnabled {
            applyRemoteFromSettings(enabled: true)
        }
        // DIAG-01: live throttled diagnostics (not only Settings refresh).
        diagnostics.startLiveUpdates { [weak self] in
            self?.buildDiagnosticsSnapshot() ?? .empty
        }
        refreshProgrammerPresentation()
        if case .failed = launchSplash.bootstrap {
            // Keep error splash; still allow UI observation.
        } else {
            launchSplash.markReady()
        }
        launchSplash.beginIfNeeded()
        notifyUI()
    }

    deinit {
        // Controllers tear down hardware in their stop methods; call from App when possible.
    }

    /// Granular UI invalidation — replaces dual `revision` + `objectWillChange` bump.
    func notifyUI() {
        objectWillChange.send()
    }

    /// Rebuild Programmer attribute presentation after selection or programmer mutation (UI-03).
    func refreshProgrammerPresentation() {
        programmerPresentation.refresh(
            orderedFixtureIDs: session.selection.snapshot.orderedFixtureIDs,
            project: session.project,
            programmer: engine.programmer
        )
    }

    /// Programmer UI callback: refresh presentation then broad UI.
    func noteProgrammerUIChanged() {
        refreshProgrammerPresentation()
        notifyUI()
    }

    /// Deprecated alias for `notifyUI()` (panels still call `bump()`).
    func bump() {
        notifyUI()
    }

    var panelContext: WorkspacePanelContext { document.panelContext }
    var fixtureLibraryBox: FixtureLibraryBox? { document.fixtureLibraryBox }
    var windowTitle: String { document.windowTitle }

    // MARK: - Document

    /// Await dirty prompt + optional save. Returns true if the requested operation may continue (UI-02 B5).
    func confirmDiscardIfDirtyAsync(actionName: String) async -> Bool {
        switch document.promptDirtyDocumentDecision(actionName: actionName) {
        case .proceedClean, .discard:
            return true
        case .save:
            return await saveShowAsync()
        case .cancel:
            return false
        }
    }

    /// Quit flow: prompt, await save if needed, then caller shuts down.
    func prepareToTerminate() async -> Bool {
        await confirmDiscardIfDirtyAsync(actionName: "quitting")
    }

    /// Sync wrapper for call sites that cannot await (prefer async variants).
    func newShow() {
        Task { @MainActor in await newShowAsync() }
    }

    func newShowAsync() async {
        guard await confirmDiscardIfDirtyAsync(actionName: "creating a new show") else { return }
        document.newShow()
        showControl.resetSong()
        afterDocumentReplaced()
        // DOC-01: empty untitled show is a real document workspace, not Welcome.
        workspace.enterDocumentWorkspace()
        notifyUI()
    }

    /// UI-02A: open deterministic populated demo for visual validation.
    func openDemoSummerNight() {
        Task { @MainActor in await openDemoSummerNightAsync() }
    }

    func openDemoSummerNightAsync() async {
        guard await confirmDiscardIfDirtyAsync(actionName: "opening the demo show") else { return }
        document.loadDemoSummerNight()
        showControl.resetSong()
        afterDocumentReplaced()
        let first = Array(session.project.fixtures.prefix(4).map(\.id))
        if !first.isEmpty {
            session.selectFixturesOrdered(first, extending: false)
        }
        notifyUI()
    }

    func importFixtureDefinition() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = "Import Fixture Definition"
        panel.message = "Aurora native JSON or OFL-lite JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try document.importFixtureDefinitions(from: url)
            reloadEngine()
            notifyUI()
        } catch {
            document.statusMessage = "Import failed: \(error.localizedDescription)"
            document.presentError(error, title: "Import Failed")
        }
    }

    func openShow() {
        Task { @MainActor in await openShowAsync() }
    }

    func openShowAsync() async {
        guard await confirmDiscardIfDirtyAsync(actionName: "opening") else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Open Aurora Show"
        panel.message = "Choose a .aurora package (folder)"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await openShow(at: url, skipDirtyConfirm: true)
    }

    /// Open a package URL (Finder, recent documents, or panel).
    func openShow(at url: URL, skipDirtyConfirm: Bool = false) {
        Task { @MainActor in
            await openShow(at: url, skipDirtyConfirm: skipDirtyConfirm)
        }
    }

    func openShow(at url: URL, skipDirtyConfirm: Bool = false) async {
        if !skipDirtyConfirm {
            guard await confirmDiscardIfDirtyAsync(actionName: "opening") else { return }
        }
        do {
            try document.openShow(from: url)
            showControl.resetSong()
            afterDocumentReplaced()
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            document.statusMessage = "Open failed: \(error.localizedDescription)"
            document.presentError(error, title: "Open Failed")
        }
    }

    /// Shared post-replace: reset document-scoped UI + reload engine (UI-02 B2).
    private func afterDocumentReplaced() {
        workspace.didReplaceDocument(project: session.project)
        // DOC-01: successful New/Open/Demo leaves Welcome for Build.
        workspace.enterDocumentWorkspace()
        reloadEngine()
        notifyUI()
    }

    func saveShow() {
        Task { @MainActor in
            await saveShowAsync()
        }
    }

    func saveShowAs() {
        Task { @MainActor in
            await saveShowAsAsync()
        }
    }

    /// Awaitable save for quit / discard flows (BLOCKER-1).
    @discardableResult
    func saveShowAsync() async -> Bool {
        if let documentURL = document.documentURL {
            return await saveAsync(to: documentURL)
        }
        return await saveShowAsAsync()
    }

    @discardableResult
    private func saveShowAsAsync() async -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save Aurora Show"
        panel.nameFieldStringValue = "\(session.project.metadata.name).aurora"
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let packageURL = url.pathExtension == ProjectPackage.packageExtension
            ? url
            : url.appendingPathExtension(ProjectPackage.packageExtension)
        return await saveAsync(to: packageURL)
    }

    @discardableResult
    private func saveAsync(to url: URL) async -> Bool {
        do {
            try await document.save(to: url)
            notifyUI()
            return !document.isDirty
        } catch {
            document.statusMessage = "Save failed: \(error.localizedDescription)"
            document.presentError(error, title: "Save Failed")
            return false
        }
    }

    func undo() {
        do {
            try document.undo()
            notifyUI()
        } catch {
            document.statusMessage = "Nothing to undo"
        }
    }

    func redo() {
        do {
            try document.redo()
            notifyUI()
        } catch {
            document.statusMessage = "Nothing to redo"
        }
    }

    func togglePanel(_ id: WorkspacePanelID) {
        workspace.togglePanel(id)
        notifyUI()
    }

    // MARK: - Engine

    func reloadEngineFromSession() {
        reloadEngine()
    }

    private func reloadEngine() {
        showControl.reloadFromProject(
            session.project,
            orderedSelection: session.selection.snapshot.orderedFixtureIDs
        )
    }

    private func applyProjectUpdate() {
        showControl.applyProjectUpdate(
            session.project,
            orderedSelection: session.selection.snapshot.orderedFixtureIDs
        )
    }

    func commitEffectsToProject() {
        do {
            try showControl.commitEffects(to: session)
            document.statusMessage = "Effects updated (\(engine.effects.exportDefinitions().count))"
            notifyUI()
        } catch {
            document.presentError(error, title: "Effects Update Failed")
        }
    }

    /// Semantic stage preview from engine's authoritative resolved frame (Pass-1 A5 fix).
    /// Does **not** re-run playback/effects in AppModel.
    func stagePreviewSnapshot() -> StagePreviewSnapshot {
        let resolved = engine.currentResolvedSnapshot()
        return StagePreviewBuilder.build(
            project: session.project,
            look: resolved.presentationLook,
            frameIndex: resolved.frameIndex,
            time: resolved.timestamp,
            global: resolved.global
        )
    }

    /// Fixture health rows for Diagnostics (P0-L+).
    func fixtureHealthRows() -> [DiagnosticsPanel.SnapshotView.Row] {
        let out = output.presentationSnapshot()
        let reports = FixtureHealth.report(
            project: session.project,
            output: out,
            artNetEnabled: artNetConfig.enabled,
            sacnEnabled: sacnConfig.enabled,
            localDMXEnabled: output.localDMXEnabled
        )
        return reports.prefix(40).map { r in
            let detail: String
            if r.issues.isEmpty {
                detail = "OK · " + r.notes.prefix(2).joined(separator: " · ")
            } else {
                detail = r.issues.joined(separator: "; ")
            }
            return .init(id: r.fixtureID.uuidString, title: r.fixtureName, detail: detail)
        }
    }

    func clearOverrides() {
        showControl.controlRouter.dispatch(.clearOverrides, notifySummary: "Clear Overrides")
        notifyUI()
    }

    func toggleMIDIPerformance() {
        showControl.controlRouter.dispatch(.toggleMIDIPerformance, notifySummary: "MIDI Performance")
        notifyUI()
    }

    func go() {
        showControl.go()
        input.sendMIDIFeedback(
            profiles: session.project.midiFeedbackProfiles,
            masterIntensity: engine.globalShowControl.masterIntensity,
            blackout: engine.globalShowControl.blackout,
            goPulse: true
        )
        output.refreshOutputStatus()
        notifyUI()
    }
    func back() { showControl.back(); notifyUI() }
    func stopPlayback() { showControl.stopPlayback(); notifyUI() }
    func fireCue(id: UUID) { showControl.fireCue(id: id); notifyUI() }

    func exportAuroraLibrary(to url: URL) throws {
        let contents = AuroraLibraryPackage.Contents.from(project: session.project, name: session.project.metadata.name)
        try AuroraLibraryPackage.save(contents, to: url)
        document.statusMessage = "Exported library \(url.lastPathComponent)"
        notifyUI()
    }

    func importAuroraLibrary(from url: URL, replaceExisting: Bool = false) throws {
        let contents = try AuroraLibraryPackage.load(from: url)
        try session.perform(MergeLibraryCommand(contents: contents, replaceExisting: replaceExisting))
        engine.updateProject(session.project)
        document.statusMessage = "Imported library \(contents.manifest.name)"
        notifyUI()
    }

    func exportLibraryPanel() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Export Aurora Library"
        panel.nameFieldStringValue = "\(session.project.metadata.name).auroralib"
        panel.allowedContentTypes = [UTType(filenameExtension: "auroralib") ?? .folder]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    try self.exportAuroraLibrary(to: url)
                } catch {
                    self.document.presentError(error, title: "Library Export Failed")
                }
            }
        }
    }

    func importLibraryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Import Aurora Library"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { @MainActor in
                do {
                    try self.importAuroraLibrary(from: url)
                } catch {
                    self.document.presentError(error, title: "Library Import Failed")
                }
            }
        }
    }

    // MARK: - Global show control (P0-I)

    func setMasterIntensity(_ value: Double) {
        engine.setMasterIntensity(value)
        notifyUI()
    }

    func toggleBlackout() {
        showControl.controlRouter.dispatch(.toggleBlackout, notifySummary: "Blackout")
        notifyUI()
    }

    func toggleFreeze() {
        showControl.controlRouter.dispatch(.toggleFreeze, notifySummary: "Freeze")
        notifyUI()
    }

    func toggleBlind() {
        showControl.controlRouter.dispatch(.toggleBlind, notifySummary: "Blind")
        notifyUI()
    }

    func panicReset() {
        showControl.controlRouter.dispatch(.panic, notifySummary: "Panic")
        notifyUI()
    }

    func perform(action: ShowAction, midiValue: UInt8? = nil) {
        showControl.perform(
            action: action,
            project: session.project,
            orderedSelection: session.selection.snapshot.orderedFixtureIDs,
            midiValue: midiValue
        )
        notifyUI()
    }

    // MARK: - Input

    func setRTPMIDIEnabled(_ enabled: Bool) {
        input.setRTPMIDIEnabled(enabled) { [weak self] msg in self?.diagnostics.log(msg) }
        notifyUI()
    }

    func setOSCEnabled(_ enabled: Bool) {
        // UI-GATE-2: live dispatch is on the OSC callback thread via ControlActionRouter;
        // this closure is presentation-only (MainActor).
        input.setOSCEnabled(
            enabled,
            router: showControl.controlRouter,
            onUINotify: { [weak self] action, _ in
                self?.showControl.refreshEngineStatus()
                self?.diagnostics.log("OSC \(action.storageKey)", subsystem: .midi)
                self?.notifyUI()
            },
            onLog: { [weak self] msg in self?.diagnostics.log(msg, subsystem: .midi) }
        )
        // Ensure router has current selection/mappings before live OSC arrives.
        showControl.controlRouter.updateMappings(session.project.midiMappings, project: session.project)
        showControl.controlRouter.updateOrderedSelection(session.selection.snapshot.orderedFixtureIDs)
        notifyUI()
    }

    /// PRE-UI-2: change engine frame rate from the app-global preference and persist it.
    func setPreferredFrameRateHz(_ hz: Double) {
        applyPreferredFrameRate(hz, persist: true)
        notifyUI()
    }

    private func applyPreferredFrameRate(_ hz: Double, persist: Bool) {
        let clamped = EngineConfiguration.clampFrameRate(hz)
        settings.preferredFrameRateHz = clamped
        if persist {
            settings.save()
        }
        let config = EngineConfiguration(frameRateHz: clamped)
        do {
            try showControl.engine.updateConfiguration(config)
            showControl.engine.frameMetrics.setTargetPeriodMs(config.framePeriod * 1000)
            diagnostics.log(
                String(format: "Engine frame rate %.0f Hz", clamped),
                subsystem: .engine
            )
        } catch {
            // Still set metrics target if restart failed mid-flight.
            showControl.engine.frameMetrics.setTargetPeriodMs((1.0 / max(1, clamped)) * 1000)
            diagnostics.log(
                "Frame rate apply failed: \(error.localizedDescription)",
                subsystem: .engine
            )
        }
    }

    /// BLOCKER-1 / UI-GATE-7: autosave through `ProjectSaveCoordinator` (serialized per destination).
    private func performBackgroundAutosave() async {
        guard document.documentURL != nil, document.isDirty else { return }
        diagnostics.log("Autosave begin", subsystem: .project)
        let cleaned = await document.autosaveIfPossible()
        if cleaned {
            diagnostics.log("Autosave ok", subsystem: .project)
            notifyUI()
        } else if document.isDirty {
            diagnostics.log("Autosave skipped or stale — document remains dirty", subsystem: .project)
        }
    }

    func armMIDILearn(_ action: ShowAction) {
        input.armMIDILearn(action)
        document.statusMessage = "MIDI Learn: \(action.storageKey) — send a message…"
        notifyUI()
    }

    func cancelMIDILearn() {
        input.cancelMIDILearn()
        document.statusMessage = "MIDI Learn cancelled"
        notifyUI()
    }

    // MARK: - Output

    func setArtNetEnabled(_ enabled: Bool) {
        output.setArtNetEnabled(enabled, engineRunning: engine.isRunning) { [weak self] msg in
            self?.diagnostics.log(msg)
        }
        notifyUI()
    }

    func setArtNetDestination(_ host: String) {
        output.setArtNetDestination(host, engineRunning: engine.isRunning)
        notifyUI()
    }

    func setSACNEnabled(_ enabled: Bool) {
        output.setSACNEnabled(enabled, engineRunning: engine.isRunning) { [weak self] msg in
            self?.diagnostics.log(msg)
        }
        notifyUI()
    }

    func setSACNUnicastHost(_ host: String?) {
        output.setSACNUnicastHost(host)
        notifyUI()
    }

    func promptArtNetDestination() {
        output.promptArtNetDestination(engineRunning: engine.isRunning) { [weak self] on in
            self?.setArtNetEnabled(on)
        }
    }

    func promptSACNDestination() {
        output.promptSACNDestination { [weak self] on in
            self?.setSACNEnabled(on)
        }
    }

    func log(_ message: String) {
        diagnostics.log(message)
        notifyUI()
    }

    // MARK: - Remote

    /// Authoritative remote enable/config path (REM-01/05). Menu and Settings both use this.
    func applyRemoteFromSettings(enabled: Bool? = nil) {
        if let enabled {
            settings.remoteAccessEnabled = enabled
            if enabled, settings.remotePIN.isEmpty {
                settings.remotePIN = RemoteHostConfig.generatePIN()
            }
            settings.save()
        }
        let on = settings.remoteAccessEnabled
        let pin = settings.remotePIN.isEmpty ? nil : settings.remotePIN
        let bind: RemoteBindPolicy = settings.remoteAccessMode == .thisMacOnly ? .loopbackOnly : .allInterfaces
        setRemoteEnabled(
            on,
            pin: pin,
            port: settings.remotePort,
            webPort: settings.remoteWebPort,
            bindPolicy: bind
        )
    }

    func setRemoteEnabled(
        _ enabled: Bool,
        pin: String? = nil,
        port: UInt16? = nil,
        webPort: UInt16? = nil,
        bindPolicy: RemoteBindPolicy? = nil
    ) {
        // UI-GATE-2: capture router for live path off MainActor.
        let router = showControl.controlRouter
        let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
            // Transport / programmer / fire — immediate, no MainActor hop.
            switch action {
            case .go:
                router.dispatch(.go)
            case .stop:
                router.dispatch(.stop)
            case .back:
                router.dispatch(.back)
            case .next:
                router.dispatch(.go)
            case .fireCueIndex(let i):
                router.dispatch(.fireCueIndex(i))
            case .fireCue(let id):
                router.dispatch(.fireCue(id))
            case .setProgrammerAttribute(let attr, let value):
                let control = MIDIControlValue(normalized: value, isTrigger: false)
                router.dispatch(.programmerAttribute(attr), control: control)
            case .masterIntensity(let v):
                router.dispatch(
                    .masterIntensity,
                    control: MIDIControlValue(normalized: min(1, max(0, v)), isTrigger: false)
                )
            case .blackout:
                router.dispatch(.blackout)
            case .blackoutOff:
                router.dispatch(.blackoutOff)
            case .toggleBlackout:
                router.dispatch(.toggleBlackout)
            case .songNext, .songPrevious:
                // SongDirector is MainActor; hop only for song navigation.
                Task { @MainActor in
                    self?.performRemoteSong(action)
                }
                return
            }
            // Presentation / log only after live dispatch.
            Task { @MainActor in
                self?.noteRemoteAction(action)
            }
        }
        remote.setRemoteEnabled(
            enabled,
            pin: pin,
            port: port ?? settings.remotePort,
            webPort: webPort ?? settings.remoteWebPort,
            bindPolicy: bindPolicy ?? (settings.remoteAccessMode == .thisMacOnly ? .loopbackOnly : .allInterfaces),
            onAction: action,
            makeSnapshot: { [weak self] in
                guard let self else {
                    return RemoteSnapshot(showName: "", engineRunning: false)
                }
                return self.remote.makeRemoteSnapshot(
                    project: self.session.project,
                    engine: self.engine,
                    song: self.songDirector.snapshot(project: self.session.project),
                    songStatusFallback: self.songStatus,
                    outputStatusLine: self.output.outputStatus
                )
            },
            onLog: { [weak self] msg in self?.diagnostics.log(msg, subsystem: .remote) }
        )
        // Keep settings truth aligned when menu toggles remote (REM-05).
        if settings.remoteAccessEnabled != enabled {
            settings.remoteAccessEnabled = enabled
            if enabled, let pin, !pin.isEmpty {
                settings.remotePIN = pin
            } else if enabled, settings.remotePIN.isEmpty {
                settings.remotePIN = remote.remoteHost.sessions.configSnapshot.pin
            }
            settings.save()
        } else if enabled, let pin, !pin.isEmpty, settings.remotePIN != pin {
            settings.remotePIN = pin
            settings.save()
        }
        notifyUI()
    }

    private func performRemoteSong(_ action: RemoteShowAction) {
        switch action {
        case .songNext:
            showControl.songNext(project: session.project)
        case .songPrevious:
            showControl.songPrevious(project: session.project)
        default:
            break
        }
        noteRemoteAction(action)
    }

    private func noteRemoteAction(_ action: RemoteShowAction) {
        showControl.refreshEngineStatus()
        diagnostics.log("Remote \(String(describing: action))", subsystem: .remote)
        notifyUI()
    }

    func setRemoteLockedToViewer(_ locked: Bool) {
        remote.setLockedToViewer(locked)
        diagnostics.log(locked ? "Remote locked to viewer" : "Remote operators allowed", subsystem: .remote)
        notifyUI()
    }

    func kickAllRemoteClients() {
        let router = showControl.controlRouter
        let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
            switch action {
            case .go: router.dispatch(.go)
            case .stop: router.dispatch(.stop)
            case .back: router.dispatch(.back)
            case .next: router.dispatch(.go)
            case .fireCueIndex(let i): router.dispatch(.fireCueIndex(i))
            case .fireCue(let id): router.dispatch(.fireCue(id))
            case .setProgrammerAttribute(let attr, let value):
                router.dispatch(
                    .programmerAttribute(attr),
                    control: MIDIControlValue(normalized: value, isTrigger: false)
                )
            case .masterIntensity(let v):
                router.dispatch(
                    .masterIntensity,
                    control: MIDIControlValue(normalized: min(1, max(0, v)), isTrigger: false)
                )
            case .blackout:
                router.dispatch(.blackout)
            case .blackoutOff:
                router.dispatch(.blackoutOff)
            case .toggleBlackout:
                router.dispatch(.toggleBlackout)
            case .songNext, .songPrevious:
                Task { @MainActor in self?.performRemoteSong(action) }
                return
            }
            Task { @MainActor in self?.noteRemoteAction(action) }
        }
        remote.kickAll(onAction: action) { [weak self] msg in
            self?.diagnostics.log(msg, subsystem: .remote)
        }
        notifyUI()
    }

    /// Orderly teardown (PRE-UI-3). Idempotent.
    private var didShutdown = false

    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        autosave.stop()
        // UI11-05: do not lose final layout drag on quit.
        workspace.flushLayoutPersistence()
        diagnostics.stopLiveUpdates()
        showControl.stopTimers()
        input.stopAll()
        output.stopAll()
        remote.stopAll()
    }

    // MARK: - Diagnostics projection (DIAG-01…03)

    func buildDiagnosticsSnapshot() -> DiagnosticsSnapshot {
        let out = output.presentationSnapshot()
        let health = output.healthSnapshots()
        let routes = session.project.universes.map { u in
            routeDiagnostics(universe: u, health: health)
        }
        return DiagnosticsSnapshot(
            engineRunning: engine.isRunning,
            frameRateHz: settings.preferredFrameRateHz,
            outputStatusLine: out.statusLine,
            localDMXStatus: output.localDMXStatus,
            localDMXEnabled: output.localDMXEnabled,
            localDMXRequested: output.localDMXRequestedEnabled,
            localDMXDeviceAvailable: output.localDMXConfiguredDeviceAvailable,
            artNetEnabled: artNetConfig.enabled,
            sacnEnabled: sacnConfig.enabled,
            midiStatus: midiHealth.statusLine,
            midiState: midiHealth.state.rawValue,
            midiSourceCount: midiHealth.connectedSourceCount,
            remoteStatus: remote.remoteStatus,
            remoteActuallyRunning: remote.isActuallyRunning,
            remoteClientCount: remote.remoteHost.sessions.clientsSnapshot.count,
            validationIssueCount: performance.validationIssueCount,
            driverHealth: health.map {
                DiagnosticsSnapshot.DriverHealthRow(
                    id: $0.driverID.uuidString,
                    name: $0.name,
                    state: $0.state.rawValue,
                    outputProtocol: $0.outputProtocol.rawValue,
                    lastError: $0.lastError
                )
            },
            universeRoutes: routes,
            generatedAt: Date()
        )
    }

    /// DIAG-03: per-universe health from matching drivers only.
    private func routeDiagnostics(
        universe: Universe,
        health: [OutputHealthSnapshot]
    ) -> DiagnosticsSnapshot.UniverseRouteRow {
        let hint = universe.protocolHint
        switch hint {
        case .none:
            return .init(
                id: universe.id,
                number: universe.number,
                name: universe.name,
                configuredRoute: "none",
                availability: "no route",
                runtimeHealth: "disabled"
            )
        case .local:
            return localRouteRow(universe: universe, health: health)
        case .artNet:
            return protocolRouteRow(universe: universe, proto: .artNet, health: health, enabled: artNetConfig.enabled)
        case .sACN:
            return protocolRouteRow(universe: universe, proto: .sACN, health: health, enabled: sacnConfig.enabled)
        case .mirror:
            return mirrorRouteRow(universe: universe, health: health)
        }
    }

    private func localRouteRow(universe: Universe, health: [OutputHealthSnapshot]) -> DiagnosticsSnapshot.UniverseRouteRow {
        let drivers = health.filter { $0.outputProtocol == .local && $0.state != .disabled }
        let availability: String
        if !output.localDMXConfiguredDeviceAvailable {
            availability = output.localDMXRequestedEnabled ? "device unavailable" : "no device"
        } else if output.localDMXEnabled {
            availability = "device ready"
        } else if output.localDMXRequestedEnabled {
            availability = "requested — not running"
        } else {
            availability = "not enabled"
        }
        let runtime: String
        if let d = drivers.first {
            runtime = d.state.rawValue + (d.lastError.map { " · \($0)" } ?? "")
        } else if output.localDMXEnabled {
            runtime = "enabled"
        } else {
            runtime = "off"
        }
        return .init(
            id: universe.id,
            number: universe.number,
            name: universe.name,
            configuredRoute: "local",
            availability: availability,
            runtimeHealth: runtime
        )
    }

    private func protocolRouteRow(
        universe: Universe,
        proto: UniverseProtocolHint,
        health: [OutputHealthSnapshot],
        enabled: Bool
    ) -> DiagnosticsSnapshot.UniverseRouteRow {
        let drivers = health.filter { $0.outputProtocol == proto }
        let active = drivers.filter { $0.state != .disabled }
        let availability = enabled ? (active.isEmpty ? "enabled — no driver ready" : "enabled") : "not enabled"
        let runtime: String
        if let worst = worstState(active) {
            let err = active.compactMap(\.lastError).first
            runtime = worst + (err.map { " · \($0)" } ?? "")
        } else {
            runtime = enabled ? "starting/idle" : "off"
        }
        return .init(
            id: universe.id,
            number: universe.number,
            name: universe.name,
            configuredRoute: proto.rawValue,
            availability: availability,
            runtimeHealth: runtime
        )
    }

    private func mirrorRouteRow(universe: Universe, health: [OutputHealthSnapshot]) -> DiagnosticsSnapshot.UniverseRouteRow {
        let physical = health.filter { $0.outputProtocol != .none && $0.state != .disabled }
        let parts = physical.map { "\($0.name):\($0.state.rawValue)" }
        let availability = physical.isEmpty ? "no physical drivers" : "\(physical.count) driver(s)"
        let runtime: String
        if physical.contains(where: { $0.state == .failed || $0.state == .disconnected }) {
            runtime = "failed · " + parts.joined(separator: ", ")
        } else if physical.contains(where: { $0.state == .degraded || $0.state == .starting }) {
            runtime = "degraded · " + parts.joined(separator: ", ")
        } else if physical.isEmpty {
            runtime = "disabled"
        } else {
            runtime = "ready · " + parts.joined(separator: ", ")
        }
        return .init(
            id: universe.id,
            number: universe.number,
            name: universe.name,
            configuredRoute: "mirror",
            availability: availability,
            runtimeHealth: runtime
        )
    }

    private func worstState(_ health: [OutputHealthSnapshot]) -> String? {
        if health.isEmpty { return nil }
        if health.contains(where: { $0.state == .failed || $0.state == .disconnected }) { return "failed" }
        if health.contains(where: { $0.state == .degraded || $0.state == .starting }) { return "degraded" }
        if health.contains(where: { $0.state == .ready }) { return "ready" }
        return health.first?.state.rawValue
    }

    func refreshDiagnosticsSnapshot() {
        diagnostics.refreshNow()
    }
}
