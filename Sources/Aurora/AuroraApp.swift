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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear {
                    appDelegate.appModel = appModel
                    // UI-02 C1: no DEBUG auto-demo. Explicit File / Welcome only.
                    // Optional automation: --load-demo-show launch argument.
                    if ProcessInfo.processInfo.arguments.contains("--load-demo-show") {
                        Task { @MainActor in
                            await appModel.openDemoSummerNightAsync()
                        }
                    }
                }
        }
        .defaultSize(width: 1280, height: 800)
        Settings {
            AuroraSettingsRoot()
                .environmentObject(appModel)
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

            CommandMenu("View") {
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
                    Button("Browser") {
                        appModel.workspace.setLeftTool(.browser)
                        appModel.notifyUI()
                    }
                    Button("Patch") {
                        appModel.workspace.setLeftTool(.patch)
                        appModel.notifyUI()
                    }
                    Button("Groups") {
                        appModel.workspace.setLeftTool(.groups)
                        appModel.notifyUI()
                    }
                    Divider()
                    Button("Palettes") {
                        appModel.workspace.setLowerTool(.palettes)
                        appModel.notifyUI()
                    }
                    Button("Cues") {
                        appModel.workspace.setLowerTool(.cues)
                        appModel.notifyUI()
                    }
                    Button("Song") {
                        appModel.workspace.setLowerTool(.song)
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
                Button(appModel.remoteHost.sessions.configSnapshot.enabled ? "Disable Remote" : "Enable Remote (random PIN)") {
                    let on = appModel.remoteHost.sessions.configSnapshot.enabled
                    appModel.setRemoteEnabled(!on)
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
