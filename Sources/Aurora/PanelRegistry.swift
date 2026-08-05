import AuroraUI
import SwiftUI

/// Maps panel IDs to concrete views. Panels observe controller state via callbacks / appModel facades.
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
                    playbackCueIndex: appModel.performance.cueIndex,
                    onGo: { appModel.go() },
                    onStop: { appModel.stopPlayback() },
                    onBack: { appModel.back() },
                    onFire: { appModel.fireCue(id: $0) },
                    onProjectChanged: {
                        appModel.reloadEngineFromSession()
                        appModel.notifyUI()
                    }
                )
            )
        case .programmer:
            return AnyView(
                ProgrammerPanel(
                    context: context,
                    programmer: appModel.engine.programmer,
                    project: appModel.session.project,
                    onChanged: { appModel.notifyUI() }
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
                    onBlind: { appModel.engine.programmer.setBlind($0); appModel.notifyUI() },
                    onHighlight: { appModel.engine.programmer.setHighlight($0); appModel.notifyUI() }
                )
            )
        case .groups:
            return AnyView(GroupsPanel(context: context, onChanged: { appModel.notifyUI() }))
        case .palettes:
            return AnyView(
                PalettesPanel(
                    context: context,
                    programmer: appModel.engine.programmer,
                    onChanged: { appModel.notifyUI() }
                )
            )
        case .midi:
            return AnyView(
                MIDIMappingsPanel(
                    context: context,
                    isLearning: appModel.isMIDILearning,
                    onLearn: { appModel.armMIDILearn($0) },
                    onCancelLearn: { appModel.cancelMIDILearn() },
                    onChanged: { appModel.notifyUI() }
                )
            )
        case .song:
            return AnyView(
                SongPanel(
                    context: context,
                    entryIndex: appModel.songDirector.entryIndex,
                    onLoadSong: { song in
                        appModel.showControl.loadSong(song, project: appModel.session.project)
                        appModel.notifyUI()
                    },
                    onNext: {
                        appModel.showControl.songNext(project: appModel.session.project)
                        appModel.notifyUI()
                    },
                    onPrevious: {
                        appModel.showControl.songPrevious(project: appModel.session.project)
                        appModel.notifyUI()
                    },
                    onChanged: { appModel.notifyUI() }
                )
            )
        case .effects:
            return AnyView(
                EffectsPanel(
                    orderedSelectionFixtureIDs: appModel.session.selection.snapshot.orderedFixtureIDs,
                    effects: appModel.engine.effects,
                    onChanged: {
                        appModel.commitEffectsToProject()
                        appModel.notifyUI()
                    }
                )
            )
        case .universeMonitor:
            return AnyView(
                UniverseMonitorPanel(
                    snapshot: appModel.engine.currentSnapshot(),
                    universes: appModel.session.project.universes,
                    defaultUniverseNumber: appModel.session.project.universes.first?.number ?? 1
                )
            )
        case .console:
            return AnyView(
                ConsolePanel(
                    lines: appModel.consoleLog,
                    midiLines: appModel.midiLog,
                    outputStatus: appModel.outputStatus
                )
            )
        default:
            return WorkspaceView.defaultPanel(id: id, context: context)
        }
    }
}
