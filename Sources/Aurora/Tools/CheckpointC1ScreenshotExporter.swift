import AppKit
import AuroraCore
import AuroraEngine
import AuroraModel
import AuroraUI
import SwiftUI

/// Checkpoint C1 visual export — shared Stage canvas in Program + Stage hosts.
/// Launch: `--export-checkpoint-c1-shots [dir]`
@MainActor
enum CheckpointC1ScreenshotExporter {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--export-checkpoint-c1-shots") else { return }

        let containerBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var outDir = containerBase
            .appendingPathComponent("Aurora", isDirectory: true)
            .appendingPathComponent("checkpoint-c1", isDirectory: true)

        if args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            let requested = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
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
            try outDir.path.write(
                to: outDir.appendingPathComponent("EXPORT_PATH.txt"),
                atomically: true,
                encoding: .utf8
            )
            fputs("Checkpoint C1 screenshots written to \(outDir.path)\n", stderr)
            NSApp.terminate(nil)
        } catch {
            fputs("Checkpoint C1 export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func exportAll(to dir: URL) throws {
        let session = DocumentSession(project: ShowProject.demoSummerNight())
        // Demo has no stage placements — place all for a readable rig.
        try session.perform(PlaceAllUnplacedCommand())

        // Live look: washes amber-ish, movers highlighted intensity.
        var attrs: [UUID: [String: Double]] = [:]
        for fx in session.project.fixtures {
            let def = session.project.definition(id: fx.definitionId)
            var a: [String: Double] = ["intensity": 0.7]
            if def?.colorModel != nil {
                a["colorR"] = 1.0
                a["colorG"] = 0.55
                a["colorB"] = 0.12
            }
            if def?.hasPanTilt == true {
                a["pan"] = 0.35
                a["tilt"] = 0.45
                a["intensity"] = 0.85
            }
            attrs[fx.id] = a
        }
        let look = ActiveLook(fixtureAttributes: attrs)
        let preview = StagePreviewBuilder.build(
            project: session.project,
            look: look,
            frameIndex: 1,
            time: 0,
            global: GlobalShowControlState(masterIntensity: 1)
        )

        let context = WorkspacePanelContext(session: session, fixtureLibrary: nil)
        let movers = session.project.groups.first { $0.name == "Movers" }?.fixtureIds ?? []
        let selected = Set(movers.prefix(1))
        if !selected.isEmpty {
            session.selectFixtures(selected, extending: false)
        }

        // 1. Program host composite — Stage Preview strip + Programmer (C1 smoke embed)
        try render(
            name: "01-program-shared-stage-preview",
            size: CGSize(width: 1440, height: 900),
            to: dir
        ) {
            programComposite(
                context: context,
                preview: preview,
                selectedIDs: [],
                geometryLocked: true
            )
        }

        // 2. Program with selection on Stage canvas
        try render(
            name: "02-program-stage-selection",
            size: CGSize(width: 1440, height: 900),
            to: dir
        ) {
            programComposite(
                context: context,
                preview: preview,
                selectedIDs: selected,
                geometryLocked: true
            )
        }

        // 3. Full Stage panel (edit chrome host around same canvas)
        try render(
            name: "03-stage-tab-shared-canvas",
            size: CGSize(width: 1440, height: 900),
            to: dir
        ) {
            stageComposite(context: context, preview: preview)
        }

        // 4. Isolated canvas only (geometry locked) — architecture surface
        try render(
            name: "04-stage-canvas-geometry-locked",
            size: CGSize(width: 1200, height: 700),
            to: dir
        ) {
            canvasOnly(
                context: context,
                preview: preview,
                selectedIDs: selected,
                edit: false
            )
        }

        // 5. Canvas edit mode chrome caption (geometry unlocked path)
        try render(
            name: "05-stage-canvas-edit-geometry",
            size: CGSize(width: 1200, height: 700),
            to: dir
        ) {
            canvasOnly(
                context: context,
                preview: preview,
                selectedIDs: selected,
                edit: true
            )
        }
    }

    // MARK: - Composites

    private static func programComposite(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        selectedIDs: Set<UUID>,
        geometryLocked: Bool
    ) -> some View {
        CameraHost(
            scale: 0.55,
            pan: .zero
        ) { scale, pan in
            HStack(spacing: 0) {
                // Left rail stub
                VStack(alignment: .leading, spacing: 8) {
                    Text("FIXTURES")
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Text("Browser · Groups")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textSecondary)
                    Spacer()
                }
                .padding(12)
                .frame(width: 180)
                .background(AuroraColor.surfacePanel)

                Divider().overlay(AuroraColor.separator)

                VStack(spacing: 0) {
                    // Mode bar
                    HStack {
                        Text("PROGRAM")
                            .font(AuroraTypography.tab)
                            .foregroundStyle(AuroraColor.accentBright)
                        Text("PATCH  STAGE  PROFILES")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                        Spacer()
                        Text("C1 · shared Stage canvas")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AuroraColor.surfaceHeader)

                    // Stage preview strip (matches production embed)
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text("STAGE PREVIEW")
                                .font(AuroraTypography.controlLabel)
                                .foregroundStyle(AuroraColor.textTertiary)
                            Text(geometryLocked
                                 ? "shared canvas · geometry locked"
                                 : "shared canvas · edit")
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AuroraColor.surfaceHeader)

                        StageCanvasView(
                            context: context,
                            preview: preview,
                            interactionMode: geometryLocked ? .programSelect : .editGeometry,
                            geometryEditingEnabled: !geometryLocked,
                            selectedIDs: selectedIDs.isEmpty
                                ? context.session.selection.snapshot.fixtureIDs
                                : selectedIDs,
                            scale: scale,
                            pan: pan,
                            onSelectFixtures: { _ in },
                            onLayoutChanged: {}
                        )
                        .frame(height: 260)
                    }
                    .background(AuroraColor.surfacePanel)

                    Divider().overlay(AuroraColor.separator)

                    // Programmer stub
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PROGRAMMER")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                        Text(selectedIDs.isEmpty
                             ? "Select fixtures on Stage Preview or Browser"
                             : "Selection follows Stage canvas · \(selectedIDs.count) fixture(s)")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textSecondary)
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AuroraColor.surfaceRaised)
                                .frame(width: 72, height: 120)
                                .overlay(Text("INT").font(.caption).foregroundStyle(.secondary))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AuroraColor.surfaceRaised)
                                .frame(width: 160, height: 120)
                                .overlay(Text("COLOR").font(.caption).foregroundStyle(.secondary))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AuroraColor.surfaceRaised)
                                .frame(width: 140, height: 120)
                                .overlay(Text("POSITION").font(.caption).foregroundStyle(.secondary))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AuroraColor.surfacePanel)
                }

                Divider().overlay(AuroraColor.separator)

                VStack(alignment: .leading, spacing: 8) {
                    Text("INSPECTOR")
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Text("Shared selection")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textSecondary)
                    Spacer()
                }
                .padding(12)
                .frame(width: 200)
                .background(AuroraColor.surfacePanel)
            }
            .background(AuroraColor.surfaceWorkspace)
            .preferredColorScheme(.dark)
        }
    }

    private static func stageComposite(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot
    ) -> some View {
        StagePanel(
            context: context,
            preview: preview,
            onLayoutChanged: {},
            onSelectFixtures: { ids in
                context.session.selectFixtures(Set(ids), extending: false)
            }
        )
        .background(AuroraColor.surfaceWorkspace)
        .preferredColorScheme(.dark)
    }

    private static func canvasOnly(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        selectedIDs: Set<UUID>,
        edit: Bool
    ) -> some View {
        CameraHost(scale: 0.65, pan: .zero) { scale, pan in
            VStack(spacing: 0) {
                HStack {
                    Text(edit ? "StageCanvasView · editGeometry" : "StageCanvasView · programSelect · geometry locked")
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Spacer()
                    Text("one StageLayout · one StagePreviewSnapshot")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .padding(8)
                .background(AuroraColor.surfaceHeader)

                StageCanvasView(
                    context: context,
                    preview: preview,
                    interactionMode: edit ? .editGeometry : .programSelect,
                    geometryEditingEnabled: edit,
                    selectedIDs: selectedIDs,
                    scale: scale,
                    pan: pan,
                    onSelectFixtures: { _ in },
                    onLayoutChanged: {}
                )
            }
            .background(AuroraColor.surfaceWorkspace)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Render

    private static func render<V: View>(
        name: String,
        size: CGSize,
        to dir: URL,
        @ViewBuilder content: () -> V
    ) throws {
        let root = content()
            .frame(width: size.width, height: size.height)

        let host = NSHostingView(rootView: root)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
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
        try data.write(to: dir.appendingPathComponent("\(name).png"))
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

/// Holds scale/pan bindings for offscreen StageCanvasView.
private struct CameraHost<Content: View>: View {
    @State private var scale: CGFloat
    @State private var pan: CGSize
    private let content: (Binding<CGFloat>, Binding<CGSize>) -> Content

    init(
        scale: CGFloat,
        pan: CGSize,
        @ViewBuilder content: @escaping (Binding<CGFloat>, Binding<CGSize>) -> Content
    ) {
        _scale = State(initialValue: scale)
        _pan = State(initialValue: pan)
        self.content = content
    }

    var body: some View {
        content($scale, $pan)
    }
}
