import AppKit
import AuroraUI
import Foundation

// MARK: - Screen identity (C5.1)

enum AuroraScreenIdentity {
    /// Best-effort durable display id from CoreGraphics / deviceDescription.
    static func identifier(for screen: NSScreen) -> String {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(num.uint32Value)"
        }
        return "name-\(screen.localizedName)"
    }

    static func displayName(for screen: NSScreen) -> String {
        screen.localizedName
    }

    static func currentVisibleScreens() -> [ScreenVisibleRecord] {
        NSScreen.screens.map { screen in
            ScreenVisibleRecord(id: identifier(for: screen), visibleFrame: screen.visibleFrame)
        }
    }

    /// Centered default frame for first undock on the preferred (or main) screen.
    static func defaultFrame(for surface: FloatSurfaceID, preferredScreen: NSScreen? = nil) -> (
        frame: CGRect,
        screenID: String,
        screenName: String
    ) {
        let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let size = surface.defaultSize
        guard let screen else {
            return (
                CGRect(origin: .zero, size: size),
                "unknown",
                "unknown"
            )
        }
        let vis = screen.visibleFrame
        let frame = CGRect(
            x: vis.midX - size.width / 2,
            y: vis.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        return (frame, identifier(for: screen), displayName(for: screen))
    }
}

// MARK: - FloatSurfaceID ↔ NSWindow (C5.1)

/// Narrow coordinator: register exact windows, track frames, close/focus without title scanning.
@MainActor
final class FloatingSurfaceWindowCoordinator {
    private var windows: [FloatSurfaceID: NSWindow] = [:]
    private var observerTokens: [FloatSurfaceID: [NSObjectProtocol]] = [:]

    /// True while Aurora is shutting down — user-close redock must not run.
    var isTerminating: () -> Bool = { false }

    /// Persist frame after move/resize/screen change.
    var onFrameChanged: ((FloatSurfaceID, CGRect, String?, String?) -> Void)?

    /// User intentionally closed the floating window (red traffic light), not app quit.
    var onUserCloseWhileFloating: ((FloatSurfaceID) -> Void)?

    func register(window: NSWindow, for surface: FloatSurfaceID) {
        if windows[surface] === window { return }
        unregister(surface: surface)
        windows[surface] = window

        // Observe close via NotificationCenter (no unused NSWindowDelegate proxy).
        let nc = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []

        tokens.append(nc.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowWillClose(surface)
            }
        })

        tokens.append(nc.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            let win = note.object as? NSWindow
            Task { @MainActor in
                guard let self, let win, self.windows[surface] === win else { return }
                self.publishFrame(surface: surface, window: win)
            }
        })

        tokens.append(nc.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            let win = note.object as? NSWindow
            Task { @MainActor in
                guard let self, let win, self.windows[surface] === win else { return }
                self.publishFrame(surface: surface, window: win)
            }
        })

        tokens.append(nc.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            let win = note.object as? NSWindow
            Task { @MainActor in
                guard let self, let win, self.windows[surface] === win else { return }
                self.publishFrame(surface: surface, window: win)
            }
        })

        observerTokens[surface] = tokens
        // Capture initial/restored frame once registered.
        publishFrame(surface: surface, window: window)
    }

    func unregister(surface: FloatSurfaceID, window: NSWindow? = nil) {
        if let window, let existing = windows[surface], existing !== window {
            return
        }
        if let tokens = observerTokens.removeValue(forKey: surface) {
            for t in tokens {
                NotificationCenter.default.removeObserver(t)
            }
        }
        windows.removeValue(forKey: surface)
    }

    func window(for surface: FloatSurfaceID) -> NSWindow? {
        windows[surface]
    }

    func closeWindow(for surface: FloatSurfaceID) {
        guard let win = windows[surface] else { return }
        // Unregister first so willClose does not treat this as user-close redock.
        unregister(surface: surface, window: win)
        win.close()
    }

    /// Close every registered auxiliary surface during application termination.
    /// Registrations are removed first so close notifications cannot redock them.
    func closeAllWindows() {
        let registered = windows
        for (surface, window) in registered {
            unregister(surface: surface, window: window)
            window.close()
        }
    }

    func focusWindow(for surface: FloatSurfaceID) {
        guard let win = windows[surface] else { return }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Private

    private func publishFrame(surface: FloatSurfaceID, window: NSWindow) {
        let frame = window.frame
        let screen = window.screen
        let screenID = screen.map { AuroraScreenIdentity.identifier(for: $0) }
        let screenName = screen.map { AuroraScreenIdentity.displayName(for: $0) }
        onFrameChanged?(surface, frame, screenID, screenName)
    }

    private func handleWindowWillClose(_ surface: FloatSurfaceID) {
        // Always drop registration when the window is going away.
        let wasRegistered = windows[surface] != nil
        if wasRegistered {
            if let tokens = observerTokens.removeValue(forKey: surface) {
                for t in tokens {
                    NotificationCenter.default.removeObserver(t)
                }
            }
            windows.removeValue(forKey: surface)
        }
        guard wasRegistered else { return }
        guard !isTerminating() else { return }
        onUserCloseWhileFloating?(surface)
    }
}
