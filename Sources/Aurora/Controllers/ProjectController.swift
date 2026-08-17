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
    private(set) var userFixtureDefinitions: [FixtureDefinition] = []
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
        WorkspacePanelContext(
            session: session,
            fixtureLibrary: fixtureLibraryBox,
            packageURL: documentURL
        )
    }

    var fixtureLibraryBox: FixtureLibraryBox? {
        guard let fixtureLibrary else { return nil }
        let builtIn = fixtureLibrary.definitions
        let builtInIDs = Set(builtIn.map(\.id))
        let user = userFixtureDefinitions.filter { !builtInIDs.contains($0.id) }
        let all = builtIn + user
        return FixtureLibraryBox(
            definitions: all,
            builtInDefinitionIDs: builtInIDs,
            userDefinitionIDs: Set(user.map(\.id)),
            search: { query in
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return all }
                return all.filter {
                    $0.manufacturer.localizedCaseInsensitiveContains(q)
                        || $0.model.localizedCaseInsensitiveContains(q)
                        || $0.modeName.localizedCaseInsensitiveContains(q)
                }
            },
            // Keep library definition UUID so project fixtures resolve the same personality
            // and the patch library list does not accumulate look-alike clones.
            makeEmbeddableCopy: { fixtureLibrary.makeEmbeddableCopy($0, newID: $0.id) },
            removeUserDefinitions: { [weak self] ids in
                try UserFixtureLibraryStore.remove(ids: ids)
                try self?.reloadUserFixtureLibrary()
            }
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
            return
        }
        do {
            try reloadUserFixtureLibrary()
        } catch {
            userFixtureDefinitions = []
            statusMessage = "User Fixture Library failed: \(error.localizedDescription)"
            onLog?(statusMessage)
        }
    }

    func reloadUserFixtureLibrary() throws {
        userFixtureDefinitions = try UserFixtureLibraryStore.load()
        objectWillChange.send()
    }

    var userFixtureLibraryDirectory: URL { UserFixtureLibraryStore.configuredDirectory }

    func setUserFixtureLibraryDirectory(_ url: URL?) throws {
        try UserFixtureLibraryStore.setDirectory(url)
        try reloadUserFixtureLibrary()
        statusMessage = "Fixture Library: \(userFixtureLibraryDirectory.path)"
    }

    func removeUserFixtureDefinitions(_ ids: Set<UUID>) throws {
        try UserFixtureLibraryStore.remove(ids: ids)
        try reloadUserFixtureLibrary()
        statusMessage = "Removed \(ids.count) mode(s) from User Fixture Library"
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
    ///
    /// Uses plain `runModal()` — fine for New/Open while the app is running.
    /// Quit uses a dedicated path in `AuroraAppDelegate` (sheets + `terminateLater`).
    func promptDirtyDocumentDecision(actionName: String) async -> DirtyDocumentDecision {
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
        // NSSavePanel / open-panel URLs are security-scoped under App Sandbox.
        let scopedDest = url.startAccessingSecurityScopedResource()
        defer {
            if scopedDest { url.stopAccessingSecurityScopedResource() }
        }

        let assetSource: URL?
        var scopedSource = false
        if let documentURL,
           documentURL.standardizedFileURL != url.standardizedFileURL {
            assetSource = documentURL
            scopedSource = documentURL.startAccessingSecurityScopedResource()
        } else {
            assetSource = nil
        }
        defer {
            if scopedSource, let documentURL {
                documentURL.stopAccessingSecurityScopedResource()
            }
        }

        let resolvedKind: ProjectSaveKind = {
            guard let documentURL else { return .manual }
            return documentURL.standardizedFileURL == url.standardizedFileURL ? .manual : .saveAs
        }()

        // Keep window/toolbar title in sync with the package basename on first save and Save As.
        // Regular Save to the same URL leaves an explicit show name alone.
        let packageBaseName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentName = session.project.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUntitled = currentName.isEmpty
            || currentName.caseInsensitiveCompare("Untitled Show") == .orderedSame
        let shouldSyncNameFromPackage = !packageBaseName.isEmpty
            && (resolvedKind == .saveAs || isUntitled)
            && packageBaseName != currentName
        let nameToPersist: String? = shouldSyncNameFromPackage ? packageBaseName : nil

        var projectToWrite = session.project
        if let nameToPersist {
            projectToWrite.metadata.name = nameToPersist
        }

        _ = try? ProjectPackage.recoverOrphanedPackages(around: url)

        let snapshot = ProjectSaveSnapshot(
            project: projectToWrite,
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
                session.applySavedMetadata(modifiedAt: writtenAt, name: nameToPersist)
                statusMessage = "Saved \(destination.lastPathComponent)"
            } else {
                documentURL = destination
                // Title should match the package even if edits landed after the snapshot.
                // Do not mark clean — the live document still has unsaved changes.
                if let nameToPersist {
                    session.applyPackageDisplayName(nameToPersist)
                }
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
        // A legacy project must migrate through the explicit Save path. Never let a
        // background autosave silently rewrite the original `.aurora` package.
        guard !ProjectPackage.isLegacyPackageURL(url) else {
            statusMessage = "Save to migrate this legacy project to .prism"
            objectWillChange.send()
            return false
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
        return try importFixtureDefinitions(defs, sourceName: url.lastPathComponent)
    }

    /// Validates and embeds a fixture import as one undoable, rollback-safe operation.
    func importFixtureDefinitions(_ defs: [FixtureDefinition], sourceName: String) throws -> Int {
        guard !defs.isEmpty else { return 0 }
        let existing = (fixtureLibrary?.definitions ?? []) + userFixtureDefinitions
        var identities = Set(existing.map(Self.fixtureModeIdentity))
        var ids = Set((existing + session.project.fixtureDefinitions).map(\.id))
        var duplicates: [String] = []
        for def in defs {
            let identity = Self.fixtureModeIdentity(def)
            if identities.contains(identity) || ids.contains(def.id) {
                duplicates.append("\(def.manufacturer) \(def.model) — \(def.modeName)")
            } else {
                identities.insert(identity)
                ids.insert(def.id)
            }
        }
        guard duplicates.isEmpty else {
            throw CommandError.message(
                "Already in the Fixture Library: " + duplicates.joined(separator: ", ")
            )
        }
        try UserFixtureLibraryStore.add(defs)
        try reloadUserFixtureLibrary()
        statusMessage = "Imported \(defs.count) mode(s) into User Library from \(sourceName)"
        onLog?(statusMessage)
        objectWillChange.send()
        return defs.count
    }

    private static func fixtureModeIdentity(_ definition: FixtureDefinition) -> String {
        [definition.manufacturer, definition.model, definition.modeName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            .joined(separator: "\u{1f}")
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
