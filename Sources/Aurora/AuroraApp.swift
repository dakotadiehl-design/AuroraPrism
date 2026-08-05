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
        }
    }
}
