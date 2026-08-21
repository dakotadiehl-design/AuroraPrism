import AuroraDesignSystem
import AppKit
import AuroraUI
import SwiftUI

final class AuroraAppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appModel else { return .terminateNow }

        // PRE-UI-3 / BLOCKER-1 — AppKit-driven quit with a reliable dirty prompt.
        //
        // Always hop via `DispatchQueue.main.async` so we return `.terminateLater` first,
        // then present an **app-modal** `NSAlert.runModal()` on the next turn.
        // Window sheets (`beginSheetModal`) often fail to appear during terminate (no
        // save dialog when the show is dirty). App-modal runModal is the dependable path.
        DispatchQueue.main.async { [weak self, weak appModel] in
            guard let self, let appModel else {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            self.handleQuitOnMain(appModel: appModel)
        }
        return .terminateLater
    }

    /// Runs only after `applicationShouldTerminate` has returned `.terminateLater`.
    private func handleQuitOnMain(appModel: AppModel) {
        // AppModel is @MainActor; we are on the main queue.
        let dirty = MainActor.assumeIsolated { appModel.document.isDirty }
        if !dirty {
            MainActor.assumeIsolated {
                appModel.noteTerminationAccepted()
                // Shut down hardware *before* replying so ENTTEC blackout/close completes.
                appModel.shutdown()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        MainActor.assumeIsolated { appModel.stopAutosaveForQuit() }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this show before quitting?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        // App-modal — always visible during quit (unlike document sheets).
        let response = alert.runModal()
        Task { @MainActor in
            await self.finishQuit(response: response, appModel: appModel)
        }
    }

    @MainActor
    private func finishQuit(response: NSApplication.ModalResponse, appModel: AppModel) async {
        switch response {
        case .alertFirstButtonReturn:
            // Modal must fully dismiss before Save As panel or package I/O.
            await Task.yield()
            let saved = await appModel.saveShowAsync(presentErrorsAsModal: true)
            if saved {
                appModel.noteTerminationAccepted()
                appModel.shutdown()
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                // Stay alive so the user can retry or discard explicitly.
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        case .alertSecondButtonReturn:
            appModel.noteTerminationAccepted()
            appModel.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        default:
            NSApp.reply(toApplicationShouldTerminate: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Idempotent — usually already ran from finishQuit / clean-quit path.
        appModel?.shutdown()
    }

    /// Finder / Launch Services double-click of a Prism or legacy Aurora package.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let appModel else { return }
        for url in urls {
            Task { @MainActor in
                await appModel.openShow(at: url)
            }
        }
    }
}

@main
struct AuroraApp: App {
    @NSApplicationDelegateAdaptor(AuroraAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    private var isPerform: Bool { appModel.workspace.mode == .perform }
    private var textEditing: Bool { KeyboardCommandGate.isTextEditingActive }

    private func revealCueBlocksShelf() {
        // Make the target visible before broadcasting the request. The asynchronous
        // notification gives SwiftUI one update cycle to install CueBlocksPanel when needed.
        appModel.workspace.setBuildWorkspaceMode(.program)
        appModel.workspace.setLowerTool(.cueBlocks)
        if !appModel.workspace.layout.isVisible(.cueList)
            && !appModel.workspace.layout.isVisible(.cueBlocks)
            && !appModel.workspace.layout.isVisible(.palettes)
            && !appModel.workspace.layout.isVisible(.song)
            && !appModel.workspace.layout.isVisible(.console) {
            appModel.workspace.togglePanel(.cueBlocks)
        }
        appModel.workspace.setLowerShelfCollapsed(false)
        appModel.notifyUI()
    }

    private func requestNewCueBlock() {
        revealCueBlocksShelf()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .prismCreateCueBlock, object: nil)
        }
    }

    private func requestNewCueBlockGroup() {
        revealCueBlocksShelf()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .prismCreateCueBlockGroup, object: nil)
        }
    }

    /// Automation: `--build-workspace patch|program|stage|profiles`
    private func applyBuildWorkspaceLaunchArg() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--build-workspace"),
              args.indices.contains(i + 1) else { return }
        let raw = args[i + 1].lowercased()
        let mode: BuildWorkspaceMode?
        switch raw {
        case "patch": mode = .patch
        case "program": mode = .program
        case "stage": mode = .stage
        case "profiles": mode = .profiles
        default: mode = nil
        }
        if let mode {
            appModel.workspace.setBuildWorkspaceMode(mode)
            appModel.notifyUI()
        }
    }

    /// Visual-acceptance automation opens the production scene rather than a
    /// SwiftUI preview or component gallery.
    private func openEffectsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--open-effects-engine") else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openEffectsEngineWindow, object: nil)
            EffectsWindowAcceptanceCapture.runIfRequested()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                    // C5E / C5.1: recover floating windows onto per-screen visible frames.
                    appModel.workspace.recoverFloatingWindows(
                        to: AuroraScreenIdentity.currentVisibleScreens()
                    )
                    // Checkpoint B visual export (production PatchWorkspaceView composites).
                    if ProcessInfo.processInfo.arguments.contains("--export-checkpoint-b-shots") {
                        CheckpointBScreenshotExporter.runIfRequested()
                        return
                    }
                    // Checkpoint C1 — shared Stage canvas (Program embed + Stage host).
                    if ProcessInfo.processInfo.arguments.contains("--export-checkpoint-c1-shots") {
                        CheckpointC1ScreenshotExporter.runIfRequested()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--export-checkpoint-c2-shots") {
                        CheckpointC2ScreenshotExporter.runIfRequested()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--export-checkpoint-c3-shots") {
                        CheckpointC3ScreenshotExporter.runIfRequested()
                        return
                    }
                    // UI-02 C1: no DEBUG auto-demo. Explicit File / Welcome only.
                    // Optional automation: --load-demo-show launch argument.
                    if ProcessInfo.processInfo.arguments.contains("--load-demo-show") {
                        Task { @MainActor in
                            await appModel.openDemoSummerNightAsync()
                            applyBuildWorkspaceLaunchArg()
                            openEffectsIfRequested()
                        }
                    } else {
                        applyBuildWorkspaceLaunchArg()
                        openEffectsIfRequested()
                    }
                }
                .background(FloatWindowRestorer().environmentObject(appModel))
        }
        .defaultSize(width: 1280, height: 800)

        // Phase F: dedicated Advanced MIDI Engine window.
        Window("MIDI Engine", id: "ame-engine") {
            AMEEngineWindowRoot()
                .environmentObject(appModel)
                .buttonStyle(AuroraButtonStyle())
        }
        .defaultSize(width: 1024, height: 640)

        Window("Prism Effects", id: "effects-engine") {
            EffectsEngineWindowRoot()
                .environmentObject(appModel)
                .buttonStyle(AuroraButtonStyle())
        }
        .defaultSize(width: 1_440, height: 900)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)

        // C5C: real macOS windows for undocked workspace surfaces (shared AppModel).
        // contentMinSize = user can resize freely; content min comes from the view's min frame.
        WindowGroup(id: "float-surface", for: FloatSurfaceID.self) { $surface in
            if let surface {
                FloatingSurfaceWindow(surface: surface)
                    .environmentObject(appModel)
                    .buttonStyle(AuroraButtonStyle())
            }
        }
        .defaultSize(width: 720, height: 560)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("About Prism", id: "about-aurora") {
            AuroraAboutView()
                .buttonStyle(AuroraButtonStyle())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("LightKey Fixture Importer", id: "lightkey-fixture-importer") {
            LightKeyFixtureImporterWindowRoot()
                .environmentObject(appModel)
                .buttonStyle(AuroraButtonStyle())
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("User Fixture Library", id: "user-fixture-library") {
            UserFixtureLibraryWindow()
                .environmentObject(appModel)
                .buttonStyle(AuroraButtonStyle())
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("Create Fixture", id: "fixture-creator") {
            FixtureCreatorWindow()
                .environmentObject(appModel)
                .buttonStyle(AuroraButtonStyle())
        }
        .defaultSize(width: 860, height: 700)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commandsRemoved()

        WindowGroup("DMX Monitor", id: "dmx-monitor", for: DMXMonitorRequest.self) { $request in
            DMXMonitorWindow(request: request ?? DMXMonitorRequest())
                .environmentObject(appModel)
                .buttonStyle(AuroraButtonStyle())
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)
        .commandsRemoved()

        Settings {
            // Pass by value/reference without EnvironmentObject on the TabView shell —
            // high-frequency AppModel polls must not rebuild SF Symbol tab items.
            AuroraSettingsRoot(appModel: appModel)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutAuroraMenuButton()
            }

            CommandGroup(replacing: .newItem) {
                if !isPerform {
                    Button("New Show") {
                        Task { @MainActor in await appModel.newShowAsync() }
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    Button("Open…") {
                        Task { @MainActor in await appModel.openShowAsync() }
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }

                Button("Save") {
                    appModel.saveShow()
                }
                .keyboardShortcut("s", modifiers: .command)

                if !isPerform {
                    Button("Save As…") {
                        appModel.saveShowAs()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Divider()

                    Button("Export Prism Library…") {
                        appModel.exportLibraryPanel()
                    }
                    Button("Import Prism Library…") {
                        appModel.importLibraryPanel()
                    }

                    Divider()

                    Button("Open Demo Show (Summer Night)") {
                        Task { @MainActor in await appModel.openDemoSummerNightAsync() }
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])

                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo \(appModel.session.undoActionName ?? "")") {
                    appModel.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appModel.session.canUndo || isPerform)

                Button("Redo \(appModel.session.redoActionName ?? "")") {
                    appModel.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appModel.session.canRedo || isPerform)
            }

            // C4.3: merge visibility into the system View menu — do not create CommandMenu("View").
            CommandGroup(after: .toolbar) {
                if !isPerform {
                    Button("Show Fixture Library") {
                        NotificationCenter.default.post(name: .openUserFixtureLibrary, object: nil)
                    }
                    Divider()
                    Button("Show Stage Preview") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setStagePreviewCollapsed(false)
                        appModel.notifyUI()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .control])
                    Button("Hide Stage Preview") {
                        appModel.workspace.setStagePreviewCollapsed(true)
                        appModel.notifyUI()
                    }
                    Divider()
                    Picker("Screen Mode", selection: Binding(
                        get: { appModel.workspace.screenMode },
                        set: { appModel.setWorkspaceScreenMode($0) }
                    )) {
                        ForEach(WorkspaceScreenMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Divider()
                    Menu("Move to Window") {
                        ForEach(FloatSurfaceID.allCases) { surface in
                            Button(surface.title) {
                                // C5.1: same undock path as panel chrome (default frame + open).
                                appModel.undockSurface(surface, preferredScreen: NSScreen.main)
                                // Window open is handled by FloatWindowRestorer via floatEpoch.
                            }
                            .disabled(appModel.workspace.isFloating(surface)
                                      || appModel.workspace.floatState.record(for: surface).kind == .hidden)
                        }
                    }
                    Menu("Dock in Main Window") {
                        ForEach(FloatSurfaceID.allCases) { surface in
                            Button(surface.title) {
                                // C5.1: redock + close exact registered NSWindow.
                                appModel.redockSurface(surface)
                            }
                            .disabled(!appModel.workspace.isFloating(surface))
                        }
                    }
                    Button("Show Inspector") {
                        if !appModel.workspace.layout.isVisible(.inspector) {
                            appModel.workspace.togglePanel(.inspector)
                            appModel.notifyUI()
                        }
                    }
                    Button("Hide Inspector") {
                        if appModel.workspace.layout.isVisible(.inspector) {
                            appModel.workspace.togglePanel(.inspector)
                            appModel.notifyUI()
                        }
                    }
                    Button("Collapse Lower Shelf") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLowerShelfCollapsed(true)
                        appModel.notifyUI()
                    }
                    Button("Expand Lower Shelf") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLowerShelfCollapsed(false)
                        appModel.notifyUI()
                    }
                    Button("Show Lower Region") {
                        if !appModel.workspace.layout.isVisible(.cueList) {
                            appModel.workspace.togglePanel(.cueList)
                            appModel.notifyUI()
                        }
                        appModel.workspace.setLowerShelfCollapsed(false)
                        appModel.notifyUI()
                    }
                    Button("Hide Lower Region") {
                        for id: WorkspacePanelID in [.cueList, .cueBlocks, .palettes, .song, .console] {
                            if appModel.workspace.layout.isVisible(id) {
                                appModel.workspace.togglePanel(id)
                            }
                        }
                        appModel.notifyUI()
                    }
                    Divider()
                    Menu("Layouts") {
                        Button("Programming") {
                            appModel.workspace.applyNamedBuildLayout("Programming")
                            appModel.notifyUI()
                        }
                        Button("Patch") {
                            appModel.workspace.applyNamedBuildLayout("Patch")
                            appModel.notifyUI()
                        }
                        Button("Song") {
                            appModel.workspace.applyNamedBuildLayout("Song")
                            appModel.notifyUI()
                        }
                        Button("Diagnostics") {
                            appModel.workspace.applyNamedBuildLayout("Diagnostics")
                            appModel.notifyUI()
                        }
                        Divider()
                        Button("Reset Layout") {
                            appModel.workspace.resetLayout()
                            appModel.notifyUI()
                        }
                    }
                    Menu("Design Layout") {
                        ForEach(DesignFocusPreset.allCases) { preset in
                            Button(preset.rawValue) {
                                appModel.workspace.setBuildWorkspaceMode(.program)
                                appModel.workspace.exitEditStage()
                                appModel.workspace.applyDesignFocus(preset)
                                appModel.notifyUI()
                            }
                        }
                    }
                }
            }

            // C4.3: major work-surface navigation lives in Workspace (not View).
            CommandMenu("Workspace") {
                Button("Build Mode") {
                    appModel.workspace.setMode(.build)
                    appModel.notifyUI()
                }
                Button("Perform Mode") {
                    appModel.workspace.setMode(.perform)
                    appModel.notifyUI()
                }
                if !isPerform {
                    Divider()
                    Button("Design") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.notifyUI()
                    }
                    .keyboardShortcut("1", modifiers: [.command, .control])
                    Button("Patch") {
                        appModel.workspace.setBuildWorkspaceMode(.patch)
                        appModel.notifyUI()
                    }
                    .keyboardShortcut("2", modifiers: [.command, .control])
                    Button("Stage") {
                        appModel.workspace.setBuildWorkspaceMode(.stage)
                        appModel.notifyUI()
                    }
                    .keyboardShortcut("3", modifiers: [.command, .control])
                    Button("Profiles") {
                        appModel.workspace.setBuildWorkspaceMode(.profiles)
                        appModel.notifyUI()
                    }
                    .keyboardShortcut("4", modifiers: [.command, .control])
                    Divider()
                    Button("Browser") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLeftTool(.browser)
                        appModel.notifyUI()
                    }
                    Button("Groups") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLeftTool(.groups)
                        appModel.notifyUI()
                    }
                    Button("Cue Blocks") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLowerTool(.cueBlocks)
                        appModel.notifyUI()
                    }
                    Button("Palettes") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLowerTool(.palettes)
                        appModel.notifyUI()
                    }
                    Button("Cues") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLowerTool(.cues)
                        appModel.notifyUI()
                    }
                    Button("Song") {
                        appModel.workspace.setBuildWorkspaceMode(.program)
                        appModel.workspace.setLowerTool(.song)
                        appModel.notifyUI()
                    }
                    Divider()
                    Button("New Cue Block…") {
                        requestNewCueBlock()
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(
                        textEditing
                            || appModel.session.selection.snapshot.orderedFixtureIDs.isEmpty
                    )
                    Button("New Cue Block Group…") {
                        requestNewCueBlockGroup()
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(textEditing)
                    Divider()
                    Button("Edit Stage") {
                        appModel.workspace.enterEditStage()
                        appModel.notifyUI()
                    }
                    .keyboardShortcut("e", modifiers: [.command, .control])
                    Button("Done Editing Stage") {
                        appModel.workspace.exitEditStage()
                        appModel.notifyUI()
                    }
                }
            }

            CommandMenu("Fixtures") {
                Button("Effects…") {
                    NotificationCenter.default.post(name: .openEffectsEngineWindow, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Create Fixture…") {
                    NotificationCenter.default.post(name: .openFixtureCreator, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(isPerform)

                Button("Fixture Library…") {
                    NotificationCenter.default.post(name: .openUserFixtureLibrary, object: nil)
                }
                .disabled(isPerform)

                Divider()

                Button("Import Fixture Definition…") {
                    appModel.importFixtureDefinition()
                }
                .disabled(isPerform)

                Button("Import LightKey Fixture…") {
                    NotificationCenter.default.post(name: .openLightKeyFixtureImporter, object: nil)
                }
                .disabled(isPerform)
            }

            CommandMenu("Playback") {
                Button("Go") {
                    if !KeyboardCommandGate.isTextEditingActive { appModel.go() }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(textEditing)
                Button("Go") {
                    if !KeyboardCommandGate.isTextEditingActive { appModel.go() }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(textEditing)
                Button("Stop") {
                    if !KeyboardCommandGate.isTextEditingActive { appModel.stopPlayback() }
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(textEditing)
                Button("Back") {
                    if !KeyboardCommandGate.isTextEditingActive { appModel.back() }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(textEditing)
                Button("Back") {
                    if !KeyboardCommandGate.isTextEditingActive { appModel.back() }
                }
                .keyboardShortcut("b", modifiers: [])
                .disabled(textEditing)
            }

            CommandMenu("MIDI") {
                Button("MIDI Engine…") {
                    NotificationCenter.default.post(name: .openAMEEngineWindow, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Button(appModel.rtpMIDI.configSnapshot.enabled ? "Disable RTP-MIDI" : "Enable RTP-MIDI") {
                    appModel.setRTPMIDIEnabled(!appModel.rtpMIDI.configSnapshot.enabled)
                }
                Button(appModel.isOSCEnabled ? "Disable OSC" : "Enable OSC (UDP 9000)") {
                    appModel.setOSCEnabled(!appModel.isOSCEnabled)
                }
            }

            CommandMenu("Remote") {
                Button(appModel.settings.remoteAccessEnabled ? "Disable ACP Remote" : "Enable ACP Remote") {
                    appModel.applyRemoteFromSettings(enabled: !appModel.settings.remoteAccessEnabled)
                }
                Button("Revoke All ACP Clients") {
                    appModel.kickAllRemoteClients()
                }
            }

            CommandMenu("Output") {
                Button("DMX Monitor…") {
                    NotificationCenter.default.post(name: .openDMXMonitor, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                Divider()
                Button(appModel.artNetConfig.enabled ? "Disable Art-Net" : "Enable Art-Net") {
                    appModel.setArtNetEnabled(!appModel.artNetConfig.enabled)
                }
                Button("Art-Net Destination…") {
                    appModel.promptArtNetDestination()
                }
                Divider()
                Button(appModel.sacnConfig.enabled ? "Disable sACN" : "Enable sACN") {
                    appModel.setSACNEnabled(!appModel.sacnConfig.enabled)
                }
                Button("sACN Destination…") {
                    appModel.promptSACNDestination()
                }
                Divider()
                Button("Local DMX Settings…") {
                    // Opens System Settings for Aurora (macOS Settings scene).
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            }
        }
    }
}
