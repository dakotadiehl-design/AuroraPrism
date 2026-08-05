import AuroraUI
import Foundation

/// Build/Perform mode, panel layout, and UI-only workspace state (Stage C).
@MainActor
final class WorkspaceController: ObservableObject {
    @Published var layout: WorkspaceLayout
    @Published var mode: WorkspaceMode = .build

    init(layout: WorkspaceLayout = WorkspaceLayoutStore.load()) {
        self.layout = layout
    }

    func togglePanel(_ id: WorkspacePanelID) {
        layout.toggle(id)
        WorkspaceLayoutStore.save(layout)
        objectWillChange.send()
    }

    func setMode(_ mode: WorkspaceMode) {
        self.mode = mode
    }

    func isVisible(_ id: WorkspacePanelID) -> Bool {
        layout.isVisible(id)
    }
}
