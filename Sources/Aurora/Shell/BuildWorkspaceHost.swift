import AuroraDesignSystem
import AppKit
import AuroraCore
import AuroraModel
import AuroraUI
import SwiftUI

/// Production Build workspace — Lightkey-aligned DESIGN (C2) + Patch / Stage / Profiles.
///
/// **DESIGN** (`program`) — Browser/Groups | Stage Preview + Programmer | Inspector + lower shelf.
/// **PATCH** — Patch owns the center.
/// **STAGE** — Full StagePanel host (same StageCanvasView) for layout focus until C3 demotes it.
/// **PROFILES** — personality editor.
struct BuildWorkspaceHost: View {
    @EnvironmentObject private var appModel: AppModel

    /// Drag start fractions so translation is applied once from gesture origin (LAYOUT-01).
    @State private var dragStartLeading: Double?
    @State private var dragStartTrailing: Double?
    @State private var dragStartBottom: Double?
    @State private var dragStartDesignPreview: Double?
    /// Divider motion is kept local until mouse-up. Publishing/persisting the
    /// workspace on every pointer sample caused overlapping, partially laid-out
    /// frames across the Stage, Programmer, and Inspector.
    @State private var liveLeadingFraction: Double?
    @State private var liveTrailingFraction: Double?
    @State private var liveBottomFraction: Double?
    @State private var liveDesignPreviewFraction: Double?
    /// Edit Stage left rail tab (C5.1: rail stays docked; Stage surface can float).
    @State private var designStageRail: DesignStageRailTab = .unplaced

    private var layout: WorkspaceLayout { appModel.workspace.layout }
    private var buildMode: BuildWorkspaceMode { appModel.workspace.buildWorkspaceMode }
    private var stageEditActive: Bool { appModel.workspace.stageEditActive }

    private var displayedLeadingFraction: Double {
        layout.leadingFraction
    }

    private var displayedTrailingFraction: Double {
        layout.trailingFraction
    }

    private var displayedBottomFraction: Double {
        layout.bottomFraction
    }

    private var displayedDesignPreviewFraction: Double {
        layout.designPreviewFraction
    }

    private var isResizingWorkspace: Bool {
        liveLeadingFraction != nil
            || liveTrailingFraction != nil
            || liveBottomFraction != nil
            || liveDesignPreviewFraction != nil
    }

    /// Mode bar highlight: STAGE alias while Edit Stage is active on DESIGN.
    private var modeBarSelection: BuildWorkspaceMode {
        if stageEditActive && buildMode == .program { return .stage }
        return buildMode
    }

    private var showInspector: Bool {
        layout.isVisible(.inspector)
            && appModel.workspace.showsInMainWindow(.inspector)
    }

    /// Checkpoint A: lower Cue/Palette/Song only in Program (canvas modes need height).
    private var showLower: Bool {
        appModel.workspace.showsLowerRegionInCurrentBuildMode
            && appModel.workspace.showsInMainWindow(.lowerShelf)
            && (layout.isVisible(.cueList)
                || layout.isVisible(.cueBlocks)
                || layout.isVisible(.palettes)
                || layout.isVisible(.song)
                || layout.isVisible(.console))
    }

    /// C3.1: shelf body expanded (vs thin collapsed strip).
    private var lowerShelfExpanded: Bool {
        showLower && !layout.lowerShelfCollapsed
    }

