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
        case .groups:
            return AnyView(GroupsPanel(context: context, onChanged: { appModel.bump() }))
        case .palettes:
            return AnyView(
                PalettesPanel(
                    context: context,
                    programmer: appModel.engine.programmer,
                    onChanged: { appModel.bump() }
                )
            )
        case .midi:
            return AnyView(
                MIDIMappingsPanel(
                    context: context,
                    isLearning: appModel.isMIDILearning,
                    onLearn: { appModel.armMIDILearn($0) },
                    onCancelLearn: { appModel.cancelMIDILearn() },
                    onChanged: { appModel.bump() }
                )
            )
        case .song:
            return AnyView(
                SongPanel(
                    context: context,
                    entryIndex: appModel.songDirector.entryIndex,
                    onLoadSong: { song in
                        appModel.songDirector.load(song: song, project: appModel.session.project, engine: appModel.engine)
                        appModel.songStatus = "\(song.title)"
                        appModel.bump()
                    },
                    onNext: {
                        appModel.songDirector.next(project: appModel.session.project, engine: appModel.engine)
                        appModel.bump()
                    },
                    onPrevious: {
                        appModel.songDirector.previous(project: appModel.session.project, engine: appModel.engine)
                        appModel.bump()
                    },
                    onChanged: { appModel.bump() }
                )
            )
        case .effects:
            return AnyView(
                EffectsPanel(
                    orderedSelectionFixtureIDs: appModel.session.selection.snapshot.orderedFixtureIDs,
                    effects: appModel.engine.effects,
                    onChanged: {
                        appModel.commitEffectsToProject()
                        appModel.bump()
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
