import AppKit
import AuroraCore
import AuroraFixtureLib
import AuroraModel
import AuroraUI
import Foundation
import UniformTypeIdentifiers

/// Document lifecycle: session, URL, dirty, save/open/new, validation hook (Stage C / BLOCKER-1).
@MainActor
final class ProjectController: ObservableObject {
    @Published private(set) var session: DocumentSession
    @Published private(set) var documentURL: URL?
    @Published var statusMessage: String = ""

    /// Serializes all package writes (manual, Save As, autosave) per destination.
    let saveCoordinator = ProjectSaveCoordinator()

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

    enum DirtyDocumentDecision: Sendable, Equatable {
        case proceedClean
        case save
        case discard
        case cancel
    }

    /// Prompt only — does not save. Caller awaits save on `.save` (UI-02 B5).
    func promptDirtyDocumentDecision(actionName: String) -> DirtyDocumentDecision {
        guard session.isDirty else { return .proceedClean }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this show before \(actionName)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    func newShow() {
        session = DocumentSession(project: .empty(name: "Untitled Show"))
        documentURL = nil
        statusMessage = "New show"
        wireEvents()
        objectWillChange.send()
    }

    /// Load deterministic UI-02A demo project (real model objects, not view hard-coding).
    func loadDemoSummerNight() {
        session = DocumentSession(project: .demoSummerNight())
        documentURL = nil
        statusMessage = "Loaded demo: Summer Night Show"
        wireEvents()
        objectWillChange.send()
        onLog?("Loaded UI-02A demo Summer Night Show")
    }

    /// Manual Save / Save As through the shared coordinator (BLOCKER-1).
    func save(to url: URL) async throws {
        let assetSource: URL?
        if let documentURL,
           documentURL.standardizedFileURL != url.standardizedFileURL {
            assetSource = documentURL
        } else {
            assetSource = nil
        }
        let resolvedKind: ProjectSaveKind = {
            guard let documentURL else { return .manual }
            return documentURL.standardizedFileURL == url.standardizedFileURL ? .manual : .saveAs
        }()

        _ = try? ProjectPackage.recoverOrphanedPackages(around: url)

        let snapshot = ProjectSaveSnapshot(
            project: session.project,
            documentStateID: session.documentGeneration,
            destinationURL: url,
            preservingAssetsFrom: assetSource,
            kind: resolvedKind
        )
        let result = try await saveCoordinator.save(snapshot)
        switch result {
        case .written(let writtenAt, let stateID, let destination):
            // Only mark clean if this state is still current.
            if session.documentGeneration == stateID {
                documentURL = destination
                session.applySavedMetadata(modifiedAt: writtenAt)
                statusMessage = "Saved \(destination.lastPathComponent)"
            } else {
                documentURL = destination
                statusMessage = "Saved \(destination.lastPathComponent) (document edited since save)"
            }
            NSDocumentController.shared.noteNewRecentDocumentURL(destination)
            objectWillChange.send()
        case .skippedStale:
            // Manual save should not skip; treat as soft failure.
            statusMessage = "Save skipped (stale)"
            objectWillChange.send()
        }
    }

    /// Autosave via coordinator. Returns whether the document was marked clean.
    @discardableResult
    func autosaveIfPossible() async -> Bool {
        guard let url = documentURL, session.isDirty else { return false }
        let snapshot = ProjectSaveSnapshot(
            project: session.project,
            documentStateID: session.documentGeneration,
            destinationURL: url,
            preservingAssetsFrom: url,
            kind: .autosave
        )
        do {
            let result = try await saveCoordinator.autosave(snapshot)
            switch result {
            case .written(let writtenAt, let stateID, let destination):
                if session.documentGeneration == stateID,
                   documentURL?.standardizedFileURL == destination.standardizedFileURL {
                    session.applySavedMetadata(modifiedAt: writtenAt)
                    statusMessage = "Autosaved \(destination.lastPathComponent)"
                    objectWillChange.send()
                    return true
                }
                return false
            case .skippedStale:
                return false
            }
        } catch {
            onLog?("Autosave failed: \(error.localizedDescription)")
            return false
        }
    }

    func openShow(from url: URL) throws {
        _ = try? ProjectPackage.recoverOrphanedPackages(around: url)
        let project = try ProjectPackage.load(from: url)
        session = DocumentSession(project: project)
        documentURL = url
        session.markSaved()
        statusMessage = "Opened \(url.lastPathComponent)"
        wireEvents()
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
