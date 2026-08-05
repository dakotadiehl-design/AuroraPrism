import AppKit
import AuroraCore
import AuroraFixtureLib
import AuroraModel
import AuroraUI
import Combine
import Foundation
import SwiftUI

/// Owns the live show session, workspace layout, fixture library, and document path.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: DocumentSession
    @Published var layout: WorkspaceLayout
    @Published private(set) var documentURL: URL?
    @Published var statusMessage: String = ""
    @Published private(set) var revision: UInt64 = 0

    private var eventToken: EventSubscriptionToken?
    private let fixtureLibrary: FixtureLibrary?

    init(project: ShowProject = .empty(name: "Untitled Show")) {
        self.session = DocumentSession(project: project)
        self.layout = WorkspaceLayoutStore.load()
        do {
            let library = try FixtureLibrary.loadBundledSeed()
            self.fixtureLibrary = library
            self.statusMessage = "Loaded \(library.definitions.count) seed personalities"
        } catch {
            self.fixtureLibrary = nil
            self.statusMessage = "Fixture library failed: \(error.localizedDescription)"
        }
        wireEvents()
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
            // Saving does not clear dirty via session; track lightly.
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

    private func wireEvents() {
        if let eventToken {
            session.eventBus.unsubscribe(eventToken)
        }
        eventToken = session.eventBus.subscribe { [weak self] _ in
            self?.bump()
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
