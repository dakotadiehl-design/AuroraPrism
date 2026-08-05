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

    /// In-process plugin registry (PR29 / P3-4 protocol surfaces).
    let pluginHost = PluginHost()

    private var cancellables = Set<AnyCancellable>()

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
        let output = OutputController()
        let showControl = ShowControlController(output: output.outputManager)
        let input = InputController()
        let remote = RemoteController()
        let diagnostics = DiagnosticsController()
        let workspace = WorkspaceController()
        let settings = AppSettingsStore()

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
        ] as [ObservableObjectPublisher] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        document.onLog = { [weak self] msg in self?.diagnostics.log(msg) }
        document.onProjectModified = { [weak self] in
            self?.applyProjectUpdate()
        }
        document.onSelectionChanged = { [weak self] snap in
            guard let self else { return }
            self.engine.programmer.setHighlightSelection(snap.fixtureIDs)
            self.showControl.controlRouter.updateOrderedSelection(snap.orderedFixtureIDs)
        }

        // Seed log from library load
        if !document.statusMessage.isEmpty {
            diagnostics.log(document.statusMessage)
        }

        reloadEngine()
        showControl.startEngineIfPossible()
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
                    self?.notifyUI()
                }
            }
        }
        input.applySavedRTPMIDI { [weak self] msg in self?.diagnostics.log(msg, subsystem: .midi) }
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
        notifyUI()
    }

    deinit {
        // Controllers tear down hardware in their stop methods; call from App when possible.
    }

    /// Granular UI invalidation — replaces dual `revision` + `objectWillChange` bump.
    func notifyUI() {
        objectWillChange.send()
    }

    /// Deprecated alias for `notifyUI()` (panels still call `bump()`).
    func bump() {
        notifyUI()
    }

    var panelContext: WorkspacePanelContext { document.panelContext }
    var fixtureLibraryBox: FixtureLibraryBox? { document.fixtureLibraryBox }
    var windowTitle: String { document.windowTitle }

    // MARK: - Document

    @discardableResult
    func confirmDiscardIfDirty(actionName: String) -> Bool {
        // Menu-driven new/open: kick async save if user chooses Save (best-effort).
        document.confirmDiscardIfDirty(actionName: actionName) { [weak self] in
            self?.saveShow()
        }
    }

    /// Quit flow: prompt, await save if needed, then caller shuts down.
    /// Returns `true` if termination should proceed.
    func prepareToTerminate() async -> Bool {
        guard document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this show before quitting?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return await saveShowAsync()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func newShow() {
        guard confirmDiscardIfDirty(actionName: "creating a new show") else { return }
        document.newShow()
        showControl.resetSong()
        reloadEngine()
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
        guard confirmDiscardIfDirty(actionName: "opening") else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Open Aurora Show"
        panel.message = "Choose a .aurora package (folder)"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openShow(at: url, skipDirtyConfirm: true)
    }

    /// Open a package URL (Finder, recent documents, or panel).
    func openShow(at url: URL, skipDirtyConfirm: Bool = false) {
        if !skipDirtyConfirm {
            guard confirmDiscardIfDirty(actionName: "opening") else { return }
        }
        do {
            try document.openShow(from: url)
            showControl.resetSong()
            reloadEngine()
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            notifyUI()
        } catch {
            document.statusMessage = "Open failed: \(error.localizedDescription)"
            document.presentError(error, title: "Open Failed")
        }
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

    func go() { showControl.go(); output.refreshOutputStatus(); notifyUI() }
    func back() { showControl.back(); notifyUI() }
    func stopPlayback() { showControl.stopPlayback(); notifyUI() }
    func fireCue(id: UUID) { showControl.fireCue(id: id); notifyUI() }

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

    func setRemoteEnabled(_ enabled: Bool, pin: String? = nil) {
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
            onAction: action,
            makeSnapshot: { [weak self] in
                guard let self else {
                    return RemoteSnapshot(
                        showName: "",
                        engineRunning: false,
                        cueIndex: -1,
                        cueName: nil,
                        songTitle: nil,
                        songEntryIndex: -1,
                        locked: false,
                        role: .viewer,
                        activeChannelCount: 0
                    )
                }
                return self.remote.makeRemoteSnapshot(
                    project: self.session.project,
                    engine: self.engine,
                    song: self.songDirector.snapshot(project: self.session.project),
                    songStatusFallback: self.songStatus
                )
            },
            onLog: { [weak self] msg in self?.diagnostics.log(msg, subsystem: .remote) }
        )
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
        showControl.stopTimers()
        input.stopAll()
        output.stopAll()
        remote.stopAll()
    }
}
