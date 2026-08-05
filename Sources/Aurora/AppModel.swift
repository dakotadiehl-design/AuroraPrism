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
        input.startMIDI(
            router: showControl.controlRouter,
            session: { [weak self] in self?.document.session ?? DocumentSession(project: .empty()) },
            onLog: { [weak self] msg in self?.diagnostics.log(msg) }
        )
        // P2-17: MIDI subsystem diagnostics bridge
        // (InputController can log connect/disconnect via setDiagnosticsLogger when wired)
        showControl.setUINotify { [weak self] action, summary in
            Task { @MainActor in
                self?.input.objectWillChange.send()
                self?.showControl.refreshEngineStatus()
                if case .programmerAttribute = action {
                    self?.notifyUI()
                }
            }
        }
        input.applySavedRTPMIDI { [weak self] msg in self?.diagnostics.log(msg) }
        showControl.startStatusPolling(
            outputStatus: { [weak self] in self?.output.outputStatus ?? "Output: Null" },
            project: { [weak self] in self?.document.session.project ?? .empty() },
            isDirty: { [weak self] in self?.document.isDirty ?? false }
        )
        output.refreshOutputStatus()
        // P2-22: preferred frame rate from app settings affects engine when possible.
        if let period = Optional(1.0 / max(1, settings.preferredFrameRateHz)) {
            showControl.engine.frameMetrics.setTargetPeriodMs(period * 1000)
        }
        autosave.onAutosave = { [weak self] in
            guard let self, let url = self.document.documentURL, self.document.isDirty else { return false }
            do {
                try self.document.save(to: url)
                self.diagnostics.log("Autosave \(url.lastPathComponent)")
                return true
            } catch {
                self.diagnostics.log("Autosave failed: \(error.localizedDescription)")
                return false
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
        document.confirmDiscardIfDirty(actionName: actionName) { [weak self] in
            self?.saveShow()
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
        if let documentURL = document.documentURL {
            save(to: documentURL)
        } else {
            saveShowAs()
        }
    }

    func saveShowAs() {
        let panel = NSSavePanel()
        panel.title = "Save Aurora Show"
        panel.nameFieldStringValue = "\(session.project.metadata.name).aurora"
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let packageURL = url.pathExtension == ProjectPackage.packageExtension
            ? url
            : url.appendingPathExtension(ProjectPackage.packageExtension)
        save(to: packageURL)
    }

    private func save(to url: URL) {
        do {
            try document.save(to: url)
            notifyUI()
        } catch {
            document.statusMessage = "Save failed: \(error.localizedDescription)"
            document.presentError(error, title: "Save Failed")
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
        input.setOSCEnabled(enabled, onAction: { [weak self] action, value in
            guard let self else { return }
            if case .programmerAttribute(let attr) = action, let value {
                for id in self.session.selection.snapshot.fixtureIDs {
                    self.engine.programmer.set(fixtureID: id, attribute: attr, value: Double(value))
                }
                self.notifyUI()
            } else {
                let midiVal: UInt8? = value.map { UInt8(min(127, max(0, Int((Double($0) * 127).rounded())))) }
                self.perform(action: action, midiValue: midiVal)
            }
            self.diagnostics.log("OSC \(action.storageKey)")
        }, onLog: { [weak self] msg in self?.diagnostics.log(msg) })
        notifyUI()
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
        let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
            Task { @MainActor in
                self?.performRemote(action)
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
            onLog: { [weak self] msg in self?.diagnostics.log(msg) }
        )
        notifyUI()
    }

    private func performRemote(_ action: RemoteShowAction) {
        // Live transport/programmer via ControlActionRouter (not MainActor-bound engine wait) — P2-15.
        switch action {
        case .go:
            showControl.controlRouter.dispatch(.go)
        case .stop:
            showControl.controlRouter.dispatch(.stop)
        case .back:
            showControl.controlRouter.dispatch(.back)
        case .next:
            showControl.controlRouter.dispatch(.go)
        case .fireCueIndex(let i):
            showControl.controlRouter.dispatch(.fireCueIndex(i))
        case .fireCue(let id):
            showControl.controlRouter.dispatch(.fireCue(id))
        case .songNext:
            showControl.songNext(project: session.project)
        case .songPrevious:
            showControl.songPrevious(project: session.project)
        case .setProgrammerAttribute(let attr, let value):
            let control = MIDIControlValue(normalized: value, isTrigger: false)
            showControl.controlRouter.dispatch(
                .programmerAttribute(attr),
                control: control
            )
        }
        showControl.refreshEngineStatus()
        diagnostics.log("Remote \(String(describing: action))")
        notifyUI()
    }

    func setRemoteLockedToViewer(_ locked: Bool) {
        remote.setLockedToViewer(locked)
        notifyUI()
    }

    func kickAllRemoteClients() {
        let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
            Task { @MainActor in
                self?.performRemote(action)
            }
        }
        remote.kickAll(onAction: action) { [weak self] msg in self?.diagnostics.log(msg) }
        notifyUI()
    }

    /// Shutdown hook for app delegate if needed later.
    func shutdown() {
        autosave.stop()
        showControl.stopTimers()
        input.stopAll()
        output.stopAll()
        remote.stopAll()
    }
}
