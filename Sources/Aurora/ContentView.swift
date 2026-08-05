import AuroraUI
import SwiftUI

/// Root workspace chrome for the main document window.
struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceView(
                layout: $appModel.layout,
                context: appModel.panelContext,
                panelBuilder: PanelRegistry.view
            )
            Divider()
            HStack {
                Text(appModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(appModel.engineStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(appModel.session.project.fixtures.count) fixtures · \(appModel.session.project.universes.count) universes")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 900, minHeight: 560)
        .id(appModel.revision)
        .navigationTitle(appModel.windowTitle)
    }
}
