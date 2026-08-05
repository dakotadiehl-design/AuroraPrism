import AppKit
import AuroraCore
import AuroraEngine
import AuroraFixtureLib
import AuroraMIDI
import AuroraModel
import AuroraOutput
import AuroraUI
import Combine
import Foundation
import SwiftUI

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
    let songDirector = SongDirector()
    private var statusTimer: Timer?

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
        startStatusPolling()
        refreshOutputStatus()
    }

    deinit {
        statusTimer?.invalidate()
        engine.stop()
        midi.stop()
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

    func newShow() {
        session = DocumentSession(project: .empty(name: "Untitled Show"))
        documentURL = nil
        statusMessage = "New show"
        wireEvents()
        reloadEngine()
        bump()
    }

    func openShow() {
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
            try ProjectPackage.save(session.project, to: url)
            documentURL = url
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
        midi.setHandler { [weak self] events in
            Task { @MainActor in
                self?.handleMIDI(events)
            }
        }
        do {
            try midi.start()
            midiStatus = "MIDI: \(midi.connectedCount) sources"
        } catch {
            midiStatus = "MIDI: error"
            statusMessage = error.localizedDescription
        }
    }

    func armMIDILearn(_ action: ShowAction) {
        midiLearn.arm(action)
        isMIDILearning = true
        statusMessage = "MIDI Learn: \(action.storageKey) — send a message…"
        bump()
    }

    func cancelMIDILearn() {
        midiLearn.cancel()
        isMIDILearning = false
        statusMessage = "MIDI Learn cancelled"
        bump()
    }

    private func handleMIDI(_ events: [MIDIEvent]) {
        for event in events {
            lastMIDIEvent = event.summary
            appendMIDILog(event.summary)
            if let learned = midiLearn.completeIfArmed(event: event) {
                isMIDILearning = false
                do {
                    try session.perform(AddMIDIMappingCommand(mapping: learned.mapping))
                    statusMessage = "Learned \(learned.action.storageKey) ← \(event.summary)"
                    log("MIDI learned \(learned.action.storageKey)")
                } catch {
                    statusMessage = "Learn failed: \(error.localizedDescription)"
                }
                bump()
                continue
            }
            if let action = MIDIActionResolver.match(event: event, mappings: session.project.midiMappings) {
                perform(action: action, midiValue: ccValue(event))
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
