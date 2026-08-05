import AuroraUI
import SwiftUI

/// Maps panel IDs to concrete views. Panels observe controller state via callbacks / appModel facades.
enum PanelRegistry {
    @MainActor
    static func view(id: WorkspacePanelID, context: WorkspacePanelContext, appModel: AppModel) -> AnyView {
        switch id {
        case .fixtureBrowser:
            return AnyView(
                FixtureBrowserPanel(
                    context: context,
                    onInspectFixtures: { ids in
                        appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                        appModel.notifyUI()
                    },
                    onInspectGroup: { id in
                        appModel.workspace.noteExplicitGroupInspect(id: id)
                        appModel.notifyUI()
                    }
                )
            )
        case .patch:
            return AnyView(PatchPanel(context: context))
        case .inspector:
            return AnyView(
                InspectorPanel(
                    context: context,
                    focus: {
                        switch appModel.workspace.inspectorFocus {
                        case .project: return .project
                        case .fixtures: return .fixtures
                        case .multiFixtures: return .multiFixtures
                        case .group(let id): return .group(id)
                        case .cue(let id): return .cue(id)
                        case .palette(let id): return .palette(id)
                        case .preset(let id): return .preset(id)
                        case .song(let id): return .song(id)
                        }
                    }(),
                    playbackCueIndex: appModel.performance.cueIndex,
                    playbackCueListID: appModel.performance.cueListID,
                    playbackCueID: appModel.performance.playbackCueID,
                    onSelectFixtures: { ids in
                        appModel.session.selectFixturesOrdered(ids, extending: false)
                        appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                        appModel.notifyUI()
                    }
                )
            )
        case .cueList:
            return AnyView(
                CueListPanel(
                    context: context,
                    playbackCueIndex: appModel.performance.cueIndex,
                    playbackCueListID: appModel.performance.cueListID,
                    playbackCueID: appModel.performance.playbackCueID,
                    onGo: { appModel.go() },
                    onStop: { appModel.stopPlayback() },
                    onBack: { appModel.back() },
                    onFire: { appModel.fireCue(id: $0) },
                    onProjectChanged: {
                        appModel.reloadEngineFromSession()
                        appModel.notifyUI()
                    },
                    onInspectCue: { id in
                        appModel.workspace.setInspectorFocus(.cue(id))
                        appModel.notifyUI()
                    },
                    onSelectCue: { cueID, _ in
                        appModel.workspace.setInspectorFocus(.cue(cueID))
                        appModel.notifyUI()
                    },
                    documentEpoch: appModel.workspace.documentEpoch
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
            return AnyView(
                GroupsPanel(
                    context: context,
                    onChanged: { appModel.notifyUI() },
                    onInspectGroup: { id in
                        appModel.workspace.setInspectorFocus(.group(id))
                        appModel.notifyUI()
                    }
                )
            )
        case .palettes:
            return AnyView(
                PalettesPanel(
                    context: context,
                    programmer: appModel.engine.programmer,
                    onChanged: { appModel.notifyUI() },
                    onInspectPalette: { id in
                        appModel.workspace.setInspectorFocus(.palette(id))
                        appModel.notifyUI()
                    },
                    onInspectPreset: { id in
                        appModel.workspace.setInspectorFocus(.preset(id))
                        appModel.notifyUI()
                    }
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
                        appModel.workspace.setInspectorFocus(.song(song.id))
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
                    onChanged: { appModel.notifyUI() },
                    onInspectSong: { id in
                        appModel.workspace.setInspectorFocus(.song(id))
                        appModel.notifyUI()
                    }
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
            return LegacyWorkspaceView.defaultPanel(id: id, context: context)
        }
    }
}
