import AuroraUI
import SwiftUI

/// Production Build workspace — Option A navigation (UI-02E).
/// Programmer always remains the center of gravity.
struct BuildWorkspaceHost: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 1) {
            HSplitView {
                leftColumn
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

                programmerColumn
                    .frame(minWidth: 420)

                inspectorColumn
                    .frame(minWidth: 160, idealWidth: 210, maxWidth: 300)
            }
            .frame(maxHeight: .infinity)

            lowerRegion
                .frame(minHeight: 140, idealHeight: 200, maxHeight: 300)
        }
        .background(AuroraColor.surfaceWorkspace)
        .onChange(of: appModel.session.selection.snapshot.fixtureIDs) { _, ids in
            appModel.workspace.noteFixtureSelectionChanged(count: ids.count)
        }
    }

    // MARK: Left — Browser | Patch | Groups

    private var leftColumn: some View {
        VStack(spacing: 0) {
            toolTabBar(
                titles: BuildLeftTool.allCases.map(\.rawValue),
                selection: Binding(
                    get: { appModel.workspace.leftTool.rawValue },
                    set: { raw in
                        if let t = BuildLeftTool(rawValue: raw) {
                            appModel.workspace.setLeftTool(t)
                            appModel.notifyUI()
                        }
                    }
                )
            )
            Group {
                switch appModel.workspace.leftTool {
                case .browser:
                    FixtureBrowserPanel(
                        context: appModel.panelContext,
                        onInspectFixtures: { ids in
                            appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                            appModel.notifyUI()
                        },
                        onInspectGroup: { id in
                            appModel.workspace.noteExplicitGroupInspect(id: id)
                            appModel.notifyUI()
                        }
                    )
                case .patch:
                    PanelRegistry.view(id: .patch, context: appModel.panelContext, appModel: appModel)
                case .groups:
                    GroupsPanel(
                        context: appModel.panelContext,
                        onChanged: { appModel.notifyUI() },
                        onInspectGroup: { id in
                            appModel.workspace.setInspectorFocus(.group(id))
                            appModel.notifyUI()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .panelChromeShell(title: leftTitle)
    }

    private var leftTitle: String {
        switch appModel.workspace.leftTool {
        case .browser: return "Fixtures"
        case .patch: return "Patch"
        case .groups: return "Groups"
        }
    }

    // MARK: Center — Programmer (always)

    private var programmerColumn: some View {
        panelShell(title: "Programmer", trailing: {
            Text("\(appModel.session.selection.snapshot.fixtureIDs.count) selected")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.accentBright)
        }) {
            ProgrammerPanel(
                context: appModel.panelContext,
                programmer: appModel.engine.programmer,
                project: appModel.session.project,
                presentation: appModel.programmerPresentation.presentation,
                presentationRevision: appModel.programmerPresentation.revision,
                onChanged: { appModel.noteProgrammerUIChanged() }
            )
        }
    }

    // MARK: Right — Inspector

    private var inspectorColumn: some View {
        panelShell(title: "Inspector", trailing: {
            Text(focusLabel)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
        }) {
            InspectorPanel(
                context: appModel.panelContext,
                focus: mapFocus(appModel.workspace.inspectorFocus),
                playbackCueIndex: appModel.performance.cueIndex,
                playbackCueListID: appModel.performance.cueListID,
                playbackCueID: appModel.performance.playbackCueID,
                programmerValues: appModel.engine.programmer.snapshot().values,
                onSelectFixtures: { ids in
                    appModel.session.selectFixturesOrdered(ids, extending: false)
                    appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                    appModel.notifyUI()
                },
                onProjectChanged: { appModel.notifyUI() },
                onError: { msg in appModel.diagnostics.log(msg) },
                documentEpoch: appModel.workspace.documentEpoch,
                documentGeneration: appModel.session.documentGeneration
            )
        }
    }

    private var focusLabel: String {
        switch appModel.workspace.inspectorFocus {
        case .project: return "Project"
        case .fixtures: return "Fixture"
        case .multiFixtures: return "Multi"
        case .group: return "Group"
        case .cue: return "Cue"
        case .palette: return "Palette"
        case .preset: return "Preset"
        case .song: return "Song"
        }
    }

    private func mapFocus(_ f: InspectorFocus) -> InspectorFocusKind {
        switch f {
        case .project: return .project
        case .fixtures: return .fixtures
        case .multiFixtures: return .multiFixtures
        case .group(let id): return .group(id)
        case .cue(let id): return .cue(id)
        case .palette(let id): return .palette(id)
        case .preset(let id): return .preset(id)
        case .song(let id): return .song(id)
        }
    }

    // MARK: Lower — Palettes | Cues | Song

    private var lowerRegion: some View {
        VStack(spacing: 0) {
            toolTabBar(
                titles: BuildLowerTool.allCases.map(\.rawValue),
                selection: Binding(
                    get: { appModel.workspace.lowerTool.rawValue },
                    set: { raw in
                        if let t = BuildLowerTool(rawValue: raw) {
                            appModel.workspace.setLowerTool(t)
                            appModel.notifyUI()
                        }
                    }
                )
            )
            Group {
                switch appModel.workspace.lowerTool {
                case .palettes:
                    PalettesPanel(
                        context: appModel.panelContext,
                        programmer: appModel.engine.programmer,
                        focusedPaletteID: {
                            if case .palette(let id) = appModel.workspace.inspectorFocus { return id }
                            return nil
                        }(),
                        focusedPresetID: {
                            if case .preset(let id) = appModel.workspace.inspectorFocus { return id }
                            return nil
                        }(),
                        onChanged: { appModel.noteProgrammerUIChanged() },
                        onProjectChanged: { appModel.notifyUI() },
                        onInspectPalette: { id in
                            appModel.workspace.setInspectorFocus(.palette(id))
                            appModel.notifyUI()
                        },
                        onInspectPreset: { id in
                            appModel.workspace.setInspectorFocus(.preset(id))
                            appModel.notifyUI()
                        },
                        onClearInspector: {
                            appModel.workspace.setInspectorFocus(.project)
                            appModel.notifyUI()
                        }
                    )
                case .cues:
                    CueListPanel(
                        context: appModel.panelContext,
                        programmer: appModel.engine.programmer,
                        playbackCueIndex: appModel.performance.cueIndex,
                        playbackCueListID: appModel.performance.cueListID,
                        playbackCueID: appModel.performance.playbackCueID,
                        onGo: { appModel.go() },
                        onStop: { appModel.stopPlayback() },
                        onBack: { appModel.back() },
                        onFire: { appModel.fireCue(id: $0) },
                        onProjectChanged: {
                            // DocumentSession.perform already triggers applyProjectUpdate (UUID-preserving).
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
                case .song:
                    SongPanel(
                        context: appModel.panelContext,
                        entryIndex: appModel.songDirector.entryIndex,
                        loadedSongID: appModel.songDirector.songID,
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .panelChromeShell(title: appModel.workspace.lowerTool.rawValue)
    }

    // MARK: - Chrome helpers

    private func toolTabBar(titles: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 2) {
            ForEach(titles, id: \.self) { title in
                Button {
                    selection.wrappedValue = title
                } label: {
                    Text(title)
                        .font(AuroraTypography.tab)
                        .foregroundStyle(selection.wrappedValue == title ? AuroraColor.textPrimary : AuroraColor.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: AuroraMetrics.tabHeight)
                        .background(selection.wrappedValue == title ? AuroraColor.accentMuted : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selection.wrappedValue == title {
                                Rectangle().fill(AuroraColor.accent).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .background(AuroraColor.surfaceHeader)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tools")
    }

    private func panelShell<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            AuroraPanelHeader(title: title, trailing: trailing)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AuroraColor.surfacePanel)
        }
        .background(AuroraColor.surfacePanel)
        .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraMetrics.radiusPanel, style: .continuous)
                .strokeBorder(AuroraColor.separatorStrong, lineWidth: AuroraMetrics.hairline)
        )
    }
}

private extension View {
    func panelChromeShell(title: String) -> some View {
        VStack(spacing: 0) {
            AuroraPanelHeader(title: title)
            self
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AuroraColor.surfacePanel)
        }
        .background(AuroraColor.surfacePanel)
        .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraMetrics.radiusPanel, style: .continuous)
                .strokeBorder(AuroraColor.separatorStrong, lineWidth: AuroraMetrics.hairline)
        )
    }
}