    private let collapsedShelfHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            buildModeBar
            GeometryReader { geo in
                let totalH = max(geo.size.height, 1)
                let totalW = max(geo.size.width, 1)
                let bottomH: CGFloat = {
                    if !showLower { return 0 }
                    if lowerShelfExpanded {
                        return max(120, totalH * displayedBottomFraction)
                    }
                    return collapsedShelfHeight
                }()
                let dividerH: CGFloat = lowerShelfExpanded ? 4 : 0
                let mainH = totalH - bottomH - dividerH

                VStack(spacing: 0) {
                    Group {
                        switch buildMode {
                        case .program:
                            programMainRow(totalW: totalW)
                        case .patch:
                            patchMainRow(totalW: totalW)
                        case .stage:
                            // Defensive: setBuildWorkspaceMode(.stage) remaps to DESIGN+Edit;
                            // if STAGE is still current, show DESIGN edit layout.
                            programMainRow(totalW: totalW)
                        case .profiles:
                            profilesMainRow(totalW: totalW)
                        }
                    }
                    .frame(height: max(1, mainH))
                    .clipped()

                    if showLower {
                        if lowerShelfExpanded {
                            horizontalDivider(totalHeight: totalH)
                            CreativeShelfWorkspaceSurface(
                                showsUndockChrome: true,
                                showsCollapseControl: true
                            )
                            .frame(height: bottomH)
                            .clipped()
                        } else {
                            collapsedLowerShelfStrip
                                .frame(height: collapsedShelfHeight)
                        }
                    }
                }
                .background(AuroraColor.surfaceWorkspace)
                .clipped()
            }
        }
        .transaction { transaction in
            if isResizingWorkspace {
                transaction.animation = nil
            }
        }
        .onChange(of: appModel.session.selection.snapshot.fixtureIDs) { _, ids in
            appModel.workspace.noteFixtureSelectionChanged(count: ids.count)
        }
        .onReceive(NotificationCenter.default.publisher(for: .auroraOpenStageObjectsRail)) { note in
            if let raw = note.object as? String, raw == "unplaced" {
                designStageRail = .unplaced
            } else {
                designStageRail = .objects
            }
        }
    }

    // MARK: - Mode bar (PROGRAM | PATCH | STAGE | PROFILES)

    private var buildModeBar: some View {
        HStack(spacing: 0) {
            ForEach(BuildWorkspaceMode.allCases) { mode in
                Button {
                    if mode == .program {
                        appModel.workspace.exitEditStage()
                    }
                    appModel.workspace.setBuildWorkspaceMode(mode)
                    appModel.notifyUI()
                } label: {
                    let selected = modeBarSelection == mode
                    Text(mode.displayName.uppercased())
                        .font(AuroraTypography.tab)
                        .tracking(0.8)
                        .foregroundStyle(
                            selected ? AuroraColor.textPrimary : AuroraColor.textTertiary
                        )
                        .padding(.horizontal, 14)
                        .frame(height: AuroraMetrics.tabHeight + 4)
                        .background(selected ? AuroraColor.accentMuted : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(AuroraColor.accent).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(modeBarSelection == mode ? .isSelected : [])
            }
            Spacer(minLength: 8)
            if buildMode == .program {
                designFocusMenu
            }
            Text(modeHint)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 6)
        .background(AuroraColor.surfaceHeader)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: AuroraMetrics.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Build workspace")
    }

    private var designFocusMenu: some View {
        Menu {
            ForEach(DesignFocusPreset.allCases) { preset in
                Button(preset.rawValue) {
                    appModel.workspace.applyDesignFocus(preset)
                    appModel.notifyUI()
                }
            }
            Divider()
            Button(layout.stagePreviewCollapsed ? "Show Stage Preview" : "Hide Stage Preview") {
                appModel.workspace.toggleStagePreviewCollapsed()
                appModel.notifyUI()
            }
        } label: {
            Text("Layout")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
                .padding(.horizontal, 8)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 80)
    }

    private var modeHint: String {
        if stageEditActive {
            return "Edit Stage · geometry unlocked · same plot as Live"
        }
        switch buildMode {
        case .program:
            return layout.stagePreviewCollapsed
                ? "Design · Programmer focus"
                : "Design · see · select · program · visualize"
        case .patch: return "Build the rig · DMX universe"
        case .stage: return "Edit Stage · in Design"
        case .profiles: return "Fixture personalities"
        }
    }

    // MARK: - DESIGN layout (C2 + C3 Edit Stage in place)
    // Fixtures | Stage Preview (hero) + Programmer deck | Inspector
    // Edit Stage: Unplaced rail + geometry tools; geometry locked when off.

    private func programMainRow(totalW: CGFloat) -> some View {
        HStack(spacing: 0) {
            if stageEditActive {
                DesignStageEditRail(rail: $designStageRail)
                    .frame(width: max(168, totalW * min(displayedLeadingFraction, 0.22)))
                    .clipped()
            } else if appModel.workspace.showsInMainWindow(.browser) {
                BrowserWorkspaceSurface(showsUndockChrome: true)
                    .frame(width: max(160, totalW * displayedLeadingFraction))
                    .clipped()
            }
            // C5.1: when Browser is floated, reclaim column space (compact chip is optional via menu).
            if stageEditActive || appModel.workspace.showsInMainWindow(.browser) {
                verticalDivider(totalWidth: totalW)
            }
            designCenterColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            if showInspector {
                verticalDividerInspector(totalWidth: totalW)
                inspectorColumn
                    .frame(width: max(160, totalW * min(displayedTrailingFraction, 0.24)))
                    .clipped()
            }
            // C5.1: Inspector floated → no full-width placeholder; Dock via View menu.
        }
    }

    private var designCenterColumn: some View {
        GeometryReader { geo in
            let totalH = max(geo.size.height, 1)
            // Edit Stage always shows the plot (unless Stage is floated out).
            let stageDocked = appModel.workspace.showsInMainWindow(.stagePreview)
            let progDocked = appModel.workspace.showsInMainWindow(.programmer)
            let showPreview = stageDocked && (stageEditActive || appModel.workspace.showsDesignStagePreview)
            let previewH: CGFloat = {
                guard showPreview else { return 0 }
                // A floated Programmer relinquishes its complete docked region.
                if !progDocked { return totalH }
                let frac = stageEditActive
                    ? max(displayedDesignPreviewFraction, 0.55)
                    : displayedDesignPreviewFraction
                let minProg: CGFloat = stageEditActive ? 80 : 120
                return max(140, min(totalH * frac, totalH - minProg))
            }()
            let reservedTop = previewH + (previewH > 0 && progDocked ? 4 : 0)
            let progH = totalH - reservedTop

            VStack(spacing: 0) {
                if showPreview {
                    DesignStageSurface(showsUndockChrome: true)
                        .frame(height: previewH)
                        .clipped()
                    if progDocked {
                        designPreviewDivider(totalHeight: totalH)
                    }
                } else if stageDocked {
                    collapsedPreviewBar
                }
                if progDocked && stageEditActive && progH < 100 {
                    compactProgrammerStrip
                        .frame(height: max(72, progH))
                        .clipped()
                } else if progDocked {
                    programmerColumn
                        .frame(height: max(100, progH))
                        .clipped()
                }
            }
            .clipped()
        }
    }

    private var compactProgrammerStrip: some View {
        HStack(spacing: 12) {
            Text("PROGRAMMER")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text("\(appModel.session.selection.snapshot.fixtureIDs.count) selected · exit Edit Stage for full deck")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
            Spacer()
            Button("Done Editing") {
                appModel.workspace.exitEditStage()
                appModel.notifyUI()
            }
            .controlSize(.small)
            .buttonStyle(AuroraButtonStyle(kind: .primary))
            .tint(AuroraColor.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AuroraColor.surfaceHeader)
    }

    private var collapsedPreviewBar: some View {
        HStack(spacing: 10) {
            Text("STAGE PREVIEW HIDDEN")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Button("Show Preview") {
                appModel.workspace.setStagePreviewCollapsed(false)
                appModel.notifyUI()
            }
            .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AuroraColor.surfaceHeader)
    }

    private func designPreviewDivider(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(AuroraColor.separatorStrong)
            .frame(height: 4)
            .overlay {
                if liveDesignPreviewFraction != nil {
                    Rectangle()
                        .fill(AuroraColor.accentBright)
                        .frame(height: 2)
                        .shadow(color: AuroraColor.accent.opacity(0.65), radius: 3)
                }
            }
            .offset(y: CGFloat(
                (liveDesignPreviewFraction ?? layout.designPreviewFraction)
                    - layout.designPreviewFraction
            ) * totalHeight)
            .zIndex(liveDesignPreviewFraction == nil ? 0 : 100)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartDesignPreview == nil {
                            dragStartDesignPreview = displayedDesignPreviewFraction
                        }
                        let next = (dragStartDesignPreview ?? displayedDesignPreviewFraction)
                            + Double(value.translation.height / totalHeight)
                        liveDesignPreviewFraction = min(0.78, max(0.22, next))
                    }
                    .onEnded { _ in
                        let committed = liveDesignPreviewFraction ?? layout.designPreviewFraction
                        dragStartDesignPreview = nil
                        appModel.workspace.updateDesignPreviewFraction(committed, immediate: true)
                        liveDesignPreviewFraction = nil
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    // MARK: - PATCH (Library | Universe hero | Inspector) — full vertical height

    private func patchMainRow(totalW: CGFloat) -> some View {
        HStack(spacing: 0) {
            // PatchWorkspaceView already provides library + universe; host adds Inspector only.
            // No panel chrome title bar competing with the universe (content first).
            PatchWorkspaceView(
                context: appModel.panelContext,
                onChanged: {
                    appModel.engine.updateProject(appModel.session.project)
                    appModel.notifyUI()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuroraColor.surfacePanel)

            if showInspector {
                verticalDividerInspector(totalWidth: totalW)
                inspectorColumn
                    .frame(width: max(180, totalW * min(displayedTrailingFraction, 0.26)))
            }
        }
    }

    // MARK: - PROFILES (center owns profile editor)
    // Legacy StagePanel host removed (Post-C6): STAGE mode aliases to DESIGN + Edit Stage.

    private func profilesMainRow(totalW: CGFloat) -> some View {
        HStack(spacing: 0) {
            panelShell(title: "Fixture Profiles", trailing: { EmptyView() }) {
                FixtureProfileEditorPanel(
                    context: appModel.panelContext,
                    onChanged: {
                        appModel.engine.load(project: appModel.session.project)
                        appModel.notifyUI()
                    }
                )
            }
            .frame(maxWidth: .infinity)
            if showInspector {
                verticalDividerInspector(totalWidth: totalW)
                inspectorColumn
                    .frame(width: max(160, totalW * min(displayedTrailingFraction, 0.24)))
            }
        }
    }

    // MARK: Dividers

    private func verticalDivider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(AuroraColor.separatorStrong)
            .frame(width: 4)
            .overlay {
                if liveLeadingFraction != nil {
                    Rectangle()
                        .fill(AuroraColor.accentBright)
                        .frame(width: 2)
                        .shadow(color: AuroraColor.accent.opacity(0.65), radius: 3)
                }
            }
            .offset(x: CGFloat(
                (liveLeadingFraction ?? layout.leadingFraction) - layout.leadingFraction
            ) * totalWidth)
            .zIndex(liveLeadingFraction == nil ? 0 : 100)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartLeading == nil {
                            dragStartLeading = displayedLeadingFraction
                        }
                        let next = (dragStartLeading ?? displayedLeadingFraction)
                            + Double(value.translation.width / totalWidth)
                        let maximum = min(0.45, 0.85 - displayedTrailingFraction)
                        liveLeadingFraction = min(maximum, max(0.12, next))
                    }
                    .onEnded { _ in
                        let committed = liveLeadingFraction ?? layout.leadingFraction
                        dragStartLeading = nil
                        appModel.workspace.updateSplitFractions(leading: committed, immediate: true)
                        liveLeadingFraction = nil
                        appModel.notifyUI()
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func verticalDividerInspector(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(AuroraColor.separatorStrong)
            .frame(width: 4)
            .overlay {
                if liveTrailingFraction != nil {
                    Rectangle()
                        .fill(AuroraColor.accentBright)
                        .frame(width: 2)
                        .shadow(color: AuroraColor.accent.opacity(0.65), radius: 3)
                }
            }
            .offset(x: -CGFloat(
                (liveTrailingFraction ?? layout.trailingFraction) - layout.trailingFraction
            ) * totalWidth)
            .zIndex(liveTrailingFraction == nil ? 0 : 100)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartTrailing == nil {
                            dragStartTrailing = displayedTrailingFraction
                        }
                        let next = (dragStartTrailing ?? displayedTrailingFraction)
                            - Double(value.translation.width / totalWidth)
                        let maximum = min(0.45, 0.85 - displayedLeadingFraction)
                        liveTrailingFraction = min(maximum, max(0.12, next))
                    }
                    .onEnded { _ in
                        let committed = liveTrailingFraction ?? layout.trailingFraction
                        dragStartTrailing = nil
                        appModel.workspace.updateSplitFractions(trailing: committed, immediate: true)
                        liveTrailingFraction = nil
                        appModel.notifyUI()
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func horizontalDivider(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(AuroraColor.separatorStrong)
            .frame(height: 4)
            .overlay {
                if liveBottomFraction != nil {
                    Rectangle()
                        .fill(AuroraColor.accentBright)
                        .frame(height: 2)
                        .shadow(color: AuroraColor.accent.opacity(0.65), radius: 3)
                }
            }
            .offset(y: -CGFloat(
                (liveBottomFraction ?? layout.bottomFraction) - layout.bottomFraction
            ) * totalHeight)
            .zIndex(liveBottomFraction == nil ? 0 : 100)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartBottom == nil {
                            dragStartBottom = displayedBottomFraction
                        }
                        // Bottom shelf sits below the divider: drag up (negative height) must grow it.
                        let next = (dragStartBottom ?? displayedBottomFraction)
                            - Double(value.translation.height / totalHeight)
                        liveBottomFraction = min(0.5, max(0.15, next))
                    }
                    .onEnded { _ in
                        let committed = liveBottomFraction ?? layout.bottomFraction
                        dragStartBottom = nil
                        appModel.workspace.updateSplitFractions(bottom: committed, immediate: true)
                        liveBottomFraction = nil
                        appModel.notifyUI()
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    @ViewBuilder
    private func undockMenu(for surface: FloatSurfaceID) -> some View {
        if surface == .stagePreview {
            UndockSurfaceButton(surface: surface, showTitle: true)
                .buttonStyle(AuroraButtonStyle(kind: .secondary))
                .controlSize(.small)
        } else {
            UndockSurfaceButton(surface: surface, showTitle: false)
                .labelStyle(.iconOnly)
                .buttonStyle(AuroraButtonStyle(kind: .quiet))
                .controlSize(.small)
        }
    }

    // MARK: Center (Program)

    private var programmerColumn: some View {
        panelShell(title: "Programmer", trailing: {
            HStack(spacing: 8) {
                Text("\(appModel.session.selection.snapshot.fixtureIDs.count) selected")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.accentBright)
                if layout.stagePreviewCollapsed {
                    Text("preview hidden")
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                undockMenu(for: .programmer)
            }
        }) {
            ProgrammerPanel(
                context: appModel.panelContext,
                programmer: appModel.engine.programmer,
                project: appModel.session.project,
                presentation: appModel.programmerPresentation.presentation,
                presentationRevision: appModel.programmerPresentation.revision,
                resolvedLook: appModel.engine.currentResolvedSnapshot().programmerLook,
                onChanged: { appModel.noteProgrammerUIChanged() }
            )
        }
        .shortcutHelpHUD(.programmer, items: appModel.programmerShortcutHelpItems)
    }

    // MARK: Inspector

    private var inspectorColumn: some View {
        panelShell(title: "Inspector", trailing: {
            HStack(spacing: 8) {
                Text(focusLabel)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                undockMenu(for: .inspector)
            }
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
                onError: { _ in },
                documentEpoch: appModel.workspace.documentEpoch,
                documentGeneration: appModel.session.documentGeneration
            )
        }
        .shortcutHelpHUD(.inspector)
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

    // MARK: Lower

    private var collapsedLowerShelfStrip: some View {
        Button {
            appModel.workspace.setLowerShelfCollapsed(false)
            appModel.notifyUI()
        } label: {
            HStack(spacing: 10) {
                Text(appModel.workspace.lowerTool.rawValue.uppercased())
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.accentBright)
                Text("·  Palettes · Cues · Song · Diagnostics")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AuroraColor.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AuroraColor.surfaceHeader)
        .overlay(alignment: .top) {
            Rectangle().fill(AuroraColor.separator).frame(height: AuroraMetrics.hairline)
        }
        .help("Expand lower shelf")
    }

    // MARK: Chrome

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

extension View {
    /// Shared panel chrome for docked + floating workspace surfaces (C5.1).
    func panelChromeShell<Trailing: View>(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) -> some View {
        VStack(spacing: 0) {
            AuroraPanelHeader(title: title, trailing: trailing)
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
