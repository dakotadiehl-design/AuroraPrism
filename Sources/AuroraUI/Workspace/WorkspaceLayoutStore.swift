import Foundation

/// Loads/saves `WorkspaceLayout` in UserDefaults (UI-11 A10 debounced save).
public enum WorkspaceLayoutStore {
    public static let defaultsKey = "aurora.workspace.layout.v2"
    private static var pendingLayout: WorkspaceLayout?
    private static var debounceWorkItem: DispatchWorkItem?
    private static let debounceQueue = DispatchQueue(label: "com.aurora.layout.persist")

    public static func load(from defaults: UserDefaults = .standard) -> WorkspaceLayout {
        guard let data = defaults.data(forKey: defaultsKey)
            ?? defaults.data(forKey: "aurora.workspace.layout.v1")
        else {
            return .default
        }
        do {
            var layout = try JSONDecoder().decode(WorkspaceLayout.self, from: data)
            if layout.schemaVersion > WorkspaceLayout.currentSchemaVersion {
                return .default
            }
            layout.schemaVersion = WorkspaceLayout.currentSchemaVersion
            layout.clampToSafeGeometry()
            return layout
        } catch {
            return .default
        }
    }

    /// Immediate persist (drag end, preset apply, app lifecycle).
    public static func save(_ layout: WorkspaceLayout, to defaults: UserDefaults = .standard) {
        var copy = layout
        copy.clampToSafeGeometry()
        do {
            let data = try JSONEncoder().encode(copy)
            defaults.set(data, forKey: defaultsKey)
        } catch {
            // Best-effort.
        }
    }

    /// Debounced persist during split drag (UI-11 A10).
    public static func saveDebounced(
        _ layout: WorkspaceLayout,
        delay: TimeInterval = 0.35,
        to defaults: UserDefaults = .standard
    ) {
        pendingLayout = layout
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem {
            if let pending = pendingLayout {
                save(pending, to: defaults)
                pendingLayout = nil
            }
        }
        debounceWorkItem = work
        debounceQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public static func flushPending(to defaults: UserDefaults = .standard) {
        debounceWorkItem?.cancel()
        if let pending = pendingLayout {
            save(pending, to: defaults)
            pendingLayout = nil
        }
    }
}
