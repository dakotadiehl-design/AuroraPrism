import AppKit
import AuroraCore
import AuroraEngine
import AuroraModel
import AuroraUI
import SwiftUI

/// Checkpoint C3 — Edit Stage in place visual package.
/// Launch: `--export-checkpoint-c3-shots`
@MainActor
enum CheckpointC3ScreenshotExporter {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--export-checkpoint-c3-shots") else { return }

        let outDir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Aurora/checkpoint-c3", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            try exportAll(to: outDir)
            try outDir.path.write(
                to: outDir.appendingPathComponent("EXPORT_PATH.txt"),
                atomically: true,
                encoding: .utf8
            )
            fputs("Checkpoint C3 screenshots written to \(outDir.path)\n", stderr)
            NSApp.terminate(nil)
        } catch {
            fputs("Checkpoint C3 export failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func exportAll(to dir: URL) throws {
        let session = DocumentSession(project: ShowProject.demoSummerNight())
        // Leave some unplaced for tray screenshot.
        try session.perform(PlaceAllUnplacedCommand())
        // Remove two so Unplaced is non-empty
        let toUnplace = Array(session.project.stageLayout.fixtures.prefix(2).map(\.fixtureID))
        if !toUnplace.isEmpty {
            try session.perform(RemoveFromStageCommand(fixtureIDs: toUnplace))
        }

        var attrs: [UUID: [String: Double]] = [:]
        for fx in session.project.fixtures {
            attrs[fx.id] = ["intensity": 0.6, "colorR": 0.9, "colorG": 0.5, "colorB": 0.2]
            if session.project.definition(id: fx.definitionId)?.hasPanTilt == true {
                attrs[fx.id]?["pan"] = 0.4
                attrs[fx.id]?["tilt"] = 0.5
            }
        }
        let preview = StagePreviewBuilder.build(
            project: session.project,
            look: ActiveLook(fixtureAttributes: attrs),
            frameIndex: 3,
            time: 0,
            global: GlobalShowControlState()
        )
        let context = WorkspacePanelContext(session: session)
        let multi = Array(session.project.stageLayout.fixtures.prefix(4).map(\.fixtureID))
        if let first = multi.first {
            session.selectFixtures(Set(multi), extending: false)
            _ = first
        }

        try render("01-design-live-geometry-locked", size: CGSize(width: 1440, height: 900), to: dir) {
            host(context: context, preview: preview, edit: false, selected: [], unplacedCount: toUnplace.count,
                 label: "DESIGN · Live · geometry locked")
        }

        try render("02-edit-stage-unplaced-tray", size: CGSize(width: 1440, height: 900), to: dir) {
            host(context: context, preview: preview, edit: true, selected: [], unplacedCount: toUnplace.count,
                 label: "EDIT STAGE · Unplaced tray · geometry unlocked")
        }

        try render("03-edit-stage-multi-selection", size: CGSize(width: 1440, height: 900), to: dir) {
            host(context: context, preview: preview, edit: true, selected: multi, unplacedCount: toUnplace.count,
                 label: "EDIT STAGE · multi-selection · Align / Distribute / Remove")
        }

        try render("04-edit-stage-exit-continue", size: CGSize(width: 1440, height: 900), to: dir) {
            host(context: context, preview: preview, edit: false, selected: multi.prefix(1).map { $0 },
                 unplacedCount: toUnplace.count,
                 label: "Done Editing · back to programming · same selection")
        }
    }

    private static func host(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        edit: Bool,
        selected: [UUID],
        unplacedCount: Int,
        label: String
    ) -> some View {
        CameraHost(scale: 0.48, pan: .zero) { scale, pan in
            VStack(spacing: 0) {
                HStack {
                    Text(edit ? "STAGE" : "DESIGN")
                        .font(AuroraTypography.tab)
                        .foregroundStyle(AuroraColor.accentBright)
                    Text(edit ? "(alias → Design + Edit Stage)" : "PATCH  STAGE  PROFILES")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Spacer()
                    Text(label)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .padding(10)
                .background(AuroraColor.surfaceHeader)

                HStack(spacing: 0) {
                    // Left rail
                    VStack(alignment: .leading, spacing: 6) {
                        if edit {
                            Text("STAGE EDIT")
                                .font(AuroraTypography.controlLabel)
                                .foregroundStyle(AuroraColor.warning)
                            Text("Unplaced (\(unplacedCount))")
                                .font(.caption)
                                .foregroundStyle(AuroraColor.warning)
                            Text("On Stage")
                                .font(.caption)
                                .foregroundStyle(AuroraColor.textSecondary)
                            Text("Drag to canvas to place")
                                .font(.caption2)
                                .foregroundStyle(AuroraColor.textTertiary)
                        } else {
                            Text("FIXTURES")
                                .font(AuroraTypography.controlLabel)
                                .foregroundStyle(AuroraColor.textTertiary)
                            Text("Browser · Groups")
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .frame(width: 160)
                    .background(AuroraColor.surfacePanel)

                    Divider().overlay(AuroraColor.separator)

                    VStack(spacing: 0) {
                        HStack {
                            Text(edit ? "EDIT STAGE" : "STAGE PREVIEW")
                                .font(AuroraTypography.controlLabel)
                                .foregroundStyle(edit ? AuroraColor.warning : AuroraColor.textTertiary)
                            Text(edit ? "geometry unlocked" : "geometry locked")
                                .font(AuroraTypography.metadata)
                                .foregroundStyle(AuroraColor.textTertiary)
                            if edit {
                                Text("Align · Distribute · Add · Remove From Stage")
                                    .font(.caption2)
                                    .foregroundStyle(AuroraColor.textTertiary)
                            }
                            Spacer()
                            Text(edit ? "Done" : "Edit Stage")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(edit ? AuroraColor.warning.opacity(0.3) : AuroraColor.accent.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(8)
                        .background(edit ? AuroraColor.warning.opacity(0.1) : AuroraColor.surfaceHeader)

                        StageCanvasView(
                            context: context,
                            preview: preview,
                            interactionMode: edit ? .editGeometry : .programSelect,
                            geometryEditingEnabled: edit,
                            selectedIDs: Set(selected),
                            scale: scale,
                            pan: pan,
                            onSelectFixtures: { _ in },
                            onLayoutChanged: {}
                        )
                        .frame(height: 420)

                        HStack {
                            Text(edit ? "PROGRAMMER (compact while editing)" : "PROGRAMMER")
                                .font(AuroraTypography.controlLabel)
                                .foregroundStyle(AuroraColor.textTertiary)
                            if !selected.isEmpty {
                                Text("\(selected.count) selected")
                                    .font(.caption)
                                    .foregroundStyle(AuroraColor.accentBright)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AuroraColor.surfacePanel)
                    }

                    Divider().overlay(AuroraColor.separator)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("INSPECTOR")
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                        Text(edit ? "Placement / identity" : "Fixture")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textSecondary)
                        Spacer()
                    }
                    .padding(10)
                    .frame(width: 170)
                    .background(AuroraColor.surfacePanel)
                }
            }
            .background(AuroraColor.surfaceWorkspace)
            .preferredColorScheme(.dark)
        }
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
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            window.orderOut(nil)
            throw ExportError.fail(name)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.fail(name)
        }
        try data.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private enum ExportError: Error { case fail(String) }
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
