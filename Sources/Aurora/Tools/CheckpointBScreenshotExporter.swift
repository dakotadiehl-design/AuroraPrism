import AuroraDesignSystem
import AppKit
import AuroraCore
import AuroraDiagnostics
import AuroraModel
import AuroraUI
import SwiftUI

/// One-shot Checkpoint B visual export of production `PatchWorkspaceView` states.
/// Invoked via launch argument: `--export-checkpoint-b-shots [dir]`
@MainActor
enum CheckpointBScreenshotExporter {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--export-checkpoint-b-shots") else { return }
        // Sandboxed app: prefer container Application Support (always writable).
        // Optional path after the flag is only honored when user-selected / already accessible.
        let containerBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var outDir = containerBase
            .appendingPathComponent("Aurora", isDirectory: true)
            .appendingPathComponent("checkpoint-b", isDirectory: true)
        if args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            let requested = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
            // Probe write access; fall back to container if sandboxed away.
            let probe = requested.appendingPathComponent(".write-probe")
            do {
                try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
                try Data().write(to: probe)
                try FileManager.default.removeItem(at: probe)
                outDir = requested
            } catch {
                fputs("Requested path not writable (sandbox); using \(outDir.path)\n", stderr)
            }
        }
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            try exportAll(to: outDir)
            // Mirror path marker for the orchestrator shell.
            let marker = outDir.appendingPathComponent("EXPORT_PATH.txt")
            try outDir.path.write(to: marker, atomically: true, encoding: .utf8)
            fputs("Checkpoint B screenshots written to \(outDir.path)\n", stderr)
            NSApp.terminate(nil)
        } catch {
            PrismLog.debug(.uiPresentation, "ui.presentation.export_failed", "A screenshot export failed.")
            fputs("Checkpoint B export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func exportAll(to dir: URL) throws {
        let demo = ShowProject.demoSummerNight()
        let empty = emptyProject()
        let multi = multiUniverseProject(from: demo)

        // 1. Empty universe
        try render(
            name: "01-empty-universe",
            project: empty,
            seed: PatchWorkspaceSeed(
                selectedDefinitionID: empty.fixtureDefinitions.first?.id
            ),
            to: dir
        )

        // 2. Populated universe (demo)
        try render(
            name: "02-populated-universe",
            project: demo,
            seed: PatchWorkspaceSeed(
                selectedDefinitionID: demo.fixtureDefinitions.first?.id
            ),
            to: dir
        )

        // 3. Selected fixture
        let selectedID = demo.fixtures.first?.id
        try render(
            name: "03-selected-fixture",
            project: demo,
            seed: PatchWorkspaceSeed(
                selectedDefinitionID: demo.fixtures.first.flatMap { demo.definition(id: $0.definitionId)?.id },
                selectedFixtureIDs: selectedID.map { Set([$0]) } ?? []
            ),
            to: dir
        )

        // 4. Qty=4 valid ghost — free range after last demo fixture
        let u1 = demo.universes[0].id
        let nextFree = demo.nextFreeAddress(in: u1, channelCount: 3) ?? 200
        let washDef = demo.fixtureDefinitions.first { $0.model.contains("RGB") }?.id
            ?? demo.fixtureDefinitions.first?.id
        let validGhost: PatchBatchPlan? = washDef.map {
            PatchBatchPlanner.plan(
                project: demo,
                definitionID: $0,
                universeID: u1,
                startAddress: nextFree,
                quantity: 4,
                namePrefix: "Wash"
            )
        }
        try render(
            name: "04-ghost-qty4-valid",
            project: demo,
            seed: PatchWorkspaceSeed(
                quantity: 4,
                namePrefix: "Wash",
                selectedDefinitionID: washDef,
                ghostPlan: validGhost
            ),
            to: dir
        )

        // 5. Invalid / collision ghost — start on occupied address 1
        let invalidGhost: PatchBatchPlan? = washDef.map {
            PatchBatchPlanner.plan(
                project: demo,
                definitionID: $0,
                universeID: u1,
                startAddress: 1,
                quantity: 4,
                namePrefix: "Clash"
            )
        }
        try render(
            name: "05-ghost-invalid-collision",
            project: demo,
            seed: PatchWorkspaceSeed(
                quantity: 4,
                namePrefix: "Clash",
                selectedDefinitionID: washDef,
                ghostPlan: invalidGhost
            ),
            to: dir
        )

        // 6. List view
        try render(
            name: "06-list-view",
            project: demo,
            seed: PatchWorkspaceSeed(
                listMode: true,
                selectedDefinitionID: washDef
            ),
            to: dir
        )

        // 7. Multi-universe (Universe 2 selected, sparsely populated)
        let u2 = multi.universes.sorted { $0.number < $1.number }.last
        try render(
            name: "07-multi-universe",
            project: multi,
            seed: PatchWorkspaceSeed(
                selectedDefinitionID: multi.fixtureDefinitions.first?.id,
                selectedUniverseID: u2?.id
            ),
            to: dir
        )
    }

    private static func emptyProject() -> ShowProject {
        var p = ShowProject.empty(name: "Empty Patch")
        let def = FixtureDefinition(
            manufacturer: "Generic",
            model: "Dimmer",
            modeName: "1ch",
            channels: [
                ChannelDef(offset: 1, name: "Intensity", attribute: "intensity")
            ]
        )
        p.fixtureDefinitions = [def]
        if p.universes.isEmpty {
            p.universes = [Universe(number: 1, name: "U1", channelCount: 512)]
        }
        p.fixtures = []
        return p
    }

    private static func multiUniverseProject(from demo: ShowProject) -> ShowProject {
        var p = demo
        let u2 = Universe(number: 2, name: "Side Stage", channelCount: 512)
        p.universes.append(u2)
        // Use RGB wash (3ch) so blocks read as objects, not single-cell chips.
        let wash = p.fixtureDefinitions.first { $0.model.contains("RGB") }
            ?? p.fixtureDefinitions.first
        if let def = wash {
            p.fixtures.append(contentsOf: [
                PatchedFixture(name: "Side Wash 1", definitionId: def.id, universeId: u2.id, address: 1),
                PatchedFixture(name: "Side Wash 2", definitionId: def.id, universeId: u2.id, address: 10),
                PatchedFixture(name: "Side Spot 1", definitionId: def.id, universeId: u2.id, address: 33),
            ])
        }
        return p
    }

    private static func render(
        name: String,
        project: ShowProject,
        seed: PatchWorkspaceSeed,
        to dir: URL
    ) throws {
        let session = DocumentSession(project: project)
        let context = WorkspacePanelContext(session: session, fixtureLibrary: nil)
        let size = CGSize(width: 1440, height: 900)

        let root = HStack(spacing: 0) {
            PatchWorkspaceView(context: context, seed: seed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(AuroraColor.separator)
            // Contextual inspector strip (production shell keeps Inspector on the right)
            InspectorPanel(context: context, focus: seed.selectedFixtureIDs.isEmpty ? .project : .fixtures)
                .frame(width: 260)
        }
        .frame(width: size.width, height: size.height)
        .background(AuroraColor.surfaceWorkspace)
        .preferredColorScheme(.dark)

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        // Attach offscreen window so SwiftUI completes layout (GeometryReader sizes correctly).
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            window.orderOut(nil)
            throw ExportError.bitmapFailed(name)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.pngFailed(name)
        }
        let url = dir.appendingPathComponent("\(name).png")
        try data.write(to: url)
    }

    private enum ExportError: Error, CustomStringConvertible {
        case bitmapFailed(String)
        case pngFailed(String)
        var description: String {
            switch self {
            case .bitmapFailed(let n): return "bitmap failed for \(n)"
            case .pngFailed(let n): return "png failed for \(n)"
            }
        }
    }
}
