import AppKit
import AuroraUI
import SwiftUI

final class AuroraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AuroraApp: App {
    @NSApplicationDelegateAdaptor(AuroraAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Show") {
                    appModel.newShow()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open…") {
                    appModel.openShow()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save") {
                    appModel.saveShow()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    appModel.saveShowAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Import Fixture Definition…") {
                    appModel.importFixtureDefinition()
                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo \(appModel.session.undoActionName ?? "")") {
                    appModel.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appModel.session.canUndo)

                Button("Redo \(appModel.session.redoActionName ?? "")") {
                    appModel.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appModel.session.canRedo)
            }

            CommandMenu("View") {
                ForEach(WorkspacePanelID.allCases) { panel in
                    Button {
                        appModel.togglePanel(panel)
                    } label: {
                        HStack {
                            Text(panel.title)
                            if appModel.layout.isVisible(panel) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            CommandMenu("Playback") {
                Button("Go") { appModel.go() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Go") { appModel.go() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("Stop") { appModel.stopPlayback() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Back") { appModel.back() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Back") { appModel.back() }
                    .keyboardShortcut("b", modifiers: [])
            }

            CommandMenu("MIDI") {
                Button(appModel.rtpMIDI.configSnapshot.enabled ? "Disable RTP-MIDI" : "Enable RTP-MIDI") {
                    appModel.setRTPMIDIEnabled(!appModel.rtpMIDI.configSnapshot.enabled)
                }
                Button(appModel.isOSCEnabled ? "Disable OSC" : "Enable OSC (UDP 9000)") {
                    appModel.setOSCEnabled(!appModel.isOSCEnabled)
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
            }
        }
    }
}

