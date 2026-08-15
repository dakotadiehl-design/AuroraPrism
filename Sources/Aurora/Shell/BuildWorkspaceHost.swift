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
    /// Shared Stage canvas camera (DESIGN + same model as STAGE tab).
    @State private var designPreviewScale: CGFloat = 1
    @State private var designPreviewPan: CGSize = .zero
    @State private var designCanvasSize: CGSize = .zero
    @State private var designStageRail: DesignStageRail = .unplaced
    @State private var designRotationDegrees: Double = 0
    @State private var designObjectRotationDegrees: Double = 0
    @State private var designObjectOpacity: Double = 0.9
    /// C4.3: live Rotation slider preview (radians by object id) — not document state.
    @State private var toolbarRotationPreview: [UUID: Double] = [:]
    @State private var rotationSliderEditing = false
    @State private var designStageStatus: String?
    @State private var designSelectedObjectIDs: Set<UUID> = []
    @State private var showStageObjectPalette = false

    private enum DesignStageRail: String, CaseIterable {
        case fixtures = "Fixtures"
        case unplaced = "Unplaced"
        case onStage = "On Stage"
        case objects = "Objects"
    }

    private var layout: WorkspaceLayout { appModel.workspace.layout }
    private var buildMode: BuildWorkspaceMode { appModel.workspace.buildWorkspaceMode }
    private var stageEditActive: Bool { appModel.workspace.stageEditActive }

    /// Mode bar highlight: STAGE alias while Edit Stage is active on DESIGN.
    private var modeBarSelection: BuildWorkspaceMode {
        if stageEditActive && buildMode == .program { return .stage }
        return buildMode
    }

    private var showInspector: Bool {
        layout.isVisible(.inspector)
    }

    /// Checkpoint A: lower Cue/Palette/Song only in Program (canvas modes need height).
    private var showLower: Bool {
        appModel.workspace.showsLowerRegionInCurrentBuildMode
            && (layout.isVisible(.cueList)
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
                        return max(120, totalH * layout.bottomFraction)
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

                    if showLower {
                        if lowerShelfExpanded {
                            horizontalDivider(totalHeight: totalH)
                            lowerRegion
                                .frame(height: bottomH)
                        } else {
                            collapsedLowerShelfStrip
                                .frame(height: collapsedShelfHeight)
                        }
                    }
                }
                .background(AuroraColor.surfaceWorkspace)
            }
        }
        .onChange(of: appModel.session.selection.snapshot.fixtureIDs) { _, ids in
            appModel.workspace.noteFixtureSelectionChanged(count: ids.count)
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
                designStageEditRail
                    .frame(width: max(168, totalW * min(layout.leadingFraction, 0.22)))
            } else {
                leftColumn(tools: BuildLeftTool.programTools, title: programLeftTitle)
                    .frame(width: max(160, totalW * layout.leadingFraction))
            }
            verticalDivider(totalWidth: totalW)
            designCenterColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showInspector {
                verticalDividerInspector(totalWidth: totalW)
                inspectorColumn
                    .frame(width: max(160, totalW * min(layout.trailingFraction, 0.24)))
            }
        }
    }

    private var designCenterColumn: some View {
        GeometryReader { geo in
            let totalH = max(geo.size.height, 1)
            // Edit Stage always shows the plot.
            let showPreview = stageEditActive || appModel.workspace.showsDesignStagePreview
            let previewH: CGFloat = {
                guard showPreview else { return 0 }
                let frac = stageEditActive
                    ? max(layout.designPreviewFraction, 0.55)
                    : layout.designPreviewFraction
                let minProg: CGFloat = stageEditActive ? 80 : 120
                return max(140, min(totalH * frac, totalH - minProg))
            }()
            let progH = totalH - previewH - (showPreview ? 4 : 0)

            VStack(spacing: 0) {
                if showPreview {
                    designStagePreviewRegion
                        .frame(height: previewH)
                    designPreviewDivider(totalHeight: totalH)
                } else {
                    collapsedPreviewBar
                }
                if stageEditActive && progH < 100 {
                    // Compact programmer strip while editing geometry
                    compactProgrammerStrip
                        .frame(height: max(72, progH))
                } else {
                    programmerColumn
                        .frame(height: max(100, progH))
                }
            }
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
            .buttonStyle(.borderedProminent)
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
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartDesignPreview == nil {
                            dragStartDesignPreview = layout.designPreviewFraction
                        }
                        let next = (dragStartDesignPreview ?? layout.designPreviewFraction)
                            + Double(value.translation.height / totalHeight)
                        appModel.workspace.updateDesignPreviewFraction(next)
                        appModel.notifyUI()
                    }
                    .onEnded { _ in
                        dragStartDesignPreview = nil
                        appModel.workspace.updateDesignPreviewFraction(
                            layout.designPreviewFraction,
                            immediate: true
                        )
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    /// Shared Stage surface — same StagePreviewSnapshot + StageLayout (C1–C3).
    private var designStagePreviewRegion: some View {
        VStack(spacing: 0) {
            designStageChrome
                .zIndex(2)
            if stageEditActive {
                // C4.2: tools bar is a sibling above the canvas (not overlaid) and keeps exclusive hit testing.
                designEditToolsBar
                    .fixedSize(horizontal: false, vertical: true)
                    .zIndex(3)
            }
            StageCanvasView(
                context: appModel.panelContext,
                preview: appModel.stagePreviewSnapshot(),
                interactionMode: stageEditActive ? .editGeometry : .programSelect,
                geometryEditingEnabled: stageEditActive,
                selectedIDs: appModel.session.selection.snapshot.fixtureIDs,
                selectedObjectIDs: $designSelectedObjectIDs,
                scale: $designPreviewScale,
                pan: $designPreviewPan,
                onSelectFixtures: { ids in
                    appModel.session.selectFixturesOrdered(ids, extending: false)
                    if !ids.isEmpty { designSelectedObjectIDs = [] }
                    appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                    appModel.notifyUI()
                },
                onLayoutChanged: {
                    appModel.engine.updateProject(appModel.session.project)
                    appModel.notifyUI()
                },
                revealFixtureID: appModel.workspace.stageRevealFixtureID,
                statusNote: $designStageStatus,
                toolbarRotationPreview: $toolbarRotationPreview
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .zIndex(0)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            designCanvasSize = geo.size
                            let cam = StageCanvasCamera.fitStage(
                                layout: appModel.session.project.stageLayout,
                                in: geo.size
                            )
                            if designPreviewScale < 0.15 {
                                designPreviewScale = cam.scale
                                designPreviewPan = cam.pan
                            }
                        }
                        .onChange(of: geo.size) { _, size in designCanvasSize = size }
                }
            )
            if let designStageStatus {
                Text(designStageStatus)
                    .font(.caption2)
                    .foregroundStyle(AuroraColor.accentBright)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(AuroraColor.surfaceHeader)
                    .zIndex(1)
            }
        }
        .background(AuroraColor.surfacePanel)
    }

    private var designStageChrome: some View {
        let snap = appModel.stagePreviewSnapshot()
        let selected = appModel.session.selection.snapshot.fixtureIDs
        return HStack(spacing: 8) {
            Text(stageEditActive ? "EDIT STAGE" : "STAGE PREVIEW")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(stageEditActive ? AuroraColor.warning : AuroraColor.textTertiary)
            Text(stageEditActive
                 ? "drag · marquee · place · Remove From Stage ≠ delete"
                 : "live · select · geometry locked")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
                .lineLimit(1)

            Menu("Fit") {
                Button("Fit Stage") {
                    let cam = StageCanvasCamera.fitStage(
                        layout: appModel.session.project.stageLayout,
                        in: designCanvasSize
                    )
                    designPreviewScale = cam.scale
                    designPreviewPan = cam.pan
                }
                Button("Fit Selection") {
                    if let cam = StageCanvasCamera.fitSelection(
                        placements: appModel.session.project.stageLayout.fixtures,
                        selectedIDs: selected,
                        in: designCanvasSize
                    ) {
                        designPreviewScale = cam.scale
                        designPreviewPan = cam.pan
                    }
                }
                .disabled(selected.isEmpty)
                Button("100%") { designPreviewScale = 1; designPreviewPan = .zero }
            }
            .controlSize(.small)

            HStack(spacing: 2) {
                Button {
                    designPreviewScale = max(0.2, designPreviewScale * 0.85)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .controlSize(.small)
                Text("\(Int(designPreviewScale * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AuroraColor.textTertiary)
                    .frame(width: 34)
                Button {
                    designPreviewScale = min(4, designPreviewScale * 1.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .controlSize(.small)
            }
            .buttonStyle(.borderless)

            if !selected.isEmpty {
                Button("Reveal") {
                    if let id = appModel.session.selection.snapshot.orderedFixtureIDs.first {
                        appModel.workspace.revealOnStage(fixtureID: id)
                        appModel.notifyUI()
                    }
                }
                .controlSize(.small)
            }

            Button {
                appModel.workspace.toggleEditStage()
                if stageEditActive {
                    designStageRail = .unplaced
                }
                appModel.notifyUI()
            } label: {
                Text(stageEditActive ? "Done" : "Edit Stage")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(stageEditActive ? AuroraColor.warning : AuroraColor.accent)
            .controlSize(.small)

            if stageEditActive {
                Menu("Align") {
                    Button("Left") { designAlign(.left) }
                    Button("Center X") { designAlign(.centerX) }
                    Button("Right") { designAlign(.right) }
                    Button("Top") { designAlign(.top) }
                    Button("Bottom") { designAlign(.bottom) }
                }
                .controlSize(.small)
                .disabled(selected.count < 2)

                Menu("Distribute") {
                    Button("Horizontally") { designDistribute(horizontal: true) }
                    Button("Vertically") { designDistribute(horizontal: false) }
                }
                .controlSize(.small)
                .disabled(selected.count < 3)

                Menu("Add") {
                    Button("Stage Area") { designAddShape(.stageArea) }
                    Button("Rectangle") { designAddShape(.rectangle) }
                    Button("Rounded Rect") { designAddShape(.roundedRectangle) }
                    Button("Ellipse") { designAddShape(.ellipse) }
                    Button("Line") { designAddShape(.line) }
                    Divider()
                    Button("Stage Objects…") {
                        designStageRail = .objects
                        showStageObjectPalette = true
                    }
                }
                .controlSize(.small)

                if !designSelectedObjectIDs.isEmpty {
                    Menu("Arrange") {
                        Button("Bring to Front") { designZOrder(.front) }
                        Button("Bring Forward") { designZOrder(.forward) }
                        Button("Send Backward") { designZOrder(.backward) }
                        Button("Send to Back") { designZOrder(.back) }
                    }
                    .controlSize(.small)
                    Button("Duplicate") { designDuplicateSelectedObjects() }
                        .controlSize(.small)
                    Button(designSelectedObjectsLocked ? "Unlock" : "Lock") {
                        designSetSelectedObjectsLocked(!designSelectedObjectsLocked)
                    }
                    .controlSize(.small)
                    Button("Delete Object", role: .destructive) { designDeleteSelectedObjects() }
                        .controlSize(.small)
                }

                if !selected.isEmpty {
                    Button("Remove From Stage", role: .destructive) {
                        designRemoveFromStage()
                    }
                    .controlSize(.small)
                }
            }

            if snap.freeze {
                Text("FROZEN").font(.caption2.weight(.bold)).foregroundStyle(.orange)
            }
            if snap.blackout {
                Text("BO").font(.caption2.weight(.bold)).foregroundStyle(.red)
            }

            Spacer(minLength: 4)

            if !stageEditActive {
                Button {
                    appModel.workspace.toggleStagePreviewCollapsed()
                    appModel.notifyUI()
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                }
                .controlSize(.small)
                .help("Hide Stage Preview")
            }

            Text("Master \(Int(snap.masterIntensity * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AuroraColor.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(stageEditActive ? AuroraColor.warning.opacity(0.12) : AuroraColor.surfaceHeader)
    }

    private var designEditToolsBar: some View {
        let selected = appModel.session.selection.snapshot.fixtureIDs
        // C4.2: toolbar must own pointer events — isolate from Stage canvas hit-testing.
        return Group {
            if !designSelectedObjectIDs.isEmpty {
                HStack(spacing: 10) {
                    Text("Object")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AuroraColor.textTertiary)
                    Text("Opacity")
                        .font(.caption2)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Slider(value: $designObjectOpacity, in: 0.1...1) { editing in
                        if !editing { designApplyObjectOpacity() }
                    }
                    .frame(maxWidth: 100)
                    .controlSize(.small)
                    Text("\(Int(designObjectOpacity * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AuroraColor.textTertiary)
                        .frame(width: 32)
                    Text("Rotation")
                        .font(.caption2)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Slider(value: $designObjectRotationDegrees, in: -180...180) { editing in
                        // C4.3: live preview while dragging; one document commit on release.
                        rotationSliderEditing = editing
                        if editing {
                            designPushRotationPreview()
                        } else {
                            designApplyObjectRotation()
                            toolbarRotationPreview = [:]
                        }
                    }
                    .frame(minWidth: 100, maxWidth: 160)
                    .frame(height: 22)
                    .controlSize(.small)
                    Text("\(Int(designObjectRotationDegrees))°")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AuroraColor.textTertiary)
                        .frame(width: 36)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(AuroraColor.surfaceHeader)
                .onChange(of: designSelectedObjectIDs) { _, _ in
                    designSyncObjectPropertyControls()
                    toolbarRotationPreview = [:]
                    rotationSliderEditing = false
                }
                .onChange(of: designObjectRotationDegrees) { _, _ in
                    if rotationSliderEditing {
                        designPushRotationPreview()
                    }
                }
            } else if !selected.isEmpty {
                HStack(spacing: 8) {
                    Text("Rotation")
                        .font(.caption2)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Slider(value: $designRotationDegrees, in: -180...180) { editing in
                        if !editing { designApplyRotation() }
                    }
                    .frame(minWidth: 120, maxWidth: 200)
                    .frame(height: 22)
                    .controlSize(.small)
                    Text("\(Int(designRotationDegrees))°")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AuroraColor.textTertiary)
                        .frame(width: 36)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(AuroraColor.surfaceHeader)
            }
        }
        .zIndex(50)
        .allowsHitTesting(true)
    }

    private var designSelectedObjectsLocked: Bool {
        let layout = appModel.session.project.stageLayout
        let objs = layout.objects.filter { designSelectedObjectIDs.contains($0.id) }
        return !objs.isEmpty && objs.allSatisfy(\.locked)
    }

    private func designSyncObjectPropertyControls() {
        let layout = appModel.session.project.stageLayout
        let objs = layout.objects.filter { designSelectedObjectIDs.contains($0.id) }
        guard let first = objs.first else { return }
        designObjectOpacity = first.opacity
        designObjectRotationDegrees = first.rotation * 180 / .pi
    }

    // MARK: - Edit Stage rail (Unplaced / On Stage / Fixtures)

    private var designStageEditRail: some View {
        let layout = appModel.session.project.stageLayout
        let placed = Set(layout.fixtures.map(\.fixtureID))
        let unplaced = appModel.session.project.fixtures.filter { !placed.contains($0.id) }
        let onStage = appModel.session.project.fixtures.filter { placed.contains($0.id) }

        return VStack(spacing: 0) {
            Picker("", selection: $designStageRail) {
                ForEach(DesignStageRail.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)

            if designStageRail == .unplaced {
                HStack {
                    Text("\(unplaced.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Place All") { designPlaceAllUnplaced() }
                        .controlSize(.mini)
                        .disabled(unplaced.isEmpty)
                }
                .padding(.horizontal, 8)
            }

            if designStageRail == .objects {
                StageObjectPaletteView(
                    onPlaceStock: { asset in designPlaceStock(asset) },
                    onPlaceShape: { kind in designAddShape(kind) },
                    onImportImage: { designImportImage() }
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    switch designStageRail {
                    case .fixtures:
                        ForEach(appModel.session.project.fixtures.sorted {
                            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        }) { fx in
                            designRailRow(fx, badge: placed.contains(fx.id) ? nil : "unplaced")
                        }
                    case .unplaced:
                        if unplaced.isEmpty {
                            Text("All fixtures placed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(unplaced) { fx in
                                designRailRow(fx, badge: nil)
                                    .onDrag {
                                        NSItemProvider(object: fx.id.uuidString as NSString)
                                    }
                            }
                        }
                    case .onStage:
                        ForEach(onStage) { fx in
                            designRailRow(fx, badge: nil)
                        }
                    case .objects:
                        EmptyView()
                    }
                }
                .listStyle(.sidebar)
            }

            Button("Exit Edit Stage") {
                appModel.workspace.exitEditStage()
                appModel.notifyUI()
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(8)
        }
        .background(AuroraColor.surfacePanel)
        .panelChromeShell(title: "Stage Edit")
    }

    private func designRailRow(_ fx: PatchedFixture, badge: String?) -> some View {
        HStack {
            Text(fx.name)
                .font(.callout)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .foregroundStyle(AuroraColor.warning)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appModel.session.selectFixturesOrdered([fx.id], extending: false)
            appModel.workspace.noteExplicitFixtureInspect(count: 1)
            appModel.notifyUI()
        }
    }

    // MARK: - Design Stage geometry ops (same commands as StagePanel)

    private enum DesignAlignEdge { case left, right, top, bottom, centerX }

    private func designCommitLayout(_ stageLayout: StageLayout) {
        do {
            try appModel.session.perform(UpdateStageLayoutCommand(layout: stageLayout))
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            designStageStatus = error.localizedDescription
        }
    }

    private func designAlign(_ edge: DesignAlignEdge) {
        let selected = appModel.session.selection.snapshot.fixtureIDs
        guard selected.count >= 2 else { return }
        var layout = appModel.session.project.stageLayout
        let places = layout.fixtures.filter { selected.contains($0.fixtureID) && !$0.locked }
        guard !places.isEmpty else { return }
        switch edge {
        case .left:
            let v = places.map(\.x).min() ?? 0
            for i in layout.fixtures.indices where selected.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].x = v
            }
        case .right:
            let v = places.map(\.x).max() ?? 0
            for i in layout.fixtures.indices where selected.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].x = v
            }
        case .top:
            let v = places.map(\.y).min() ?? 0
            for i in layout.fixtures.indices where selected.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].y = v
            }
        case .bottom:
            let v = places.map(\.y).max() ?? 0
            for i in layout.fixtures.indices where selected.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].y = v
            }
        case .centerX:
            let v = places.map(\.x).reduce(0, +) / Double(places.count)
            for i in layout.fixtures.indices where selected.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].x = v
            }
        }
        designCommitLayout(layout)
        designStageStatus = "Aligned"
    }

    private func designDistribute(horizontal: Bool) {
        let selected = appModel.session.selection.snapshot.fixtureIDs
        guard selected.count >= 3 else { return }
        var layout = appModel.session.project.stageLayout
        var places = layout.fixtures.filter { selected.contains($0.fixtureID) && !$0.locked }
        if horizontal {
            places.sort { $0.x < $1.x }
            guard let first = places.first, let last = places.last, places.count > 2 else { return }
            let step = (last.x - first.x) / Double(places.count - 1)
            for (idx, p) in places.enumerated() {
                if let i = layout.fixtures.firstIndex(where: { $0.fixtureID == p.fixtureID }) {
                    layout.fixtures[i].x = first.x + step * Double(idx)
                }
            }
        } else {
            places.sort { $0.y < $1.y }
            guard let first = places.first, let last = places.last, places.count > 2 else { return }
            let step = (last.y - first.y) / Double(places.count - 1)
            for (idx, p) in places.enumerated() {
                if let i = layout.fixtures.firstIndex(where: { $0.fixtureID == p.fixtureID }) {
                    layout.fixtures[i].y = first.y + step * Double(idx)
                }
            }
        }
        designCommitLayout(layout)
        designStageStatus = "Distributed"
    }

    private func designApplyRotation() {
        let selected = appModel.session.selection.snapshot.fixtureIDs
        guard !selected.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        let rad = designRotationDegrees * .pi / 180
        for i in layout.fixtures.indices where selected.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
            layout.fixtures[i].rotation = rad
        }
        designCommitLayout(layout)
    }

    private func designRemoveFromStage() {
        let ids = Array(appModel.session.selection.snapshot.fixtureIDs)
        guard !ids.isEmpty else { return }
        do {
            try appModel.session.perform(RemoveFromStageCommand(fixtureIDs: ids))
            designStageStatus = "Removed from Stage (still patched)"
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            designStageStatus = error.localizedDescription
        }
    }

    private func designPlaceAllUnplaced() {
        do {
            try appModel.session.perform(PlaceAllUnplacedCommand())
            designStageStatus = "Placed all unplaced"
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            designStageStatus = error.localizedDescription
        }
    }

    private func designAddShape(_ kind: StageScenicKind) {
        var layout = appModel.session.project.stageLayout
        let cx = layout.canvasWidth / 2
        let cy = layout.canvasHeight / 2
        let obj: StageLayoutObject
        switch kind {
        case .stageArea:
            obj = .shape(.stageArea, name: "Stage", x: cx, y: cy * 1.2, width: 480, height: 160, zIndex: layout.nextZIndex)
        case .truss, .line:
            obj = .shape(kind, name: kind.rawValue, x: cx, y: cy * 0.5, width: 320, height: 12, zIndex: layout.nextZIndex)
        case .label:
            obj = StageLayoutObject(
                kind: .text, shapeKind: .label, name: "Label",
                x: cx, y: cy, width: 120, height: 36, zIndex: layout.nextZIndex,
                text: "Label"
            )
        default:
            obj = .shape(kind, name: kind.rawValue, x: cx, y: cy, width: 120, height: 80, zIndex: layout.nextZIndex)
        }
        layout.appendObject(obj)
        designCommitLayout(layout)
        designSelectedObjectIDs = [obj.id]
        designObjectOpacity = obj.opacity
        designObjectRotationDegrees = 0
        designStageStatus = "Added \(obj.name)"
    }

    private func designPlaceStock(_ asset: StageStockAsset) {
        var layout = appModel.session.project.stageLayout
        let size = asset.defaultSize
        let obj = StageLayoutObject.stock(
            assetKey: asset.key,
            name: asset.displayName,
            x: layout.canvasWidth / 2,
            y: layout.canvasHeight / 2,
            width: size.width,
            height: size.height,
            opacity: asset.defaultOpacity,
            zIndex: layout.nextZIndex
        )
        layout.appendObject(obj)
        designCommitLayout(layout)
        designSelectedObjectIDs = [obj.id]
        designObjectOpacity = asset.defaultOpacity
        designObjectRotationDegrees = 0
        designStageStatus = "Placed \(asset.displayName)"
    }

    private func designImportImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // C4.5: package-relative media/stage/… (+ staging until first save).
            let imported = try StageMediaSupport.importImage(
                from: url,
                intoOpenPackage: appModel.documentURL
            )
            let asset = MediaAssetRef(
                name: url.deletingPathExtension().lastPathComponent,
                relativePath: imported.relativePath,
                notes: "Stage imported image"
            )
            try appModel.session.perform(RegisterMediaAssetCommand(asset: asset))
            var layout = appModel.session.project.stageLayout
            let obj = StageLayoutObject(
                kind: .importedImage,
                mediaRef: imported.relativePath,
                name: asset.name,
                x: layout.canvasWidth / 2,
                y: layout.canvasHeight / 2,
                width: 160,
                height: 120,
                zIndex: layout.nextZIndex,
                opacity: 0.95
            )
            layout.appendObject(obj)
            try appModel.session.perform(UpdateStageLayoutCommand(layout: layout))
            designSelectedObjectIDs = [obj.id]
            designObjectOpacity = 0.95
            designObjectRotationDegrees = 0
            designStageStatus = appModel.documentURL == nil
                ? "Imported image (staged until Save)"
                : "Imported image (project media)"
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            designStageStatus = error.localizedDescription
        }
    }

    private enum DesignZOp { case front, back, forward, backward }

    private func designZOrder(_ op: DesignZOp) {
        let ids = designSelectedObjectIDs
        guard !ids.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        switch op {
        case .front:
            let maxZ = (layout.objects.map(\.zIndex).max() ?? 0) + 1
            for i in layout.objects.indices where ids.contains(layout.objects[i].id) {
                layout.objects[i].zIndex = maxZ
            }
        case .back:
            let minZ = (layout.objects.map(\.zIndex).min() ?? 0) - 1
            for i in layout.objects.indices where ids.contains(layout.objects[i].id) {
                layout.objects[i].zIndex = minZ
            }
        case .forward:
            for i in layout.objects.indices where ids.contains(layout.objects[i].id) {
                layout.objects[i].zIndex += 1
            }
        case .backward:
            for i in layout.objects.indices where ids.contains(layout.objects[i].id) {
                layout.objects[i].zIndex -= 1
            }
        }
        designCommitLayout(layout)
        designStageStatus = "Z-order updated"
    }

    private func designDeleteSelectedObjects() {
        let ids = designSelectedObjectIDs
        guard !ids.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        layout.objects.removeAll { ids.contains($0.id) }
        designSelectedObjectIDs = []
        designCommitLayout(layout)
        designStageStatus = "Deleted object(s)"
    }

    private func designDuplicateSelectedObjects() {
        let ids = Array(designSelectedObjectIDs)
        guard !ids.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        var newIDs: Set<UUID> = []
        let offset: Double = 24
        for id in ids {
            guard let src = layout.objects.first(where: { $0.id == id }) else { continue }
            var copy = src
            copy.id = UUID()
            copy.x += offset
            copy.y += offset
            copy.zIndex = layout.nextZIndex
            copy.locked = false
            layout.appendObject(copy)
            newIDs.insert(copy.id)
        }
        guard !newIDs.isEmpty else { return }
        designCommitLayout(layout)
        designSelectedObjectIDs = newIDs
        designStageStatus = newIDs.count == 1 ? "Duplicated object" : "Duplicated \(newIDs.count) objects"
    }

    private func designSetSelectedObjectsLocked(_ locked: Bool) {
        let ids = designSelectedObjectIDs
        guard !ids.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        for i in layout.objects.indices where ids.contains(layout.objects[i].id) {
            layout.objects[i].locked = locked
        }
        designCommitLayout(layout)
        designStageStatus = locked ? "Locked" : "Unlocked"
    }

    private func designApplyObjectOpacity() {
        let ids = designSelectedObjectIDs
        guard !ids.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        for i in layout.objects.indices where ids.contains(layout.objects[i].id) && !layout.objects[i].locked {
            layout.objects[i].opacity = designObjectOpacity
        }
        designCommitLayout(layout)
        designStageStatus = "Opacity updated"
    }

    private func designPushRotationPreview() {
        let rad = designObjectRotationDegrees * .pi / 180
        var map: [UUID: Double] = [:]
        for id in designSelectedObjectIDs {
            map[id] = rad
        }
        toolbarRotationPreview = map
    }

    private func designApplyObjectRotation() {
        let ids = designSelectedObjectIDs
        guard !ids.isEmpty else { return }
        var layout = appModel.session.project.stageLayout
        let rad = designObjectRotationDegrees * .pi / 180
        for i in layout.objects.indices where ids.contains(layout.objects[i].id) && !layout.objects[i].locked {
            layout.objects[i].rotation = rad
        }
        designCommitLayout(layout)
        toolbarRotationPreview = [:]
        designStageStatus = "Object rotation updated"
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
                    .frame(width: max(180, totalW * min(layout.trailingFraction, 0.26)))
            }
        }
    }

    // MARK: - STAGE (tray inside StagePanel | canvas hero | Inspector) — no double left rail

    private func stageMainRow(totalW: CGFloat) -> some View {
        let trail = showInspector ? max(180, totalW * min(layout.trailingFraction, 0.24)) : 0
        return HStack(spacing: 0) {
            // StagePanel owns Unplaced/On Stage rail + canvas — do not stack Browser left.
            StagePanel(
                context: appModel.panelContext,
                preview: appModel.stagePreviewSnapshot(),
                onLayoutChanged: {
                    appModel.engine.updateProject(appModel.session.project)
                    appModel.notifyUI()
                },
                onSelectFixtures: { ids in
                    appModel.session.selectFixturesOrdered(ids, extending: false)
                    appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                    appModel.notifyUI()
                },
                revealFixtureID: appModel.workspace.stageRevealFixtureID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuroraColor.surfacePanel)

            if showInspector {
                verticalDividerInspector(totalWidth: totalW)
                inspectorColumn
                    .frame(width: trail)
            }
        }
    }

    // MARK: - PROFILES (center owns profile editor)

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
                    .frame(width: max(160, totalW * min(layout.trailingFraction, 0.24)))
            }
        }
    }

    // MARK: Dividers

    private func verticalDivider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(AuroraColor.separatorStrong)
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartLeading == nil {
                            dragStartLeading = layout.leadingFraction
                        }
                        let next = (dragStartLeading ?? layout.leadingFraction) + Double(value.translation.width / totalWidth)
                        appModel.workspace.updateSplitFractions(leading: next)
                        appModel.notifyUI()
                    }
                    .onEnded { _ in
                        dragStartLeading = nil
                        appModel.workspace.updateSplitFractions(leading: layout.leadingFraction, immediate: true)
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
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartTrailing == nil {
                            dragStartTrailing = layout.trailingFraction
                        }
                        let next = (dragStartTrailing ?? layout.trailingFraction) - Double(value.translation.width / totalWidth)
                        appModel.workspace.updateSplitFractions(trailing: next)
                        appModel.notifyUI()
                    }
                    .onEnded { _ in
                        dragStartTrailing = nil
                        appModel.workspace.updateSplitFractions(trailing: layout.trailingFraction, immediate: true)
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
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartBottom == nil {
                            dragStartBottom = layout.bottomFraction
                        }
                        let next = (dragStartBottom ?? layout.bottomFraction) + Double(value.translation.height / totalHeight)
                        appModel.workspace.updateSplitFractions(bottom: next)
                        appModel.notifyUI()
                    }
                    .onEnded { _ in
                        dragStartBottom = nil
                        appModel.workspace.updateSplitFractions(bottom: layout.bottomFraction, immediate: true)
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    // MARK: Left rails

    private func leftColumn(tools: [BuildLeftTool], title: String) -> some View {
        VStack(spacing: 0) {
            toolTabBar(
                titles: tools.map(\.rawValue),
                selection: Binding(
                    get: {
                        if tools.contains(appModel.workspace.leftTool) {
                            return appModel.workspace.leftTool.rawValue
                        }
                        return tools.first?.rawValue ?? BuildLeftTool.browser.rawValue
                    },
                    set: { raw in
                        if let t = BuildLeftTool(rawValue: raw), tools.contains(t) {
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
        .panelChromeShell(title: title)
    }

    private var programLeftTitle: String {
        switch appModel.workspace.leftTool {
        case .browser: return "Fixtures"
        case .groups: return "Groups"
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
            }
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

    // MARK: Inspector

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

    private var lowerRegion: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
                Spacer(minLength: 8)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .panelChromeShell(title: appModel.workspace.lowerTool.rawValue)
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

    // MARK: Chrome

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
