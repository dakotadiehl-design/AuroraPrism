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

/// Owns the live show session, workspace layout, fixture library, engine, MIDI, and document path.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: DocumentSession
    @Published var layout: WorkspaceLayout
    @Published private(set) var documentURL: URL?
    @Published var statusMessage: String = ""
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var engineStatus: String = "Engine stopped"
    @Published private(set) var midiStatus: String = "MIDI: off"
    @Published private(set) var lastMIDIEvent: String = ""
    @Published private(set) var isMIDILearning: Bool = false
    @Published var songStatus: String = ""
    @Published var artNetConfig: ArtNetConfig
    @Published var sacnConfig: SACNConfig
    @Published private(set) var outputStatus: String = "Output: Null"
    @Published private(set) var midiLog: [String] = []
    @Published private(set) var consoleLog: [String] = []

    private var eventToken: EventSubscriptionToken?
    private let fixtureLibrary: FixtureLibrary?
    private let outputManager = OutputManager()
    private let nullDriver = NullOutputDriver(name: "Null")
    private let artNetDriver: ArtNetOutputDriver
    private let sacnDriver: SACNOutputDriver
    let engine: LightingEngine
    private let midi = MIDIInputManager()
    let midiLearn = MIDILearnSession()
    private var controlRouter: ControlActionRouter!
    private let midiLearnFlag = MIDILearnFlag()
    let rtpMIDI = RTPMIDISession()
    private let oscServer = OSCInputServer(port: 9000)
    @Published private(set) var oscStatus: String = "OSC: off"
    @Published private(set) var isOSCEnabled: Bool = false
    let songDirector = SongDirector()
    /// In-process plugin registry (PR29 skeleton; no dylib loading).
    let pluginHost = PluginHost()
    let diagnostics = DiagnosticsStore()
    let remoteHost = RemoteHost()
    private(set) var remoteWeb: RemoteWebServer?
    @Published private(set) var remoteStatus: String = "Remote: off"
    private var statusTimer: Timer?
    private var remoteSnapshotTimer: Timer?

    init(project: ShowProject = .empty(name: "Untitled Show")) {
        self.session = DocumentSession(project: project)
        self.layout = WorkspaceLayoutStore.load()
        let artConfig = ArtNetConfig.load()
        self.artNetConfig = artConfig
        self.artNetDriver = ArtNetOutputDriver(config: artConfig)
        let sacn = SACNConfig.load()
        self.sacnConfig = sacn
        self.sacnDriver = SACNOutputDriver(config: sacn)
        self.engine = LightingEngine(output: outputManager)
        self.controlRouter = ControlActionRouter(engine: engine)
        outputManager.register(nullDriver)
        if artConfig.enabled {
            outputManager.register(artNetDriver)
        }
        if sacn.enabled {
            outputManager.register(sacnDriver)
        }

        do {
            let library = try FixtureLibrary.loadBundledSeed()
            self.fixtureLibrary = library
            self.statusMessage = "Loaded \(library.definitions.count) seed personalities"
            log("Loaded fixture library (\(library.definitions.count) personalities)")
        } catch {
            self.fixtureLibrary = nil
            self.statusMessage = "Fixture library failed: \(error.localizedDescription)"
            log("Fixture library error: \(error.localizedDescription)")
        }

        wireEvents()
        reloadEngine()
        startEngineIfPossible()
        startMIDI()
        applySavedRTPMIDI()
        startStatusPolling()
        refreshOutputStatus()
    }

    deinit {
        statusTimer?.invalidate()
        remoteSnapshotTimer?.invalidate()
        engine.stop()
        midi.stop()
        oscServer.stop()
        remoteHost.stop()
        remoteWeb?.stop()
    }

    var panelContext: WorkspacePanelContext {
        WorkspacePanelContext(session: session, fixtureLibrary: fixtureLibraryBox)
    }

    var fixtureLibraryBox: FixtureLibraryBox? {
        guard let fixtureLibrary else { return nil }
        return FixtureLibraryBox(
            definitions: fixtureLibrary.definitions,
            search: { fixtureLibrary.search($0) },
            makeEmbeddableCopy: { fixtureLibrary.makeEmbeddableCopy($0) }
        )
    }

    var windowTitle: String {
        let name = session.project.metadata.name
        let dirty = session.isDirty ? " — Edited" : ""
        return "\(name)\(dirty)"
    }

    // MARK: - Document

    /// Returns false if the user cancels a dirty-document transition (P0-4).
    @discardableResult
    func confirmDiscardIfDirty(actionName: String) -> Bool {
        guard session.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this show before \(actionName)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveShow()
            return !session.isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func newShow() {
        guard confirmDiscardIfDirty(actionName: "creating a new show") else { return }
        session = DocumentSession(project: .empty(name: "Untitled Show"))
        documentURL = nil
        statusMessage = "New show"
        wireEvents()
        reloadEngine()
        bump()
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
            let defs = try FixtureImporter.importDefinitions(from: url)
            for def in defs {
                try session.perform(EmbedFixtureDefinitionCommand(definition: def))
            }
            statusMessage = "Imported \(defs.count) definition(s) from \(url.lastPathComponent)"
            log(statusMessage)
            reloadEngine()
            bump()
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
            presentError(error, title: "Import Failed")
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
        do {
            let project = try ProjectPackage.load(from: url)
            session = DocumentSession(project: project)
            documentURL = url
            session.markSaved()
            statusMessage = "Opened \(url.lastPathComponent)"
            wireEvents()
            reloadEngine()
            bump()
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
            presentError(error, title: "Open Failed")
        }
    }

    func saveShow() {
        if let documentURL {
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
            // True Save As: destination may not exist yet — copy media/layouts from the
            // currently open package, not from the empty destination.
            let assetSource: URL?
            if let documentURL,
               documentURL.standardizedFileURL != url.standardizedFileURL {
                assetSource = documentURL
            } else {
                assetSource = nil
            }
            try ProjectPackage.save(session.project, to: url, preservingAssetsFrom: assetSource)
            documentURL = url
            session.markSaved()
            statusMessage = "Saved \(url.lastPathComponent)"
            bump()
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            presentError(error, title: "Save Failed")
        }
    }

    // MARK: - Edit

    func undo() {
        do {
            try session.undo()
            statusMessage = "Undo \(session.redoActionName ?? "")"
            bump()
        } catch {
            statusMessage = "Nothing to undo"
        }
    }

    func redo() {
        do {
            try session.redo()
            statusMessage = "Redo \(session.undoActionName ?? "")"
            bump()
        } catch {
            statusMessage = "Nothing to redo"
        }
    }

    func togglePanel(_ id: WorkspacePanelID) {
        layout.toggle(id)
        WorkspaceLayoutStore.save(layout)
        bump()
    }

    func bump() {
        revision &+= 1
        objectWillChange.send()
    }

    // MARK: - Engine

    func reloadEngineFromSession() {
        reloadEngine()
    }

    private func reloadEngine() {
        engine.setLook(nil) // use cue playback, not a static override
        engine.load(project: session.project)
        if let list = session.project.cueLists.first {
            engine.loadCueList(list)
        }
        controlRouter.updateMappings(session.project.midiMappings, project: session.project)
        controlRouter.updateSelection(session.selection.snapshot.fixtureIDs)
    }

    func go() {
        engine.go()
        refreshEngineStatus()
        bump()
    }

    func back() {
        engine.back()
        refreshEngineStatus()
        bump()
    }

    func stopPlayback() {
        engine.stopPlayback()
        refreshEngineStatus()
        bump()
    }

    func fireCue(id: UUID) {
        engine.fire(cueID: id)
        refreshEngineStatus()
        bump()
    }

    private func startEngineIfPossible() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
            refreshEngineStatus()
        } catch {
            engineStatus = "Engine start failed"
            statusMessage = error.localizedDescription
        }
    }

    private func startMIDI() {
        let router = controlRouter!
        let learnFlag = midiLearnFlag
        controlRouter.setUINotify { [weak self] action, summary in
            Task { @MainActor in
                self?.appendMIDILog(summary)
                self?.lastMIDIEvent = summary
                self?.midiStatus = "MIDI: \(self?.midi.connectedCount ?? 0) src · \(summary)"
                self?.refreshEngineStatus()
                if case .programmerAttribute = action {
                    self?.bump()
                }
            }
        }
        controlRouter.updateMappings(session.project.midiMappings, project: session.project)
        midi.setHandler { [weak self] events in
            if learnFlag.isArmed {
                Task { @MainActor in
                    self?.handleMIDILearnOnly(events)
                }
                return
            }
            // Hot path: no MainActor (P1-1).
            router.handleMIDIEvents(events)
        }
        do {
            try midi.start()
            midiStatus = "MIDI: \(midi.connectedCount) sources"
        } catch {
            midiStatus = "MIDI: error"
            statusMessage = error.localizedDescription
        }
    }

    private func applySavedRTPMIDI() {
        let config = RTPMIDIConfig.load()
        rtpMIDI.apply(config)
        if config.enabled {
            log("RTP-MIDI enabled (\(rtpMIDI.localName))")
            try? midi.connectAllSources()
        }
    }

    func setRTPMIDIEnabled(_ enabled: Bool) {
        rtpMIDI.setEnabled(enabled)
        if enabled {
            try? midi.connectAllSources()
        }
        midiStatus = "\(midi.connectedCount) src · \(rtpMIDI.statusLine())"
        log(rtpMIDI.statusLine())
        bump()
    }

    func setOSCEnabled(_ enabled: Bool) {
        if enabled {
            oscServer.setHandler { [weak self] action, value in
                Task { @MainActor in
                    guard let self else { return }
                    if case .programmerAttribute = action, let value {
                        let ids = self.session.selection.snapshot.fixtureIDs
                        let attr: String
                        if case .programmerAttribute(let a) = action { attr = a } else { attr = "intensity" }
                        for id in ids {
                            self.engine.programmer.set(fixtureID: id, attribute: attr, value: Double(value))
                        }
                        self.bump()
                    } else {
                        let midiVal: UInt8? = value.map { UInt8(min(127, max(0, Int(($0 * 127).rounded())))) }
                        self.perform(action: action, midiValue: midiVal)
                    }
                    self.log("OSC \(action.storageKey)")
                }
            }
            do {
                try oscServer.start()
                isOSCEnabled = true
                oscStatus = "OSC: :\(oscServer.port)"
                log("OSC listening on \(oscServer.port)")
            } catch {
                isOSCEnabled = false
                oscStatus = "OSC: error"
                log("OSC start failed: \(error.localizedDescription)")
            }
        } else {
            oscServer.stop()
            isOSCEnabled = false
            oscStatus = "OSC: off"
            log("OSC stopped")
        }
        bump()
    }

    func armMIDILearn(_ action: ShowAction) {
        midiLearn.arm(action)
        isMIDILearning = true
        midiLearnFlag.isArmed = true
        statusMessage = "MIDI Learn: \(action.storageKey) — send a message…"
        bump()
    }

    func cancelMIDILearn() {
        midiLearn.cancel()
        isMIDILearning = false
        midiLearnFlag.isArmed = false
        statusMessage = "MIDI Learn cancelled"
        bump()
    }

    private func handleMIDILearnOnly(_ events: [MIDIEvent]) {
        for event in events {
            lastMIDIEvent = event.summary
            appendMIDILog(event.summary)
            if let learned = midiLearn.completeIfArmed(event: event) {
                isMIDILearning = false
                midiLearnFlag.isArmed = false
                do {
                    try session.perform(AddMIDIMappingCommand(mapping: learned.mapping))
                    controlRouter.updateMappings(session.project.midiMappings, project: session.project)
                    statusMessage = "Learned \(learned.action.storageKey) ← \(event.summary)"
                    log("MIDI learned \(learned.action.storageKey)")
                } catch {
                    statusMessage = "Learn failed: \(error.localizedDescription)"
                }
                bump()
            }
        }
        midiStatus = "MIDI: \(midi.connectedCount) src · \(lastMIDIEvent)"
    }

    func setArtNetEnabled(_ enabled: Bool) {
        artNetConfig.enabled = enabled
        artNetConfig.save()
        applyArtNetRegistration()
        refreshOutputStatus()
        log(enabled ? "Art-Net enabled → \(artNetConfig.destinationHost)" : "Art-Net disabled")
        bump()
    }

    func setArtNetDestination(_ host: String) {
        artNetConfig.destinationHost = host
        artNetConfig.useBroadcast = host.contains("255")
        artNetConfig.save()
        artNetDriver.updateConfig(artNetConfig)
        refreshOutputStatus()
        bump()
    }

    func setSACNEnabled(_ enabled: Bool) {
        sacnConfig.enabled = enabled
        sacnConfig.save()
        applySACNRegistration()
        refreshOutputStatus()
        log(enabled ? "sACN enabled" : "sACN disabled")
        bump()
    }

    func setSACNUnicastHost(_ host: String?) {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        sacnConfig.destinationHost = (trimmed?.isEmpty == false) ? trimmed : nil
        sacnConfig.save()
        sacnDriver.updateConfig(sacnConfig)
        refreshOutputStatus()
        bump()
    }

    private func applyArtNetRegistration() {
        if artNetConfig.enabled {
            artNetDriver.updateConfig(artNetConfig)
            outputManager.register(artNetDriver)
            if engine.isRunning {
                try? artNetDriver.start()
            }
        } else {
            artNetDriver.stop()
            outputManager.unregister(id: artNetDriver.id)
        }
    }

    private func applySACNRegistration() {
        if sacnConfig.enabled {
            sacnDriver.updateConfig(sacnConfig)
            outputManager.register(sacnDriver)
            if engine.isRunning {
                try? sacnDriver.start()
            }
        } else {
            sacnDriver.stop()
            outputManager.unregister(id: sacnDriver.id)
        }
    }

    private func refreshOutputStatus() {
        var parts: [String] = []
        if artNetConfig.enabled {
            let err = artNetDriver.lastError.map { " err:\($0)" } ?? ""
            parts.append("Art-Net \(artNetConfig.destinationHost):\(artNetConfig.destinationPort)\(err)")
        }
        if sacnConfig.enabled {
            let dest = sacnConfig.destinationHost ?? "multicast"
            let err = sacnDriver.lastError.map { " err:\($0)" } ?? ""
            parts.append("sACN \(dest):\(sacnConfig.destinationPort)\(err)")
        }
        outputStatus = parts.isEmpty ? "Output: Null only" : parts.joined(separator: " · ")
    }

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)"
        consoleLog.append(line)
        if consoleLog.count > 200 {
            consoleLog.removeFirst(consoleLog.count - 200)
        }
        diagnostics.info(message, subsystem: .app)
    }

    private func appendMIDILog(_ message: String) {
        midiLog.append(message)
        if midiLog.count > 100 {
            midiLog.removeFirst(midiLog.count - 100)
        }
    }

    private func ccValue(_ event: MIDIEvent) -> UInt8? {
        if case .controlChange(_, _, let v, _) = event { return v }
        return nil
    }

    func perform(action: ShowAction, midiValue: UInt8? = nil) {
        switch action {
        case .go: go()
        case .stop: stopPlayback()
        case .back: back()
        case .fireCue(let id): fireCue(id: id)
        case .fireCueIndex(let index):
            if let list = session.project.cueLists.first,
               list.cues.indices.contains(index) {
                fireCue(id: list.cues[index].id)
            }
        case .programmerAttribute(let attr):
            let value = MIDIActionResolver.ccNormalized(midiValue ?? 0)
            let ids = session.selection.snapshot.fixtureIDs
            for id in ids {
                engine.programmer.set(fixtureID: id, attribute: attr, value: value)
            }
            bump()
        }
    }

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEngineStatus()
            }
        }
    }

    private func refreshEngineStatus() {
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
        refreshOutputStatus()
    }

    private func wireEvents() {
        if let eventToken {
            session.eventBus.unsubscribe(eventToken)
        }
        eventToken = session.eventBus.subscribe { [weak self] event in
            guard let self else { return }
            self.bump()
            switch event {
            case .projectModified:
                self.reloadEngine()
            case .selectionChanged(let snap):
                self.engine.programmer.setHighlightSelection(snap.fixtureIDs)
                self.controlRouter.updateSelection(snap.fixtureIDs)
            }
        }
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func promptArtNetDestination() {
        let alert = NSAlert()
        alert.messageText = "Art-Net Destination"
        alert.informativeText = "Host IP (unicast) or 255.255.255.255 (broadcast). Show universe N → Art-Net N\(artNetConfig.universeOffset)."
        let field = NSTextField(string: artNetConfig.destinationHost)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            setArtNetDestination(field.stringValue)
            if !artNetConfig.enabled {
                setArtNetEnabled(true)
            }
        }
    }

    func setRemoteEnabled(_ enabled: Bool, pin: String? = nil) {
        var config = remoteHost.sessions.configSnapshot
        config.enabled = enabled
        if enabled {
            // P1-5: never default to trivial 0000; generate unless operator supplies.
            let chosen = (pin?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            config.pin = chosen ?? RemoteHostConfig.generatePIN()
        }
        remoteHost.sessions.updateConfig(config)
        if enabled {
            let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
                Task { @MainActor in
                    self?.performRemote(action)
                }
            }
            remoteHost.setActionHandler(action)
            let web = RemoteWebServer(sessions: remoteHost.sessions, port: 8743)
            web.setActionHandler(action)
            remoteWeb = web
            do {
                try remoteHost.start()
                try web.start()
                let activePIN = remoteHost.sessions.configSnapshot.pin
                remoteStatus = "Remote TCP :\(config.port) · Web :8743 · PIN \(activePIN)"
                log("Remote TCP \(config.port) + web 8743 · PIN \(activePIN)")
                startRemoteSnapshotTimer()
            } catch {
                remoteStatus = "Remote: error"
                log("Remote start failed: \(error.localizedDescription)")
            }
        } else {
            remoteSnapshotTimer?.invalidate()
            remoteSnapshotTimer = nil
            remoteHost.stop()
            remoteWeb?.stop()
            remoteWeb = nil
            remoteStatus = "Remote: off"
            log("Remote stopped")
        }
        bump()
    }

    private func startRemoteSnapshotTimer() {
        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let snap = self.makeRemoteSnapshot()
                self.remoteHost.setSnapshotProvider { snap }
                self.remoteWeb?.setSnapshotProvider { snap }
                self.remoteHost.broadcastSnapshot()
            }
        }
    }

    private func makeRemoteSnapshot() -> RemoteSnapshot {
        let engineSnap = engine.currentSnapshot()
        let pb = engineSnap.playback
        let levels = engineSnap.universeLevels[1] ?? []
        let active = levels.filter { $0 > 0 }.count
        var cueName: String?
        if pb.cueIndex >= 0,
           let cues = session.project.cueLists.first?.cues,
           cues.indices.contains(pb.cueIndex) {
            cueName = cues[pb.cueIndex].name
        }
        return RemoteSnapshot(
            showName: session.project.metadata.name,
            engineRunning: engine.isRunning,
            cueIndex: pb.cueIndex,
            cueName: cueName,
            songTitle: songStatus.isEmpty ? nil : songStatus,
            songEntryIndex: songDirector.entryIndex,
            locked: remoteHost.sessions.configSnapshot.lockedToViewer,
            role: .operatorRole,
            activeChannelCount: active
        )
    }

    private func performRemote(_ action: RemoteShowAction) {
        switch action {
        case .go: go()
        case .stop: stopPlayback()
        case .back: back()
        case .next: go()
        case .fireCueIndex(let i):
            if let list = session.project.cueLists.first, list.cues.indices.contains(i) {
                fireCue(id: list.cues[i].id)
            }
        case .fireCue(let id):
            fireCue(id: id)
        case .songNext:
            songDirector.next(project: session.project, engine: engine)
            bump()
        case .songPrevious:
            songDirector.previous(project: session.project, engine: engine)
            bump()
        case .setProgrammerAttribute(let attr, let value):
            for id in session.selection.snapshot.fixtureIDs {
                engine.programmer.set(fixtureID: id, attribute: attr, value: value)
            }
            bump()
        }
        log("Remote \(String(describing: action))")
    }

    func setRemoteLockedToViewer(_ locked: Bool) {
        remoteHost.sessions.setLockedToViewer(locked)
        remoteStatus = locked ? "Remote: locked (viewer)" : "Remote: operators allowed"
        bump()
    }

    func kickAllRemoteClients() {
        let ids = remoteHost.sessions.kickAll()
        // Web tokens are session-scoped; restart web to drop tokens cleanly.
        if remoteHost.sessions.configSnapshot.enabled, let web = remoteWeb {
            web.stop()
            let action: @Sendable (RemoteShowAction) -> Void = { [weak self] action in
                Task { @MainActor in
                    self?.performRemote(action)
                }
            }
            let fresh = RemoteWebServer(sessions: remoteHost.sessions, port: web.port)
            fresh.setActionHandler(action)
            remoteWeb = fresh
            try? fresh.start()
        }
        log("Kicked \(ids.count) remote client(s)")
        bump()
    }

    func promptSACNDestination() {
        let alert = NSAlert()
        alert.messageText = "sACN Destination"
        alert.informativeText = "Leave empty for per-universe multicast (239.255.x.y). Or set a unicast node IP. Show U N → sACN N+\(sacnConfig.universeOffset)."
        let field = NSTextField(string: sacnConfig.destinationHost ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.placeholderString = "multicast"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            setSACNUnicastHost(field.stringValue)
            if !sacnConfig.enabled {
                setSACNEnabled(true)
            }
        }
    }
}
