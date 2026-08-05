import AppKit
import AuroraCore
import AuroraFixtureLib
import AuroraModel
import AuroraUI
import Foundation
import UniformTypeIdentifiers

/// Document lifecycle: session, URL, dirty, save/open/new, validation hook (Stage C).
@MainActor
final class ProjectController: ObservableObject {
    @Published private(set) var session: DocumentSession
    @Published private(set) var documentURL: URL?
    @Published var statusMessage: String = ""

    private(set) var fixtureLibrary: FixtureLibrary?
    private var eventToken: EventSubscriptionToken?

    /// Called after document mutations (engine/input should refresh).
    var onProjectModified: (() -> Void)?
    var onSelectionChanged: ((SelectionSnapshot) -> Void)?
    var onLog: ((String) -> Void)?

    init(project: ShowProject = .empty(name: "Untitled Show")) {
        self.session = DocumentSession(project: project)
        loadFixtureLibrary()
        wireEvents()
    }

    var windowTitle: String {
        let name = session.project.metadata.name
        let dirty = session.isDirty ? " — Edited" : ""
        return "\(name)\(dirty)"
    }

    var isDirty: Bool { session.isDirty }

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

    private func loadFixtureLibrary() {
        do {
            let library = try FixtureLibrary.loadBundledSeed()
            fixtureLibrary = library
            statusMessage = "Loaded \(library.definitions.count) seed personalities"
            onLog?("Loaded fixture library (\(library.definitions.count) personalities)")
        } catch {
            fixtureLibrary = nil
            statusMessage = "Fixture library failed: \(error.localizedDescription)"
            onLog?("Fixture library error: \(error.localizedDescription)")
        }
    }

    func wireEvents() {
        if let eventToken {
            session.eventBus.unsubscribe(eventToken)
        }
        eventToken = session.eventBus.subscribe { [weak self] event in
            guard let self else { return }
            self.objectWillChange.send()
            switch event {
            case .projectModified:
                self.onProjectModified?()
            case .selectionChanged(let snap):
                self.onSelectionChanged?(snap)
            }
        }
    }

    @discardableResult
    func confirmDiscardIfDirty(actionName: String, save: () -> Void) -> Bool {
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
            save()
            return !session.isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func newShow() {
        session = DocumentSession(project: .empty(name: "Untitled Show"))
        documentURL = nil
        statusMessage = "New show"
        wireEvents()
        objectWillChange.send()
    }

    func openShow(from url: URL) throws {
        let project = try ProjectPackage.load(from: url)
        session = DocumentSession(project: project)
        documentURL = url
        session.markSaved()
        statusMessage = "Opened \(url.lastPathComponent)"
        wireEvents()
        objectWillChange.send()
    }

    func save(to url: URL) throws {
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
        objectWillChange.send()
    }

    func undo() throws {
        try session.undo()
        statusMessage = "Undo \(session.redoActionName ?? "")"
        objectWillChange.send()
    }

    func redo() throws {
        try session.redo()
        statusMessage = "Redo \(session.undoActionName ?? "")"
        objectWillChange.send()
    }

    func importFixtureDefinitions(from url: URL) throws -> Int {
        let defs = try FixtureImporter.importDefinitions(from: url)
        for def in defs {
            try session.perform(EmbedFixtureDefinitionCommand(definition: def))
        }
        statusMessage = "Imported \(defs.count) definition(s) from \(url.lastPathComponent)"
        onLog?(statusMessage)
        objectWillChange.send()
        return defs.count
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
