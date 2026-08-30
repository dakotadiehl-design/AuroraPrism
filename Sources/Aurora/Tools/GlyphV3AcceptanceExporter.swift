import AppKit
import AuroraCore
import AuroraEngine
import AuroraModel
import AuroraUI
import SwiftUI

/// Captures the production Stage host with both renderer styles against the
/// repository's real fixture projects.
@MainActor
enum GlyphV3AcceptanceExporter {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--export-glyph-v3-acceptance") else { return }
        let output = args.indices.contains(index + 1)
            ? URL(fileURLWithPath: args[index + 1], isDirectory: true)
            : URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prism-glyph-v3-acceptance")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            try captureProject(
                repository.appendingPathComponent("smoketest files/Test Show.prism"),
                name: "test-show",
                output: output
            )
            try captureProject(
                repository.appendingPathComponent("smoketest files/HaywireFullRig.prism"),
                name: "haywire-full-rig",
                output: output
            )
            fputs("Glyph V3 acceptance screenshots written to \(output.path)\n", stderr)
            NSApp.terminate(nil)
        } catch {
            fputs("Glyph V3 acceptance export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func captureProject(_ url: URL, name: String, output: URL) throws {
        let project = try ProjectPackage.load(from: url)
        let session = DocumentSession(project: project)
        let context = WorkspacePanelContext(session: session)
        let selected = Array(project.stageLayout.fixtures.prefix(3).map(\.fixtureID))
        session.selectFixtures(Set(selected), extending: false)

        var attributes: [UUID: [String: Double]] = [:]
        for (index, fixture) in project.fixtures.enumerated() {
            let colors: [(Double, Double, Double)] = [(0.72, 0.12, 1), (0.05, 0.8, 1), (1, 0.45, 0.05), (0.15, 1, 0.4)]
            let color = colors[index % colors.count]
            attributes[fixture.id] = [
                "intensity": 0.35 + Double(index % 4) * 0.2,
                "colorR": color.0,
                "colorG": color.1,
                "colorB": color.2,
            ]
        }
        let preview = StagePreviewBuilder.build(
            project: project,
            look: ActiveLook(fixtureAttributes: attributes),
            frameIndex: 1,
            time: 0,
            global: .default
        )
        for style in StageGlyphStyle.allCases {
            try render(
                name: "\(name)-\(style.rawValue)",
                output: output,
                content: StagePanel(
                    context: context,
                    preview: preview,
                    onLayoutChanged: {},
                    onSelectFixtures: { _ in },
                    glyphStyle: style
                )
            )
        }
    }

    private static func render<V: View>(name: String, output: URL, content: V) throws {
        let size = CGSize(width: 1440, height: 900)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            window.orderOut(nil)
            throw ExportError.capture(name)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.capture(name)
        }
        try data.write(to: output.appendingPathComponent("\(name).png"))
    }

    private enum ExportError: Error { case capture(String) }
}
