import AppKit
import AuroraCore
import AuroraEngine
import AuroraFixtureLib
import AuroraModel
import AuroraOutput
import AuroraUI
import Combine
import Foundation
import SwiftUI

/// Owns the live show session, workspace layout, fixture library, engine, and document path.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: DocumentSession
    @Published var layout: WorkspaceLayout
    @Published private(set) var documentURL: URL?
    @Published var statusMessage: String = ""
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var engineStatus: String = "Engine stopped"

    private var eventToken: EventSubscriptionToken?
    private let fixtureLibrary: FixtureLibrary?
    private let outputManager = OutputManager()
    private let nullDriver = NullOutputDriver(name: "Null")
    let engine: LightingEngine
    private var statusTimer: Timer?

    init(project: ShowProject = .empty(name: "Untitled Show")) {
        self.session = DocumentSession(project: project)
        self.layout = WorkspaceLayoutStore.load()
        self.engine = LightingEngine(output: outputManager)
        outputManager.register(nullDriver)

        do {
            let library = try FixtureLibrary.loadBundledSeed()
            self.fixtureLibrary = library
            self.statusMessage = "Loaded \(library.definitions.count) seed personalities"
        } catch {
            self.fixtureLibrary = nil
            self.statusMessage = "Fixture library failed: \(error.localizedDescription)"
        }

        wireEvents()
        reloadEngine()
        startEngineIfPossible()
        startStatusPolling()
    }

    deinit {
        statusTimer?.invalidate()
        engine.stop()
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

    private func reloadEngine() {
        engine.load(project: session.project)
        // Demo look: intensity 1.0 on all patched fixtures (until cue engine PR11).
        var look = ActiveLook()
        for fixture in session.project.fixtures {
            look.set(fixtureID: fixture.id, attribute: "intensity", value: 1.0)
        }
        engine.setLook(look)
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
        if snap.isRunning || engine.isRunning {
            engineStatus = String(
                format: "Engine %.0f Hz · frame %llu",
                snap.frameRateHz,
                snap.frameIndex
            )
        } else {
            engineStatus = "Engine stopped"
        }
    }

    private func wireEvents() {
        if let eventToken {
            session.eventBus.unsubscribe(eventToken)
        }
        eventToken = session.eventBus.subscribe { [weak self] event in
            guard let self else { return }
            self.bump()
            if case .projectModified = event {
                self.reloadEngine()
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
}
