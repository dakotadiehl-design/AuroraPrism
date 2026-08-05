import AuroraUI
import SwiftUI

/// Root workspace chrome for the main document window.
struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceView(
                layout: Binding(
                    get: { appModel.workspace.layout },
                    set: {
                        appModel.workspace.layout = $0
                        WorkspaceLayoutStore.save($0)
                        appModel.notifyUI()
                    }
                ),
                context: appModel.panelContext,
                panelBuilder: { id, ctx in
                    PanelRegistry.view(id: id, context: ctx, appModel: appModel)
                }
            )
            Divider()
            HStack {
                Text(appModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if appModel.workspace.mode == .perform {
                    Text(appModel.performance.cueName.isEmpty
                         ? "Cue —"
                         : "Cue \(appModel.performance.cueIndex + 1) \(appModel.performance.cueName)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.tertiary)
                }
                Text(appModel.performance.outputStatusLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(appModel.midiStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(appModel.engineStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(appModel.session.project.fixtures.count) fixtures · \(appModel.session.project.universes.count) universes")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if appModel.performance.validationIssueCount > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(appModel.performance.validationIssueCount) issues")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 900, minHeight: 560)
        // Stage C: observe composition root + controllers; no global .id(revision).
        .navigationTitle(appModel.windowTitle)
    }
}

#if DEBUG
#Preview("Aurora Workspace") {
    ContentView()
        .environmentObject(AppModel())
        .frame(width: 1100, height: 720)
}
#endif

