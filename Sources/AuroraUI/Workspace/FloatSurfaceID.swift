import CoreGraphics
import Foundation

// MARK: - C5 detachable surfaces

/// Surfaces that can float as independent macOS windows (C5A).
/// Workspace/UI state only — not lighting-show content.
public enum FloatSurfaceID: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case browser
    case stagePreview
    case programmer
    case inspector
    case lowerShelf
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .browser: return "Browser"
        case .stagePreview: return "Stage Preview"
        case .programmer: return "Programmer"
        case .inspector: return "Inspector"
        case .lowerShelf: return "Creative Shelf"
        case .diagnostics: return "Diagnostics"
        }
    }

    public var defaultSize: CGSize {
        switch self {
        case .browser: return CGSize(width: 320, height: 720)
        case .stagePreview: return CGSize(width: 900, height: 640)
        case .programmer: return CGSize(width: 720, height: 420)
        case .inspector: return CGSize(width: 340, height: 720)
        case .lowerShelf: return CGSize(width: 960, height: 320)
        case .diagnostics: return CGSize(width: 640, height: 480)
        }
    }

    public var minimumSize: CGSize {
        switch self {
        case .browser: return CGSize(width: 220, height: 320)
        case .stagePreview: return CGSize(width: 400, height: 280)
        case .programmer: return CGSize(width: 420, height: 220)
        case .inspector: return CGSize(width: 240, height: 320)
        case .lowerShelf: return CGSize(width: 480, height: 180)
        case .diagnostics: return CGSize(width: 360, height: 240)
        }
    }

    /// Subtools expected on Browser (Fixtures / Groups) — contract for C5.1 tests.
    public static let browserSubtools = ["Browser", "Groups"]

    /// Subtools expected on Creative Shelf — contract for C5.1 tests.
    public static let creativeShelfSubtools = ["Palettes", "Cues", "Song", "Diagnostics"]
}

/// Docked in main window, floating in its own window, or hidden.
public enum PanelPresentationKind: String, Codable, Sendable, Hashable {
    case docked
    case floating
    case hidden
}

/// Controls whether floating workspace surfaces are restored across application launches.
/// This is an application preference, never part of a show document.
public enum WorkspaceScreenMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case single
    case multi

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .single: return "Single Screen"
        case .multi: return "Multi Screen"
        }
    }
}

public enum WorkspaceScreenModeStore {
    private static let key = "prism.workspace.screen-mode"

    public static func load(from defaults: UserDefaults = .standard) -> WorkspaceScreenMode {
        guard let raw = defaults.string(forKey: key),
              let mode = WorkspaceScreenMode(rawValue: raw)
        else { return .single }
        return mode
    }

