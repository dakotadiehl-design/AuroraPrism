import AppKit
import AuroraUI
import SwiftUI

// MARK: - Floating window host (C5C / C5.1)

/// Independent macOS window hosting one detachable workspace surface.
/// Shares `AppModel` with the main window — production surfaces, not clones.
struct FloatingSurfaceWindow: View {
    @EnvironmentObject private var appModel: AppModel
    let surface: FloatSurfaceID

    @State private var configuredWindowID: ObjectIdentifier?

    var body: some View {
        VStack(spacing: 0) {
            floatingChrome
            Divider().background(AuroraColor.separator)
            surfaceBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AuroraColor.surfaceWorkspace)
        .frame(
            minWidth: surface.minimumSize.width,
            idealWidth: surface.defaultSize.width,
            maxWidth: 2400,
            minHeight: surface.minimumSize.height,
            idealHeight: surface.defaultSize.height,
            maxHeight: 1800
        )
        .background(
            FloatingWindowConfigurator(surface: surface) { win in
                let oid = ObjectIdentifier(win)
                guard configuredWindowID != oid else { return }
                configuredWindowID = oid
                Self.configure(window: win, for: surface, appModel: appModel)
                appModel.floatWindows.register(window: win, for: surface)
            }
        )
        // C5.1: do NOT redock in onDisappear — quit vs user-close is handled by
        // FloatingSurfaceWindowCoordinator (willClose + isTerminating).
    }

    private var floatingChrome: some View {
        HStack(spacing: 8) {
            Text(surface.title.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text("resize from edges · Dock to return")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
                .lineLimit(1)
            Spacer()
            Button("Dock") {
                // Unified: redock state + close exact registered window.
                appModel.redockSurface(surface)
            }
            .buttonStyle(AuroraButtonStyle(kind: .secondary))
            .controlSize(.small)
            .help("Dock in Main Window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AuroraColor.surfaceHeader)
    }

    @ViewBuilder
    private var surfaceBody: some View {
        switch surface {
        case .browser:
            BrowserWorkspaceSurface(showsUndockChrome: false)
        case .stagePreview:
            // Production DESIGN Stage — not legacy StagePanel.
            DesignStageSurface(showsUndockChrome: false)
        case .programmer:
            ProgrammerWorkspaceSurface()
        case .inspector:
            InspectorWorkspaceSurface()
        case .lowerShelf:
            CreativeShelfWorkspaceSurface(
                showsUndockChrome: false,
                showsCollapseControl: false
            )
        case .diagnostics:
            DiagnosticsWorkspaceSurface()
        }
    }

    /// Ensure titled, closable, miniaturizable, **resizable** window at a sensible size.
    private static func configure(window: NSWindow, for surface: FloatSurfaceID, appModel: AppModel) {
        window.title = surface.title
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.minSize = NSSize(width: surface.minimumSize.width, height: surface.minimumSize.height)

        let rec = appModel.workspace.floatState.record(for: surface)
        if let stored = rec.frame, stored.width > 100, stored.height > 100 {
            var f = stored
            // Prefer matching screen by id; else clamp onto current/main visible frame.
            let screens = AuroraScreenIdentity.currentVisibleScreens()
            let recovered = WorkspaceFloatState.recoverFrame(
                f,
                preferredScreenID: rec.screenID,
                screens: screens
            )
            f = recovered.frame
            window.setFrame(f, display: true)
        } else {
            let size = surface.defaultSize
            if let screen = window.screen ?? NSScreen.main {
                let vis = screen.visibleFrame
                let origin = NSPoint(
                    x: vis.midX - size.width / 2,
                    y: vis.midY - size.height / 2
                )
                window.setFrame(NSRect(origin: origin, size: size), display: true)
            } else {
                window.setContentSize(size)
            }
        }
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Resolve NSWindow for SwiftUI content

private struct FloatingWindowConfigurator: NSViewRepresentable {
    let surface: FloatSurfaceID
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let win = view.window {
                onResolve(win)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let win = nsView.window {
                onResolve(win)
            }
        }
    }
}

// MARK: - Docked placeholder when surface is floated (legacy full-size; prefer CompactFloatRestoreChip)

struct FloatedSurfacePlaceholder: View {
    let surface: FloatSurfaceID
    var onDock: () -> Void
    var onFocusWindow: (() -> Void)?

    var body: some View {
        CompactFloatRestoreChip(surface: surface, onDock: onDock, onFocus: onFocusWindow)
    }
}

// MARK: - Undock control (shared — unified path via AppModel.undockSurface)

struct UndockSurfaceButton: View {
    let surface: FloatSurfaceID
    var showTitle: Bool = false
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            undock()
        } label: {
            if showTitle {
                Label("Undock", systemImage: "macwindow")
            } else {
                Label("Move to Window", systemImage: "macwindow")
            }
        }
        .help("Open \(surface.title) in a separate resizable window")
        .disabled(appModel.workspace.isFloating(surface))
    }

    private func undock() {
        appModel.undockSurface(surface, preferredScreen: NSScreen.main)
        openWindow(id: "float-surface", value: surface)
    }
}

/// Restores previously floated surfaces as real windows after launch (C5B/C5E).
struct FloatWindowRestorer: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var didInitialRestore = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard !didInitialRestore else { return }
                didInitialRestore = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    restore()
                }
            }
            .onChange(of: appModel.workspace.floatEpoch) { _, _ in
                DispatchQueue.main.async {
                    restoreMissing()
                }
            }
    }

    private func restore() {
        let surfaces = appModel.workspace.floatState.floatingSurfaceIDs
        for surface in surfaces {
            openWindow(id: "float-surface", value: surface)
        }
        guard !surfaces.isEmpty else { return }
        // SwiftUI WindowGroup creation is asynchronous. Let restored auxiliary windows
        // materialize, then put the primary Prism workspace above them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .prismBringMainWindowForward, object: nil)
        }
    }

    private func restoreMissing() {
        for surface in appModel.workspace.floatState.floatingSurfaceIDs {
            // Skip if coordinator already has a live window for this surface.
            if appModel.floatWindows.window(for: surface) != nil { continue }
            openWindow(id: "float-surface", value: surface)
        }
    }
}
