import AuroraUI
import SwiftUI

/// Maps panel IDs to concrete views.
enum PanelRegistry {
    @MainActor
    static func view(id: WorkspacePanelID, context: WorkspacePanelContext, appModel: AppModel) -> AnyView {
        switch id {
        case .fixtureBrowser:
            return AnyView(FixtureBrowserPanel(context: context))
        case .patch:
            return AnyView(PatchPanel(context: context))
        case .inspector:
            return AnyView(InspectorPanel(context: context))
        case .cueList:
            return AnyView(
                CueListPanel(
                    context: context,
                    playbackCueIndex: appModel.engine.currentSnapshot().playback.cueIndex,
                    onGo: { appModel.go() },
                    onStop: { appModel.stopPlayback() },
                    onBack: { appModel.back() },
                    onFire: { appModel.fireCue(id: $0) },
                    onProjectChanged: {
                        appModel.reloadEngineFromSession()
                        appModel.bump()
                    }
                )
            )
        case .programmer:
            return AnyView(
                ProgrammerPanel(
                    context: context,
                    programmer: appModel.engine.programmer,
                    project: appModel.session.project,
                    onChanged: { appModel.bump() }
                )
            )
        case .livePlayback:
            return AnyView(
                LivePlaybackPanel(
                    snapshot: appModel.engine.currentSnapshot(),
                    onGo: { appModel.go() },
                    onStop: { appModel.stopPlayback() },
                    onBack: { appModel.back() },
                    isBlind: appModel.engine.programmer.snapshot().isBlind,
                    isHighlight: appModel.engine.programmer.snapshot().isHighlight,
                    onBlind: { appModel.engine.programmer.setBlind($0); appModel.bump() },
                    onHighlight: { appModel.engine.programmer.setHighlight($0); appModel.bump() }
                )
            )
        default:
            return WorkspaceView.defaultPanel(id: id, context: context)
        }
    }
}