    public static func save(_ mode: WorkspaceScreenMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

/// Per-surface float presentation (C5B).
public struct FloatSurfaceRecord: Codable, Equatable, Sendable, Hashable {
    public var kind: PanelPresentationKind
    /// Window origin/size in global screen coordinates when floating.
    public var frameX: Double?
    public var frameY: Double?
    public var frameW: Double?
    public var frameH: Double?
    /// Best-effort durable screen identity (display ID string preferred over localized name).
    public var screenID: String?
    /// Optional human-readable name for diagnostics.
    public var screenName: String?

    public init(
        kind: PanelPresentationKind = .docked,
        frameX: Double? = nil,
        frameY: Double? = nil,
        frameW: Double? = nil,
        frameH: Double? = nil,
        screenID: String? = nil,
        screenName: String? = nil
    ) {
        self.kind = kind
        self.frameX = frameX
        self.frameY = frameY
        self.frameW = frameW
        self.frameH = frameH
        self.screenID = screenID
        self.screenName = screenName
    }

    public var frame: CGRect? {
        guard let x = frameX, let y = frameY, let w = frameW, let h = frameH, w > 1, h > 1 else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    public mutating func setFrame(_ rect: CGRect) {
        frameX = rect.origin.x
        frameY = rect.origin.y
        frameW = rect.size.width
        frameH = rect.size.height
    }
}

/// One available display used for C5.1 frame recovery (visible frame, not full frame).
public struct ScreenVisibleRecord: Equatable, Sendable, Hashable {
    public var id: String
    public var visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

/// Full multi-window presentation map (C5B / C5F-ready for future presets).
public struct WorkspaceFloatState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var surfaces: [String: FloatSurfaceRecord]

    public init(
        schemaVersion: Int = WorkspaceFloatState.currentSchemaVersion,
        surfaces: [String: FloatSurfaceRecord] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.surfaces = surfaces
    }

    public static let `default` = WorkspaceFloatState()

    public func record(for id: FloatSurfaceID) -> FloatSurfaceRecord {
        surfaces[id.rawValue] ?? FloatSurfaceRecord()
    }

    public mutating func setRecord(_ record: FloatSurfaceRecord, for id: FloatSurfaceID) {
        surfaces[id.rawValue] = record
    }

    public func isFloating(_ id: FloatSurfaceID) -> Bool {
        record(for: id).kind == .floating
    }

    public func isDocked(_ id: FloatSurfaceID) -> Bool {
        record(for: id).kind == .docked
    }

    /// Surface content should appear in the main shell (docked, not floating/hidden).
    public func showsInMainWindow(_ id: FloatSurfaceID) -> Bool {
        record(for: id).kind == .docked
    }

    public mutating func float(
        _ id: FloatSurfaceID,
        frame: CGRect? = nil,
        screenID: String? = nil,
        screenName: String? = nil
    ) {
        var r = record(for: id)
        r.kind = .floating
        if let frame { r.setFrame(frame) }
        if let screenID { r.screenID = screenID }
        if let screenName { r.screenName = screenName }
        setRecord(r, for: id)
    }

    public mutating func dock(_ id: FloatSurfaceID) {
        var r = record(for: id)
        r.kind = .docked
        setRecord(r, for: id)
    }

    public mutating func hide(_ id: FloatSurfaceID) {
        var r = record(for: id)
        r.kind = .hidden
        setRecord(r, for: id)
    }

    public mutating func dockAll() {
        for id in FloatSurfaceID.allCases where record(for: id).kind == .floating {
            dock(id)
        }
    }

    /// Legacy API: treat each rect as a screen visible frame (ids synthetic).
    public mutating func recoverFramesToVisibleScreens(_ screens: [CGRect]) {
        let records = screens.enumerated().map { idx, frame in
            ScreenVisibleRecord(id: "screen-\(idx)", visibleFrame: frame)
        }
        recoverFrames(to: records)
    }

    /// C5.1: recover floating frames onto **per-screen visible frames**.
    /// Avoids placing windows in monitor gaps (union geometry) or under menu bar/Dock.
    @discardableResult
    public mutating func recoverFrames(to screens: [ScreenVisibleRecord]) -> Bool {
        guard !screens.isEmpty else { return false }
        var changed = false
        for key in surfaces.keys {
            guard var rec = surfaces[key], rec.kind == .floating,
                  let frame = rec.frame, frame.width > 1, frame.height > 1 else {
                continue
            }
            let recovered = Self.recoverFrame(frame, preferredScreenID: rec.screenID, screens: screens)
            if recovered.frame != frame || recovered.screenID != rec.screenID {
                rec.setFrame(recovered.frame)
                if let sid = recovered.screenID {
                    rec.screenID = sid
                }
                surfaces[key] = rec
                changed = true
            }
        }
        return changed
    }

    /// Pure recovery for a single window frame (testable without AppKit).
    public static func recoverFrame(
        _ frame: CGRect,
        preferredScreenID: String?,
        screens: [ScreenVisibleRecord]
    ) -> (frame: CGRect, screenID: String?) {
        guard !screens.isEmpty else { return (frame, preferredScreenID) }

        // 1. Prefer the saved screen when it still exists.
        let host: ScreenVisibleRecord
        if let preferredScreenID,
           let match = screens.first(where: { $0.id == preferredScreenID }) {
            host = match
        } else {
            // 2. Screen with greatest intersection area.
            var best: ScreenVisibleRecord?
            var bestArea: CGFloat = 0
            for s in screens {
                let inter = s.visibleFrame.intersection(frame)
                let area = inter.isNull ? 0 : inter.width * inter.height
                if area > bestArea {
                    bestArea = area
                    best = s
                }
            }
            // 3. No intersection (gap / removed monitor) → primary (first) screen.
            host = best ?? screens[0]
        }

        var f = frame
        let vis = host.visibleFrame

        // Fit within host if larger than visible area.
        if f.width > vis.width {
            f.size.width = max(200, vis.width * 0.9)
        }
        if f.height > vis.height {
            f.size.height = max(160, vis.height * 0.9)
        }

        // Ensure meaningful intersection with host visible frame (title bar reachable).
        let titleBarSlop: CGFloat = 28
        if !vis.intersects(f) {
            f.origin.x = vis.midX - f.width / 2
            f.origin.y = vis.midY - f.height / 2
        }

        // Clamp so at least the top strip of the window sits on the visible frame.
        if f.maxX > vis.maxX { f.origin.x = vis.maxX - f.width }
        if f.minX < vis.minX { f.origin.x = vis.minX }
        // Keep top of window (macOS y increases upward) on-screen.
        if f.maxY > vis.maxY { f.origin.y = vis.maxY - f.height }
        if f.minY < vis.minY { f.origin.y = vis.minY }
        // Prefer title bar (top of window = maxY) inside visible area.
        if f.maxY - titleBarSlop > vis.maxY {
            f.origin.y = vis.maxY - f.height
        }
        if f.maxY < vis.minY + titleBarSlop {
            f.origin.y = vis.minY + titleBarSlop - f.height
            if f.minY < vis.minY { f.origin.y = vis.minY }
        }

        return (f, host.id)
    }

    public var floatingSurfaceIDs: [FloatSurfaceID] {
        FloatSurfaceID.allCases.filter { isFloating($0) }
    }
}

// MARK: - Persistence (main-actor owned; workspace mutations are UI-originated)

@MainActor
public enum WorkspaceFloatStore {
    public static let defaultsKey = "aurora.workspace.float.v1"
    private static var pending: WorkspaceFloatState?
    private static var workItem: DispatchWorkItem?

    public static func load(from defaults: UserDefaults = .standard) -> WorkspaceFloatState {
        guard let data = defaults.data(forKey: defaultsKey) else { return .default }
        do {
            var state = try JSONDecoder().decode(WorkspaceFloatState.self, from: data)
            if state.schemaVersion > WorkspaceFloatState.currentSchemaVersion {
                return .default
            }
            state.schemaVersion = WorkspaceFloatState.currentSchemaVersion
            return state
        } catch {
            return .default
        }
    }

    public static func save(_ state: WorkspaceFloatState, to defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: defaultsKey)
        } catch {
            // Best-effort.
        }
    }

    public static func saveDebounced(_ state: WorkspaceFloatState, delay: TimeInterval = 0.35) {
        pending = state
        workItem?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                if let pending {
                    save(pending)
                    self.pending = nil
                }
            }
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public static func flushPending() {
        workItem?.cancel()
        workItem = nil
        if let pending {
            save(pending)
            self.pending = nil
        }
    }
}
