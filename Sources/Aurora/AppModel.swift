import AppKit
import AuroraCore
import AuroraEngine
import AuroraFixtureLib
import AuroraMIDI
import AuroraModel
import AuroraDiagnostics
import AuroraOutput
import AuroraUI
import PrismACP
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
    let acp: PrismACPController
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

    /// C5.1: exact FloatSurfaceID ↔ NSWindow mapping + frame tracking.
    let floatWindows = FloatingSurfaceWindowCoordinator()

    /// True once quit has been accepted — floating teardown must not redock (preserve layout).
    @Published private(set) var isTerminating = false

    private var cancellables = Set<AnyCancellable>()
    private var controlEventObserver: ControlEventObserverToken?
    /// Private Effects authoring state used only to substitute the main Stage presentation.
    /// It is never installed in `EffectRunner` and therefore cannot reach DMX output.
    private var effectsStagePreviewEffect: EffectInstance?
    private var effectsStagePreviewEnabled = false

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
    var remoteStatus: String { acp.status }
    var engine: LightingEngine { showControl.engine }
    var songDirector: SongDirector { showControl.songDirector }
    var midiLearn: MIDILearnSession { input.midiLearn }
    var rtpMIDI: RTPMIDISession { input.rtpMIDI }
    var performance: PerformanceSnapshot { showControl.performance }

    init(project: ShowProject = .empty(name: "Untitled Show")) {
        let settings = AppSettingsStore()
        PrismLogConfigurationStore.shared.replace(settings.loggingConfiguration)
        let memorySink = InMemoryPrismLogSink.shared
        PrismLog.shared = CompositePrismLogger(sinks: [UnifiedPrismLogger(), memorySink])
        if settings.consumeLoggingLoadWarning() {
            PrismLog.warning(
                .appSettings,
                "app.settings.config_fallback",
                "Prism couldn't read the saved logging settings and restored the production defaults."
            )
        }

        let document = ProjectController(project: project)
        let output = OutputController(settings: settings)
        let showControl = ShowControlController(output: output.outputManager)
        let input = InputController()
        let acp = PrismACPController()
        let diagnostics = DiagnosticsController(memorySink: memorySink)
        let workspace = WorkspaceController()

        self.document = document
        self.output = output
        self.showControl = showControl
        self.input = input
        self.acp = acp
        self.diagnostics = diagnostics
        self.workspace = workspace
        self.settings = settings
        showControl.onSemanticCommit = { [weak self] in
            Task { @MainActor in
                await self?.publishACPState()
            }
        }
        // C5.1: wire float window coordinator → workspace frame / redock policy.
        floatWindows.isTerminating = { [weak self] in self?.isTerminating == true }
        floatWindows.onFrameChanged = { [weak self] surface, frame, screenID, screenName in
            self?.workspace.updateFloatingFrame(
                surface,
                frame: frame,
                screenID: screenID,
                screenName: screenName
            )
        }
        floatWindows.onUserCloseWhileFloating = { [weak self] surface in
            guard let self else { return }
            switch FloatWindowClosePolicy.decide(
                isTerminating: self.isTerminating,
                surfaceStillFloating: self.workspace.isFloating(surface)
            ) {
            case .redock:
                self.workspace.redock(surface)
                self.notifyUI()
            case .preserveFloating, .ignore:
                break
            }
        }

        // Cascade child observation so EnvironmentObject AppModel still refreshes UI.
        for publisher in [
            document.objectWillChange,
            workspace.objectWillChange,
            showControl.objectWillChange,
            input.objectWillChange,
            output.objectWillChange,
            acp.objectWillChange,
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

        document.onProjectModified = { [weak self] in
            guard let self else { return }
            self.applyProjectUpdate()
            self.showControl.noteAuthoritativeCommit()
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
            output.setLocalDMXEnabled(true, engineRunning: engine.isRunning)
        } else {
            output.startLocalDMXIfNeeded()
        }

        launchSplash.note(.startingMIDI)
        // Wave 1: clock adapter independent of channel-voice Learn path.
        input.attachClockAdapter(showControl.clockAdapter)
        // UI-GATE-1: multi-observer — MIDI log and show-control both subscribe; neither replaces the other.
        input.startMIDI(
            router: showControl.controlRouter,
            session: { [weak self] in self?.document.session ?? DocumentSession(project: .empty()) }
        )
        // Binding resolution against live inventory (Wave 1–5 review C5).
        input.setInventoryListener { [weak self] devices in
            self?.showControl.updateMIDIInventory(devices)
        }
        showControl.updateMIDIInventory(input.midiSources)
        _ = showControl.addUIObserver { [weak self] action, _ in
            Task { @MainActor in
                self?.showControl.refreshEngineStatus()
                if case .programmerAttribute = action {
                    self?.refreshProgrammerPresentation()
                    self?.notifyUI()
                }
            }
        }
        input.applySavedRTPMIDI()

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
        if settings.remoteAccessEnabled {
            applyRemoteFromSettings(enabled: true)
        }
        // DIAG-01: live throttled diagnostics (not only Settings refresh).
        diagnostics.startLiveUpdates { [weak self] in
            self?.buildDiagnosticsSnapshot() ?? .empty
        }
        PrismLog.notice(
            .appLifecycle,
            "app.lifecycle.launch",
            "Prism is ready.",
            metadata: [
                "profile": .public(settings.loggingConfiguration.profile.rawValue),
                "count": .count(PrismLogCategory.allCases.count),
            ]
        )
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
    /// Programmer high-frequency path (color wheel, faders).
    /// Refreshes presentation store only — avoids full-shell `notifyUI()` on every pointer sample (C.E. 1.1).
    func noteProgrammerUIChanged() {
        refreshProgrammerPresentation()
        // `programmerPresentation` is already cascaded via objectWillChange subscription.
        // Stage/output follow engine frames; no broad shell rebuild required here.
    }

    /// Applies silent Shift-D numeric entry to the current fixture selection.
    func setSelectedDimmer(percent: Int) {
        let fixtureIDs = session.selection.snapshot.orderedFixtureIDs
        guard !fixtureIDs.isEmpty else { return }
        var resolved = engine.currentResolvedSnapshot().programmerLook.fixtureAttributes
        for (fixtureID, attributes) in engine.programmer.snapshot().values {
            var merged = resolved[fixtureID] ?? [:]
            merged.merge(attributes) { _, programmerValue in programmerValue }
            resolved[fixtureID] = merged
        }
        let current = ProgrammerIntensityGroup.effectiveValues(
            fixtureIDs: fixtureIDs,
            project: session.project,
            resolvedValues: resolved
        )
        guard !current.isEmpty else { return }
        let shifted = ProgrammerIntensityGroup.shiftedValues(
            current,
            toAverage: Double(min(100, max(0, percent))) / 100
        )
        engine.programmer.setMany(attribute: "intensity", values: shifted)
        noteProgrammerUIChanged()
    }

    /// Applies silent Shift-F numeric entry to fog/haze output on capable fixtures.
    func setSelectedFog(percent: Int) {
        setSelectedDeviceFunction(
            percent: percent,
            preferredAttributes: [
                "fogOutput", "hazeOutput", "smokeOutput", "fog", "haze", "smoke",
            ]
        )
    }

    /// Applies silent Shift-S numeric entry to fan/blower speed on capable fixtures.
    func setSelectedFanSpeed(percent: Int) {
        setSelectedDeviceFunction(
            percent: percent,
            preferredAttributes: ["fanSpeed", "fan_speed", "blowerSpeed", "fan", "blower"]
        )
    }

    private func setSelectedDeviceFunction(percent: Int, preferredAttributes: [String]) {
        let fixtureIDs = session.selection.snapshot.orderedFixtureIDs
        guard !fixtureIDs.isEmpty else { return }
        let caps = ProgrammerAttributePresentationResolver.physicalCapabilityMap(
            orderedFixtureIDs: fixtureIDs,
            project: session.project
        )
        var resolved = engine.currentResolvedSnapshot().programmerLook.fixtureAttributes
        for (fixtureID, attributes) in engine.programmer.snapshot().values {
            var merged = resolved[fixtureID] ?? [:]
            merged.merge(attributes) { _, programmerValue in programmerValue }
            resolved[fixtureID] = merged
        }

        let normalizedPreference = preferredAttributes.map { $0.lowercased() }
        var attributesByFixture: [UUID: String] = [:]
        var current: [UUID: Double] = [:]
        for fixtureID in fixtureIDs {
            let supported = caps[fixtureID] ?? []
            guard let attribute = normalizedPreference.compactMap({ wanted in
                supported.first { $0.lowercased() == wanted }
            }).first else { continue }
            attributesByFixture[fixtureID] = attribute
            current[fixtureID] = resolved[fixtureID]?[attribute] ?? 0
        }
        guard !current.isEmpty else { return }

        let shifted = ProgrammerIntensityGroup.shiftedValues(
            current,
            toAverage: Double(min(100, max(0, percent))) / 100
        )
        var batch: [UUID: [String: Double]] = [:]
        for (fixtureID, value) in shifted {
            if let attribute = attributesByFixture[fixtureID] {
                batch[fixtureID] = [attribute: value]
            }
        }
        engine.programmer.setMany(batch)
        noteProgrammerUIChanged()
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
        switch await document.promptDirtyDocumentDecision(actionName: actionName) {
        case .proceedClean, .discard:
            return true
        case .save:
            return await saveShowAsync(presentErrorsAsModal: true)
        case .cancel:
            return false
        }
    }

    /// Stop periodic autosave so it cannot contend with a quit-time manual save.
    func stopAutosaveForQuit() {
        autosave.stop()
    }

    /// Mark quit accepted so floating-window teardown does not rewrite docked layout.
    func noteTerminationAccepted() {
        isTerminating = true
        workspace.flushFloatPersistence()
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
        panel.message = "Prism native JSON, OFL-lite, or Prism converter (.prism-fixture.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try document.importFixtureDefinitions(from: url)
            reloadEngine()
            notifyUI()
        } catch {
            document.statusMessage = PrismErrorReporting.userFacingMessage(for: error)
            document.presentError(error, title: "Import Failed")
        }
    }

    func createUserFixture(_ definition: FixtureDefinition) throws {
        _ = try document.importFixtureDefinitions([definition], sourceName: "Fixture Creator")
        notifyUI()
    }

    /// Commits reviewed LightKey personalities and refreshes fixture-dependent runtime state.
    func importLightKeyFixtureDefinitions(
        _ definitions: [FixtureDefinition],
        sourceName: String
    ) throws -> Int {
        let count = try document.importFixtureDefinitions(definitions, sourceName: sourceName)
        reloadEngine()
        notifyUI()
        return count
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
        panel.title = "Open Prism Project"
        panel.message = "Choose a .prism project or legacy .aurora project"
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
            RecentProjectStore.note(url)
            if ProjectPackage.isLegacyPackageURL(url) {
                await promptToMigrateLegacyProject()
            }
        } catch {
            document.statusMessage = PrismErrorReporting.userFacingMessage(for: error)
            document.presentError(error, title: "Open Failed")
        }
    }

    /// Shared post-replace: reset document-scoped UI + reload engine (UI-02 B2).
    private func afterDocumentReplaced() {
        workspace.didReplaceDocument(project: session.project)
        // DOC-01: successful New/Open/Demo leaves Welcome for Build.
        workspace.enterDocumentWorkspace()
        reloadEngine()
        showControl.noteAuthoritativeCommit(replacingUniverse: true)
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
    func saveShowAsync(presentErrorsAsModal: Bool = true) async -> Bool {
        // Programmer is engine-ephemeral until recorded into a cue. Offer to bridge
        // the live look into the show document before writing the package.
        guard ensureProgrammerLookHandledBeforeSave(presentErrorsAsModal: presentErrorsAsModal) else {
            return false
        }
        if let documentURL = document.documentURL {
            if ProjectPackage.isLegacyPackageURL(documentURL) {
                return await migrateLegacyProjectOnSave(
                    from: documentURL,
                    presentErrorsAsModal: presentErrorsAsModal
                )
            }
            return await saveAsync(to: documentURL, presentErrorsAsModal: presentErrorsAsModal)
        }
        return await saveShowAsAsync(presentErrorsAsModal: presentErrorsAsModal)
    }

    /// When the programmer holds a look, prompt to Update/Record a cue before Save.
    /// Returns `false` if the user cancels (Save aborted).
    @discardableResult
    func ensureProgrammerLookHandledBeforeSave(presentErrorsAsModal: Bool = true) -> Bool {
        let levels = engine.programmer.captureLevels()
        guard !ProgrammerCueBridge.levelsAreEmpty(levels) else { return true }

        if !presentErrorsAsModal {
            // Quit path without modals: still prefer updating a target cue when possible
            // so the look is not silently discarded; otherwise save show only.
            if applyProgrammerLevelsToUpdateTarget(levels) != nil {
                document.statusMessage = "Saved look into cue before package write"
                return true
            }
            document.statusMessage = "Saving show without recording programmer look"
            return true
        }

        let preferredCueID = performance.playbackCueID ?? performance.currentCue.cueID
        let preferredListID = performance.cueListID ?? performance.currentCue.listID
        let updateTarget = ProgrammerCueBridge.resolveUpdateTarget(
            project: session.project,
            preferredListID: preferredListID,
            preferredCueID: preferredCueID
        )
        // Fallback: first cue in project when playback has no cue id yet.
        let target = updateTarget ?? ProgrammerCueBridge.resolveUpdateTarget(
            project: session.project,
            preferredListID: session.project.cueLists.first?.id,
            preferredCueID: session.project.cueLists.first?.cues.first?.id
        )
        let canRecord = ProgrammerCueBridge.resolveRecordList(
            project: session.project,
            preferredListID: performance.cueListID ?? session.project.cueLists.first?.id
        ) != nil

        let alert = NSAlert()
        alert.messageText = "Store live programmer look in the show?"
        alert.informativeText = """
        Color and intensity from the Programmer are not stored in the project file until they are recorded into a cue.

        \(levels.fixtures.count) fixture(s) have live values. Choose how to continue before saving.
        """
        alert.alertStyle = .informational

        // Button order is product decision mapping (alert returns first/second/…).
        var buttonMap: [NSApplication.ModalResponse: ProgrammerCueBridge.SaveLookDecision] = [:]
        if let target {
            alert.addButton(withTitle: "Update “\(target.cue.name.isEmpty ? "Cue" : target.cue.name)”")
            buttonMap[.alertFirstButtonReturn] = .updateTargetCue
            alert.addButton(withTitle: "Record New Cue")
            buttonMap[.alertSecondButtonReturn] = .recordNewCue
            alert.addButton(withTitle: "Save Without Look")
            buttonMap[.alertThirdButtonReturn] = .saveWithoutLook
            alert.addButton(withTitle: "Cancel")
            // Fourth button uses alertThirdButtonReturn + 1 in AppKit.
            buttonMap[NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1)] = .cancel
        } else if canRecord {
            alert.addButton(withTitle: "Record New Cue")
            buttonMap[.alertFirstButtonReturn] = .recordNewCue
            alert.addButton(withTitle: "Save Without Look")
            buttonMap[.alertSecondButtonReturn] = .saveWithoutLook
            alert.addButton(withTitle: "Cancel")
            buttonMap[.alertThirdButtonReturn] = .cancel
        } else {
            alert.informativeText += "\n\nThis show has no cue list yet. Create a cue list, or save without storing the look."
            alert.addButton(withTitle: "Save Without Look")
            buttonMap[.alertFirstButtonReturn] = .saveWithoutLook
            alert.addButton(withTitle: "Cancel")
            buttonMap[.alertSecondButtonReturn] = .cancel
        }

        let response = alert.runModal()
        let decision = buttonMap[response] ?? .cancel

        switch decision {
        case .updateTargetCue:
            if let name = applyProgrammerLevelsToUpdateTarget(levels) {
                document.statusMessage = "Updated \(name) from programmer"
                notifyUI()
                return true
            }
            document.statusMessage = "Could not update cue — save cancelled"
            return false
        case .recordNewCue:
            if let name = applyProgrammerLevelsAsNewCue(levels) {
                document.statusMessage = "Recorded \(name) from programmer"
                notifyUI()
                return true
            }
            document.statusMessage = "Could not record cue — save cancelled"
            return false
        case .saveWithoutLook:
            document.statusMessage = "Saving show without programmer look"
            return true
        case .cancel:
            return false
        }
    }

    /// Applies captured levels to the best-effort update target. Returns cue name on success.
    @discardableResult
    func applyProgrammerLevelsToUpdateTarget(_ levels: CueLevelData) -> String? {
        let target = ProgrammerCueBridge.resolveUpdateTarget(
            project: session.project,
            preferredListID: performance.cueListID ?? session.project.cueLists.first?.id,
            preferredCueID: performance.playbackCueID
                ?? session.project.cueLists.first?.cues.first?.id
        )
        guard let target else { return nil }
        let updated = ProgrammerCueBridge.cueByApplyingLevels(target.cue, levels: levels)
        do {
            try session.perform(UpdateCueCommand(listID: target.listID, cue: updated))
            applyProjectUpdate()
            return updated.name.isEmpty ? "cue" : updated.name
        } catch {
            document.statusMessage = PrismErrorReporting.statusMessage(for: error, operation: "update cue")
            return nil
        }
    }

    /// Records a new cue with captured levels. Returns cue name on success.
    @discardableResult
    func applyProgrammerLevelsAsNewCue(_ levels: CueLevelData) -> String? {
        guard let list = ProgrammerCueBridge.resolveRecordList(
            project: session.project,
            preferredListID: performance.cueListID ?? session.project.cueLists.first?.id
        ) else { return nil }
        let cue = ProgrammerCueBridge.makeRecordedCue(
            levels: levels,
            list: list,
            preferences: session.project.preferences
        )
        do {
            try session.perform(AddCueCommand(listID: list.id, cue: cue))
            applyProjectUpdate()
            return cue.name
        } catch {
            document.statusMessage = PrismErrorReporting.statusMessage(for: error, operation: "record cue")
            return nil
        }
    }

    @discardableResult
    private func saveShowAsAsync(
        presentErrorsAsModal: Bool = true,
        suggestedURL: URL? = nil,
        isLegacyMigration: Bool = false
    ) async -> Bool {
        let panel = NSSavePanel()
        panel.title = isLegacyMigration ? "Migrate to Prism" : "Save Prism Project"
        panel.message = isLegacyMigration
            ? "Save the migrated Prism project. The original .aurora project will remain unchanged."
            : nil
        panel.directoryURL = suggestedURL?.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedURL?.lastPathComponent
            ?? "\(session.project.metadata.name).\(ProjectPackage.packageExtension)"
        panel.allowedContentTypes = [UTType(importedAs: "com.aurora.show-package")]
        panel.prompt = isLegacyMigration ? "Migrate" : "Save"
        // App-modal is reliable after the quit dirty sheet has dismissed (`Task.yield` in finishQuit).
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let packageURL = url.pathExtension.lowercased() == ProjectPackage.packageExtension
            ? url
            : url.appendingPathExtension(ProjectPackage.packageExtension)
        return await saveAsync(to: packageURL, presentErrorsAsModal: presentErrorsAsModal)
    }

    /// Legacy projects remain untouched when opened. Choosing migration—or the first
    /// subsequent Save—uses a prefilled save panel for sandbox authorization, writes a
    /// `.prism` package, and moves the live document there.
    private func promptToMigrateLegacyProject() async {
        let alert = NSAlert()
        alert.messageText = "Migrate this project to Prism?"
        alert.informativeText = "This legacy .aurora project can be opened normally. Saving changes will create a .prism project and preserve the original file."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Migrate Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let legacyURL = document.documentURL {
            _ = await migrateLegacyProjectOnSave(from: legacyURL, presentErrorsAsModal: true)
        }
    }

    private func migrateLegacyProjectOnSave(
        from legacyURL: URL,
        presentErrorsAsModal: Bool
    ) async -> Bool {
        let proposedURL = ProjectPackage.preferredPackageURL(for: legacyURL)

        // Opening a package grants access to that package, not necessarily to create a
        // sibling in its parent directory. NSSavePanel grants the required destination
        // security scope and also prevents accidental overwrite without confirmation.
        return await saveShowAsAsync(
            presentErrorsAsModal: presentErrorsAsModal,
            suggestedURL: proposedURL,
            isLegacyMigration: true
        )
    }

    @discardableResult
    private func saveAsync(to url: URL, presentErrorsAsModal: Bool = true) async -> Bool {
        do {
            try await document.save(to: url)
            notifyUI()
            return !document.isDirty
        } catch {
            document.statusMessage = PrismErrorReporting.userFacingMessage(for: error)
            if presentErrorsAsModal {
                document.presentError(error, title: "Save Failed")
            } else {
                _ = PrismErrorReporting.report(error: error, context: .projectSave())
            }
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

    func setEffectsStagePreview(_ effect: EffectInstance?) {
        effectsStagePreviewEffect = effect
        notifyUI()
    }

    func setEffectsStagePreviewEnabled(_ enabled: Bool) {
        effectsStagePreviewEnabled = enabled
        notifyUI()
    }

    /// Semantic stage preview from engine's authoritative resolved frame (Pass-1 A5 fix).
    /// Does **not** re-run playback/effects in AppModel.
    func stagePreviewSnapshot() -> StagePreviewSnapshot {
        let resolved = engine.currentResolvedSnapshot()
        if effectsStagePreviewEnabled, let effect = effectsStagePreviewEffect {
            let preview = engine.evaluateEffectPreview(
                effect,
                time: ProcessInfo.processInfo.systemUptime,
                baseLook: resolved.presentationLook
            )
            return StagePreviewBuilder.build(
                project: session.project,
                look: preview.semanticLook,
                frameIndex: resolved.frameIndex,
                time: resolved.timestamp,
                global: .init()
            )
        }
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
        panel.title = "Export Prism Library"
        panel.nameFieldStringValue = "\(session.project.metadata.name).\(AuroraLibraryPackage.packageExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: AuroraLibraryPackage.packageExtension) ?? .folder]
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
        panel.title = "Import Prism Library"
        panel.message = "Choose a .prismlib library or legacy .auroralib library"
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
        input.setRTPMIDIEnabled(enabled)
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
                PrismLog.debug(.controlOSC, "control.osc.dispatch", "OSC dispatched an action.")
                self?.notifyUI()
            }
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
            PrismLog.notice(
                .engineShow,
                "engine.show.started",
                "The show engine frame rate is \(Int(clamped)) Hz.",
                metadata: ["frameRateHz": .double(clamped, privacy: .public)]
            )
        } catch {
            // Still set metrics target if restart failed mid-flight.
            showControl.engine.frameMetrics.setTargetPeriodMs((1.0 / max(1, clamped)) * 1000)
            PrismLog.error(
                .engineShow,
                "engine.show.start_failed",
                "Prism couldn't apply the new frame rate.",
                technical: String(reflecting: error)
            )
        }
    }

    /// BLOCKER-1 / UI-GATE-7: autosave through `ProjectSaveCoordinator` (serialized per destination).
    private func performBackgroundAutosave() async {
        guard document.documentURL != nil, document.isDirty else { return }
        let cleaned = await document.autosaveIfPossible()
        if document.autosaveDisabledAfterFailures {
            autosave.isEnabled = false
            autosave.stop()
        }
        if cleaned {
            notifyUI()
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
        output.setArtNetEnabled(enabled, engineRunning: engine.isRunning)
        notifyUI()
    }

    func setArtNetDestination(_ host: String) {
        output.setArtNetDestination(host, engineRunning: engine.isRunning)
        notifyUI()
    }

    func setSACNEnabled(_ enabled: Bool) {
        output.setSACNEnabled(enabled, engineRunning: engine.isRunning)
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
        PrismLog.info(.appLifecycle, "app.lifecycle.launch", message)
        notifyUI()
    }

    // MARK: - Remote

    func publishACPState() async {
        let node = await acp.service.diagnostics().nodeID
        guard !node.isEmpty else { return }
        let state = PrismACPAuthoritativeState(
            authorityEpoch: 1,
            revision: 1,
            showID: session.project.workspaceLayoutId?.uuidString.lowercased()
                ?? PrismACPDiagnosticIdentifier.stableUUID(seed: document.documentURL?.standardizedFileURL.path ?? session.project.metadata.name),
            showName: session.project.metadata.name
        )
        _ = node
        await acp.service.noteAuthoritativeState(state)
    }

    /// Authoritative remote enable path. Starts ACP only; never the legacy TCP/HTTP stack.
    func applyRemoteFromSettings(enabled: Bool? = nil) {
        if let enabled {
            settings.remoteAccessEnabled = enabled
            settings.save()
        }
        let on = settings.remoteAccessEnabled
        let discovery = settings.acpDiscoveryEnabled
        let port = settings.acpPort
        Task { @MainActor in
            await acp.apply(
                enabled: on,
                discovery: discovery,
                port: port
            )
            if on {
                await publishACPState()
            }
            notifyUI()
        }
    }

    func setRemoteEnabled(_ enabled: Bool) {
        applyRemoteFromSettings(enabled: enabled)
    }

    func kickAllRemoteClients() {
        Task { @MainActor in
            await acp.stop()
            if settings.remoteAccessEnabled {
                await acp.setEnabled(true)
            }
            notifyUI()
        }
    }

    /// Orderly teardown (PRE-UI-3). Idempotent.
    private var didShutdown = false

    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        isTerminating = true
        PrismLog.notice(.appLifecycle, "app.lifecycle.terminate", "Prism is quitting.")
        floatWindows.closeAllWindows()
        autosave.stop()
        // UI11-05 / C5.1: flush layout + float frames; do not redock floats on quit.
        workspace.flushLayoutPersistence()
        diagnostics.stopLiveUpdates()
        showControl.stopTimers()
        input.stopAll()
        output.stopAll()
        Task { await acp.stop() }
    }

    // MARK: - C5.1 unified undock / redock (state + exact window)

    /// Undock with a consistent default frame and open path (panel chrome + View menu).
    func undockSurface(_ surface: FloatSurfaceID, preferredScreen: NSScreen? = nil) {
        let defaults = AuroraScreenIdentity.defaultFrame(for: surface, preferredScreen: preferredScreen)
        // Prefer last stored frame when re-undocking the same surface.
        let stored = workspace.floatState.record(for: surface).frame
        let frame: CGRect
        if let stored, stored.width > 100, stored.height > 100 {
            frame = stored
        } else {
            frame = defaults.frame
        }
        let screenID = workspace.floatState.record(for: surface).screenID ?? defaults.screenID
        let screenName = workspace.floatState.record(for: surface).screenName ?? defaults.screenName
        workspace.undock(surface, frame: frame, screenID: screenID, screenName: screenName)
        PrismLog.info(.appWindowing, "app.windowing.surface_opened", "A floating workspace window opened.")
        notifyUI()
    }

    /// Redock and close the exact registered floating window (no title scanning).
    func redockSurface(_ surface: FloatSurfaceID) {
        workspace.redock(surface)
        floatWindows.closeWindow(for: surface)
        notifyUI()
    }

    /// Single Screen is both a persistence policy and an immediate workspace action.
    /// Multi Screen preserves the current arrangement and restores it on the next launch.
    func setWorkspaceScreenMode(_ mode: WorkspaceScreenMode) {
        workspace.setScreenMode(mode)
        if mode == .single {
            for surface in FloatSurfaceID.allCases where workspace.isFloating(surface) {
                redockSurface(surface)
            }
        }
        notifyUI()
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
            remoteStatus: acp.status,
            remoteActuallyRunning: acp.isRunning,
            remoteClientCount: 0,
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
