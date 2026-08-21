import AppKit
import AuroraDiagnostics
import Foundation

/// Captures the actual running Effects NSWindow for visual acceptance automation.
/// Unlike component exporters, this reads the laid-out production window tree.
@MainActor
enum EffectsWindowAcceptanceCapture {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--capture-effects-window"),
              arguments.indices.contains(flag + 1) else { return }
        let outputURL = URL(fileURLWithPath: arguments[flag + 1])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let window = NSApp.windows.first(where: { $0.title.contains("Prism Effects") }),
                  let contentView = window.contentView else { return }
            window.orderFrontRegardless()
            contentView.layoutSubtreeIfNeeded()
            guard let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
            contentView.cacheDisplay(in: contentView.bounds, to: representation)
            guard let data = representation.representation(using: .png, properties: [:]) else { return }
            do {
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: outputURL, options: .atomic)
            } catch {
                PrismLog.error(
                    .appWindowing,
                    "effects.capture.failed",
                    "Effects acceptance capture failed",
                    metadata: ["error": .public(String(describing: error))]
                )
            }
        }
    }
}
