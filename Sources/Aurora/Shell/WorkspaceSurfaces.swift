import AuroraUI
import SwiftUI

// MARK: - Browser (Fixtures + Groups) — docked + floating (C5.1)

/// Production DESIGN browser surface. Same host for main workspace and float windows.
struct BrowserWorkspaceSurface: View {
    @EnvironmentObject private var appModel: AppModel
    var showsUndockChrome: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            toolTabBar
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
                        },
                        onRevealOnStage: { id in
                            appModel.workspace.revealOnStage(fixtureID: id)
                            appModel.notifyUI()
                        }
                    )
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
        .panelChromeShell(title: title, trailing: {
            if showsUndockChrome {
                UndockSurfaceButton(surface: .browser, showTitle: false)
                    .labelStyle(.iconOnly)
                    .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    .controlSize(.small)
            }
        })
    }

    private var title: String {
        switch appModel.workspace.leftTool {
        case .browser: return "Fixtures"
        case .groups: return "Groups"
        }
    }

    private var toolTabBar: some View {
        let tools = BuildLeftTool.programTools
        return HStack(spacing: 2) {
            ForEach(tools) { tool in
                let selected = appModel.workspace.leftTool == tool
                Button {
                    appModel.workspace.setLeftTool(tool)
                    appModel.notifyUI()
                } label: {
                    Text(tool.rawValue)
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(selected ? AuroraColor.accentBright : AuroraColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: AuroraMetrics.tabHeight)
                        .background(selected ? AuroraColor.surfacePanel : Color.clear)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .background(AuroraColor.surfaceHeader)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: AuroraMetrics.hairline)
        }
    }
}

// MARK: - Creative Shelf (Palettes / Cues / Song / Diagnostics)

/// Production lower shelf. Shared `workspace.lowerTool` in docked and floating hosts.
struct CreativeShelfWorkspaceSurface: View {
    @EnvironmentObject private var appModel: AppModel
    var showsUndockChrome: Bool = true
    var showsCollapseControl: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                toolTabBar
                Spacer(minLength: 8)
                if showsCollapseControl {
                    Button {
                        appModel.workspace.setLowerShelfCollapsed(true)
                        appModel.notifyUI()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AuroraColor.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: AuroraMetrics.tabHeight)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse lower shelf")
                }
            }
            shelfBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .panelChromeShell(title: appModel.workspace.lowerTool.rawValue, trailing: {
            if showsUndockChrome {
                UndockSurfaceButton(surface: .lowerShelf, showTitle: false)
                    .labelStyle(.iconOnly)
                    .buttonStyle(AuroraButtonStyle(kind: .quiet))
                    .controlSize(.small)
            }
        })
    }

    private var toolTabBar: some View {
        HStack(spacing: 2) {
            ForEach(BuildLowerTool.allCases) { tool in
                let selected = appModel.workspace.lowerTool == tool
                Button {
                    appModel.workspace.setLowerTool(tool)
                    appModel.notifyUI()
                } label: {
                    Text(tool.rawValue)
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(selected ? AuroraColor.accentBright : AuroraColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: AuroraMetrics.tabHeight)
                        .background(selected ? AuroraColor.surfacePanel : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(AuroraColor.surfaceHeader)
    }

    @ViewBuilder
    private var shelfBody: some View {
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
                onProjectChanged: { appModel.notifyUI() },
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
        case .diagnostics:
            DiagnosticsPanel(snapshot: diagnosticsViewSnapshot)
        }
    }

    private var diagnosticsViewSnapshot: DiagnosticsPanel.SnapshotView {
        let s = appModel.diagnostics.snapshot
        return DiagnosticsPanel.SnapshotView(
            engineRunning: s.engineRunning,
            frameRateHz: s.frameRateHz,
            outputStatusLine: s.outputStatusLine,
            localDMXStatus: s.localDMXStatus,
            localDMXEnabled: s.localDMXEnabled,
            localDMXRequested: s.localDMXRequested,
            localDMXDeviceAvailable: s.localDMXDeviceAvailable,
            artNetEnabled: s.artNetEnabled,
            sacnEnabled: s.sacnEnabled,
            midiStatus: s.midiStatus,
            midiState: s.midiState,
            midiSourceCount: s.midiSourceCount,
            remoteStatus: s.remoteStatus,
            remoteActuallyRunning: s.remoteActuallyRunning,
            remoteClientCount: s.remoteClientCount,
            validationIssueCount: s.validationIssueCount,
            driverRows: s.driverHealth.map {
                .init(id: $0.id, title: $0.name, detail: "\($0.state)\($0.lastError.map { " · \($0)" } ?? "")")
            },
            universeRows: s.universeRoutes.map {
                .init(
                    id: $0.id.uuidString,
                    title: "U\($0.number) \($0.name) · \($0.configuredRoute)",
                    detail: "\($0.availability) · \($0.runtimeHealth)"
                )
            },
            consoleTail: Array(appModel.consoleLog.suffix(20)),
            fixtureHealthRows: appModel.fixtureHealthRows(),
            externalControlRows: appModel.externalControl.entries.suffix(30).reversed().map { e in
                .init(
                    id: e.id.uuidString,
                    title: "\(Self.timeFmt.string(from: e.time))  \(e.source)  \(e.event)",
                    detail: "\(e.mapping) → \(e.result)"
                )
            }
        )
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - Programmer / Inspector / Diagnostics wrappers (PanelRegistry parity)

struct ProgrammerWorkspaceSurface: View {
    @EnvironmentObject private var appModel: AppModel
    var showsUndockChrome: Bool = false

    var body: some View {
        PanelRegistry.view(id: .programmer, context: appModel.panelContext, appModel: appModel)
    }
}

struct InspectorWorkspaceSurface: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        PanelRegistry.view(id: .inspector, context: appModel.panelContext, appModel: appModel)
    }
}

struct DiagnosticsWorkspaceSurface: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        PanelRegistry.view(id: .console, context: appModel.panelContext, appModel: appModel)
    }
}

// MARK: - Compact restore affordance (C5.1 space reclaim)

/// Thin strip when a surface is floated — does not reserve full original geometry.
struct CompactFloatRestoreChip: View {
    let surface: FloatSurfaceID
    var onDock: () -> Void
    var onFocus: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AuroraColor.textTertiary)
            Text("\(surface.title) floated")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let onFocus {
                Button("Show") { onFocus() }
                    .buttonStyle(AuroraButtonStyle(kind: .secondary))
                    .controlSize(.mini)
            }
            Button("Dock") { onDock() }
                .buttonStyle(AuroraButtonStyle(kind: .primary))
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(AuroraColor.surfaceHeader)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: AuroraMetrics.hairline)
        }
        .help("\(surface.title) is in a separate window — Dock to return")
    }
}
