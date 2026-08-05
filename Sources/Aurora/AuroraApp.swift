import SwiftUI

/// macOS application entry point (system design name: AuroraApp).
@main
struct AuroraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 480, height: 420)
    }
}
