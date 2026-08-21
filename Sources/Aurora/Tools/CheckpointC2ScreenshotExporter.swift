import AuroraDesignSystem
import AppKit
import AuroraCore
import AuroraDiagnostics
import AuroraEngine
import AuroraModel
import AuroraUI
import SwiftUI

/// Checkpoint C2 — DESIGN workspace visual package.
/// Launch: `--export-checkpoint-c2-shots`
@MainActor
enum CheckpointC2ScreenshotExporter {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--export-checkpoint-c2-shots") else { return }

        let containerBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let outDir = containerBase
            .appendingPathComponent("Aurora", isDirectory: true)
            .appendingPathComponent("checkpoint-c2", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            try exportAll(to: outDir)
            try outDir.path.write(
                to: outDir.appendingPathComponent("EXPORT_PATH.txt"),
                atomically: true,
                encoding: .utf8
            )
            fputs("Checkpoint C2 screenshots written to \(outDir.path)\n", stderr)
            NSApp.terminate(nil)
        } catch {
            PrismLog.debug(.uiPresentation, "ui.presentation.export_failed", "A screenshot export failed.")
            fputs("Checkpoint C2 export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func exportAll(to dir: URL) throws {
        let session = DocumentSession(project: ShowProject.demoSummerNight())
        try session.perform(PlaceAllUnplacedCommand())

        var attrs: [UUID: [String: Double]] = [:]
        for fx in session.project.fixtures {
            let def = session.project.definition(id: fx.definitionId)
            var a: [String: Double] = ["intensity": 0.65]
            if def?.colorModel != nil {
                a["colorR"] = 1; a["colorG"] = 0.55; a["colorB"] = 0.12
            }
            if def?.hasPanTilt == true {
                a["pan"] = 0.4; a["tilt"] = 0.5; a["intensity"] = 0.9
            }
            attrs[fx.id] = a
        }
        let look = ActiveLook(fixtureAttributes: attrs)
        let preview = StagePreviewBuilder.build(
            project: session.project,
            look: look,
            frameIndex: 2,
            time: 0,
            global: GlobalShowControlState()
        )
        let context = WorkspacePanelContext(session: session)

        let front = Set(session.project.groups.first { $0.name == "Front Wash" }?.fixtureIds ?? [])
        let movers = Set(session.project.groups.first { $0.name == "Movers" }?.fixtureIds ?? [])
        let oneMover = movers.prefix(1)

        // 1. No selection
        try render("01-design-no-selection", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: [],
                previewCollapsed: false,
                previewFraction: 0.52,
                bottomFraction: 0.26,
                label: "DESIGN · no selection"
            )
        }

        // 2. RGB wash group
        try render("02-design-front-wash-group", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(front),
                previewCollapsed: false,
                previewFraction: 0.52,
                bottomFraction: 0.26,
                label: "DESIGN · Front Wash group"
            )
        }

