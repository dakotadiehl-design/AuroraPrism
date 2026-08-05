import AuroraUI
import SwiftUI

/// Maps panel IDs to concrete views (PR8 replaces patch/browser placeholders).
enum PanelRegistry {
    @MainActor
    static func view(id: WorkspacePanelID, context: WorkspacePanelContext) -> AnyView {
        switch id {
        case .fixtureBrowser:
            return AnyView(FixtureBrowserPanel(context: context))
        case .patch:
            return AnyView(PatchPanel(context: context))
        case .inspector:
            return AnyView(InspectorPanel(context: context))
        default:
            return WorkspaceView.defaultPanel(id: id, context: context)
        }
    }
}
