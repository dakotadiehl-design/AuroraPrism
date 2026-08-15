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
        // PRE-UI-3 / BLOCKER-1: await save via coordinator, then orderly shutdown.
        Task { @MainActor in
            let proceed = await appModel.prepareToTerminate()
            if proceed {
                appModel.shutdown()
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.shutdown()
    }

    /// Finder / Launch Services double-click of a `.aurora` package.
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
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
                        }
                    } else {
                        applyBuildWorkspaceLaunchArg()
                    }
                }
        }
        .defaultSize(width: 1280, height: 800)
        Settings {
            // Pass by value/reference without EnvironmentObject on the TabView shell —
            // high-frequency AppModel polls must not rebuild SF Symbol tab items.
            AuroraSettingsRoot(appModel: appModel)
        }
        .commands {
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

                    Button("Export Aurora Library…") {
                        appModel.exportLibraryPanel()
                    }
                    Button("Import Aurora Library…") {
                        appModel.importLibraryPanel()
                    }

                    Divider()

                    Button("Open Demo Show (Summer Night)") {
                        Task { @MainActor in await appModel.openDemoSummerNightAsync() }
                    }
                    .keyboardShortcut("d", modifiers: [.command, .shift])

                    Divider()

                    Button("Import Fixture Definition…") {
                        appModel.importFixtureDefinition()
                    }
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
                        for id: WorkspacePanelID in [.cueList, .palettes, .song, .console] {
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
                Button(appModel.rtpMIDI.configSnapshot.enabled ? "Disable RTP-MIDI" : "Enable RTP-MIDI") {
                    appModel.setRTPMIDIEnabled(!appModel.rtpMIDI.configSnapshot.enabled)
                }
                Button(appModel.isOSCEnabled ? "Disable OSC" : "Enable OSC (UDP 9000)") {
                    appModel.setOSCEnabled(!appModel.isOSCEnabled)
                }
            }

            CommandMenu("Remote") {
                Button(appModel.settings.remoteAccessEnabled ? "Disable Remote" : "Enable Remote") {
                    // REM-05: menu uses the same settings-backed authority as Settings.
                    appModel.applyRemoteFromSettings(enabled: !appModel.settings.remoteAccessEnabled)
                }
                Button("Lock Remotes to Viewer") {
                    appModel.setRemoteLockedToViewer(true)
                }
                Button("Allow Remote Operators") {
                    appModel.setRemoteLockedToViewer(false)
                }
                Button("Kick All Remote Clients") {
                    appModel.kickAllRemoteClients()
                }
            }

            CommandMenu("Output") {
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
