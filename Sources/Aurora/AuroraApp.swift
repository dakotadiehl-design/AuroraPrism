import AppKit
import SwiftUI

/// Ensures SPM’s bare executable is treated as a normal GUI app (Dock + key window).
/// SwiftPM does not produce an `.app` bundle, so without this the process can run
/// with no visible window and no Dock icon.
final class AuroraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// macOS application entry point (system design name: AuroraApp).
@main
struct AuroraApp: App {
    @NSApplicationDelegateAdaptor(AuroraAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 480, height: 420)
    }
}