        // 3. Movers group
        try render("03-design-movers-group", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(movers),
                previewCollapsed: false,
                previewFraction: 0.52,
                bottomFraction: 0.26,
                label: "DESIGN · Movers group"
            )
        }

        // 4. Single mover from Stage
        try render("04-design-single-mover-stage", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(oneMover),
                previewCollapsed: false,
                previewFraction: 0.55,
                bottomFraction: 0.24,
                label: "DESIGN · select on Stage Preview"
            )
        }

        // 5. Live color look (amber washes already in preview)
        try render("05-design-live-color", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(front),
                previewCollapsed: false,
                previewFraction: 0.55,
                bottomFraction: 0.22,
                label: "DESIGN · live amber look (resolved state)"
            )
        }

        // 6. Live position (movers with pan)
        try render("06-design-live-position", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(movers),
                previewCollapsed: false,
                previewFraction: 0.58,
                bottomFraction: 0.20,
                label: "DESIGN · mover beams / pan from resolved look"
            )
        }

        // 7. Programmer focus — preview collapsed
        try render("07-design-programmer-focus", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(front),
                previewCollapsed: true,
                previewFraction: 0.3,
                bottomFraction: 0.24,
                label: "DESIGN · Programmer Focus (preview collapsed)"
            )
        }

        // 8. Preview focus
        try render("08-design-preview-focus", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(oneMover),
                previewCollapsed: false,
                previewFraction: 0.72,
                bottomFraction: 0.16,
                label: "DESIGN · Preview Focus"
            )
        }

        // 9. Lower shelf expanded (cue focus proportions)
        try render("09-design-lower-shelf-expanded", size: CGSize(width: 1440, height: 900), to: dir) {
            designHost(
                context: context,
                preview: preview,
                selected: Array(front),
                previewCollapsed: false,
                previewFraction: 0.36,
                bottomFraction: 0.42,
                label: "DESIGN · Cue Focus (lower shelf expanded)",
                showLower: true
            )
        }
    }

    private static func designHost(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        selected: [UUID],
        previewCollapsed: Bool,
        previewFraction: CGFloat,
        bottomFraction: CGFloat,
        label: String,
        showLower: Bool = true
    ) -> some View {
        CameraHost(scale: 0.5, pan: .zero) { scale, pan in
            VStack(spacing: 0) {
                // Mode bar
                HStack {
                    Text("DESIGN").font(AuroraTypography.tab).foregroundStyle(AuroraColor.accentBright)
                    Text("PATCH  STAGE  PROFILES")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Spacer()
                    Text(label)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AuroraColor.surfaceHeader)

                GeometryReader { geo in
                    let totalH = geo.size.height
                    let bottomH = showLower ? totalH * bottomFraction : 0
                    let mainH = totalH - bottomH - (showLower ? 4 : 0)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            // Left
                            VStack(alignment: .leading, spacing: 6) {
                                Text("FIXTURES").font(AuroraTypography.controlLabel)
                                    .foregroundStyle(AuroraColor.textTertiary)
                                Text("Browser · Groups")
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textSecondary)
                                if !selected.isEmpty {
                                    Text("\(selected.count) selected")
                                        .font(.caption)
                                        .foregroundStyle(AuroraColor.accentBright)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .frame(width: 170)
                            .background(AuroraColor.surfacePanel)

                            Divider().overlay(AuroraColor.separator)

                            // Center
                            VStack(spacing: 0) {
                                if !previewCollapsed {
                                    VStack(spacing: 0) {
                                        HStack {
                                            Text("STAGE PREVIEW")
                                                .font(AuroraTypography.controlLabel)
                                                .foregroundStyle(AuroraColor.textTertiary)
                                            Text("live · geometry locked")
                                                .font(AuroraTypography.metadata)
                                                .foregroundStyle(AuroraColor.textTertiary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AuroraColor.surfaceHeader)

                                        StageCanvasView(
                                            context: context,
                                            preview: preview,
                                            interactionMode: .programSelect,
                                            geometryEditingEnabled: false,
                                            selectedIDs: Set(selected),
                                            scale: scale,
                                            pan: pan,
                                            onSelectFixtures: { _ in },
                                            onLayoutChanged: {}
                                        )
                                    }
                                    .frame(height: max(120, mainH * previewFraction))
                                    Divider().overlay(AuroraColor.separator)
                                } else {
                                    HStack {
                                        Text("STAGE PREVIEW HIDDEN")
                                            .font(AuroraTypography.controlLabel)
                                            .foregroundStyle(AuroraColor.textTertiary)
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(AuroraColor.surfaceHeader)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PROGRAMMER")
                                        .font(AuroraTypography.controlLabel)
                                        .foregroundStyle(AuroraColor.textTertiary)
                                    Text(selected.isEmpty
                                         ? "Select on Stage Preview or Browser"
                                         : "Contextual controls for \(selected.count) fixture(s)")
                                        .font(AuroraTypography.metadata)
                                        .foregroundStyle(AuroraColor.textSecondary)
                                    HStack(spacing: 12) {
                                        chip("INTENSITY")
                                        if selected.count > 0 { chip("COLOR") }
                                        if selected.count >= 3 { chip("POSITION") }
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(AuroraColor.surfacePanel)
                            }

                            Divider().overlay(AuroraColor.separator)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("INSPECTOR")
                                    .font(AuroraTypography.controlLabel)
                                    .foregroundStyle(AuroraColor.textTertiary)
                                Text(selected.isEmpty ? "Project" : "Fixture")
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textSecondary)
                                Spacer()
                            }
                            .padding(10)
                            .frame(width: 180)
                            .background(AuroraColor.surfacePanel)
                        }
                        .frame(height: mainH)

                        if showLower {
                            Divider().overlay(AuroraColor.separator)
                            HStack {
                                Text("PALETTES  ·  CUES  ·  SONG  ·  DIAGNOSTICS")
                                    .font(AuroraTypography.tab)
                                    .foregroundStyle(AuroraColor.textTertiary)
                                Spacer()
                                Text("lower shelf")
                                    .font(AuroraTypography.metadata)
                                    .foregroundStyle(AuroraColor.textTertiary)
                            }
                            .padding(12)
                            .frame(height: max(80, bottomH))
                            .background(AuroraColor.surfaceHeader)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuroraColor.surfaceWorkspace)
            .preferredColorScheme(.dark)
        }
    }

    private static func chip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AuroraColor.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 20)
            .background(AuroraColor.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private static func render<V: View>(
        _ name: String,
        size: CGSize,
        to dir: URL,
        @ViewBuilder content: () -> V
    ) throws {
        let host = NSHostingView(rootView: content().frame(width: size.width, height: size.height))
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
            throw ExportError.bitmap(name)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.png(name)
        }
        try data.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private enum ExportError: Error {
        case bitmap(String)
        case png(String)
    }
}

private struct CameraHost<Content: View>: View {
    @State private var scale: CGFloat
    @State private var pan: CGSize
    private let content: (Binding<CGFloat>, Binding<CGSize>) -> Content

    init(scale: CGFloat, pan: CGSize, @ViewBuilder content: @escaping (Binding<CGFloat>, Binding<CGSize>) -> Content) {
        _scale = State(initialValue: scale)
        _pan = State(initialValue: pan)
        self.content = content
    }

    var body: some View { content($scale, $pan) }
}
