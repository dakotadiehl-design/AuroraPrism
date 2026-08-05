import Foundation

/// Loads/saves `WorkspaceLayout` in UserDefaults.
public enum WorkspaceLayoutStore {
    public static let defaultsKey = "aurora.workspace.layout.v1"

    public static func load(from defaults: UserDefaults = .standard) -> WorkspaceLayout {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(WorkspaceLayout.self, from: data)
        } catch {
            return .default
        }
    }

    public static func save(_ layout: WorkspaceLayout, to defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(layout)
            defaults.set(data, forKey: defaultsKey)
        } catch {
            // Best-effort persistence; ignore encode failures.
        }
    }
}
