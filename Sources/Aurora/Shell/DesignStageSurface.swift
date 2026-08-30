import AuroraDesignSystem
import AppKit
import AuroraCore
import AuroraDiagnostics
import AuroraModel
import AuroraUI
import SwiftUI

extension Notification.Name {
    static let auroraOpenStageObjectsRail = Notification.Name("aurora.openStageObjectsRail")
}

// MARK: - Production DESIGN Stage surface (C5.1)
/// Same Stage chrome + `StageCanvasView` for docked DESIGN and floating Stage Preview.
/// Camera (`designPreviewScale` / `designPreviewPan`) is shared on `WorkspaceController`.

struct DesignStageSurface: View {
    @EnvironmentObject private var appModel: AppModel
    /// Docked host shows Undock; floating host has outer Dock chrome instead.
    var showsUndockChrome: Bool = true

    @State private var designCanvasSize: CGSize = .zero
    @State private var designRotationDegrees: Double = 0
    @State private var designObjectRotationDegrees: Double = 0
    @State private var designObjectOpacity: Double = 0.9
    @State private var toolbarRotationPreview: [UUID: Double] = [:]
    @State private var rotationSliderEditing = false
    @State private var designStageStatus: String?
    @State private var designSelectedObjectIDs: Set<UUID> = []

    private var scaleBinding: Binding<CGFloat> {
        Binding(
            get: { appModel.workspace.designPreviewScale },
            set: {
                appModel.workspace.designPreviewScale = $0
                appModel.workspace.objectWillChange.send()
            }
        )
    }

    private var panBinding: Binding<CGSize> {
        Binding(
            get: { appModel.workspace.designPreviewPan },
            set: {
                appModel.workspace.designPreviewPan = $0
                appModel.workspace.objectWillChange.send()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            designStageChrome
                .zIndex(2)
            if appModel.workspace.stageEditActive {
                // C4.2: tools bar is a sibling above the canvas (not overlaid) and keeps exclusive hit testing.
                designEditToolsBar
                    .fixedSize(horizontal: false, vertical: true)
                    .zIndex(3)
            }
            StageCanvasView(
                context: appModel.panelContext,
                preview: appModel.stagePreviewSnapshot(),
                interactionMode: appModel.workspace.stageEditActive ? .editGeometry : .programSelect,
                geometryEditingEnabled: appModel.workspace.stageEditActive,
                selectedIDs: appModel.session.selection.snapshot.fixtureIDs,
                selectedTargets: appModel.session.selection.snapshot.fixtureTargets,
                orderedSelectedTargets: appModel.session.selection.snapshot.orderedFixtureTargets,
                glyphStyle: appModel.settings.stageGlyphStyle,
                selectedObjectIDs: $designSelectedObjectIDs,
                scale: scaleBinding,
                pan: panBinding,
                onSelectFixtures: { ids in
                    appModel.session.selectFixturesOrdered(ids, extending: false)
                    if !ids.isEmpty { designSelectedObjectIDs = [] }
                    appModel.workspace.noteExplicitFixtureInspect(count: ids.count)
                    appModel.notifyUI()
                },
                onSelectFixtureTargets: { targets in
                    appModel.session.selectFixtureTargetsOrdered(targets, extending: false)
                    if !targets.isEmpty { designSelectedObjectIDs = [] }
                    appModel.workspace.noteExplicitFixtureInspect(count: Set(targets.map(\.fixtureID)).count)
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
                            if appModel.workspace.designPreviewScale < 0.15 {
                                appModel.workspace.designPreviewScale = cam.scale
                                appModel.workspace.designPreviewPan = cam.pan
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
        .shortcutHelpHUD(.stage)
    }

    private var designStageChrome: some View {
        let snap = appModel.stagePreviewSnapshot()
        let selected = appModel.session.selection.snapshot.fixtureIDs
        return HStack(spacing: 8) {
            Text(appModel.workspace.stageEditActive ? "EDIT STAGE" : "STAGE PREVIEW")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(appModel.workspace.stageEditActive ? AuroraColor.warning : AuroraColor.textTertiary)
            Text(appModel.workspace.stageEditActive
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
                    appModel.workspace.designPreviewScale = cam.scale
                    appModel.workspace.designPreviewPan = cam.pan
                }
                Button("Fit Selection") {
                    if let cam = StageCanvasCamera.fitSelection(
                        placements: appModel.session.project.stageLayout.fixtures,
                        selectedIDs: selected,
                        in: designCanvasSize
                    ) {
                        appModel.workspace.designPreviewScale = cam.scale
                        appModel.workspace.designPreviewPan = cam.pan
                    }
                }
                .disabled(selected.isEmpty)
                Button("100%") { appModel.workspace.designPreviewScale = 1; appModel.workspace.designPreviewPan = .zero }
            }
            .controlSize(.small)

            if showsUndockChrome {
                UndockSurfaceButton(surface: .stagePreview, showTitle: true)
                    .buttonStyle(AuroraButtonStyle(kind: .secondary))
                    .controlSize(.small)
                    .disabled(appModel.workspace.isFloating(.stagePreview))
            }

            HStack(spacing: 2) {
                Button {
                    appModel.workspace.designPreviewScale = max(0.2, appModel.workspace.designPreviewScale * 0.85)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .controlSize(.small)
                Text("\(Int(appModel.workspace.designPreviewScale * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AuroraColor.textTertiary)
                    .frame(width: 34)
                Button {
                    appModel.workspace.designPreviewScale = min(4, appModel.workspace.designPreviewScale * 1.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .controlSize(.small)
            }
            .buttonStyle(AuroraButtonStyle(kind: .quiet))

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
                if appModel.workspace.stageEditActive {
                    NotificationCenter.default.post(name: .auroraOpenStageObjectsRail, object: "unplaced")
                }
                appModel.notifyUI()
            } label: {
                Text(appModel.workspace.stageEditActive ? "Done" : "Edit Stage")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(AuroraButtonStyle(kind: .primary))
            .tint(appModel.workspace.stageEditActive ? AuroraColor.warning : AuroraColor.accent)
            .controlSize(.small)

            if appModel.workspace.stageEditActive {
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
                        // Edit rail lives in main DESIGN host; palette is available there.
                        NotificationCenter.default.post(name: .auroraOpenStageObjectsRail, object: nil)
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

            if !appModel.workspace.stageEditActive {
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
        .background(appModel.workspace.stageEditActive ? AuroraColor.warning.opacity(0.12) : AuroraColor.surfaceHeader)
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

    // MARK: - Design Stage geometry ops (same commands as StagePanel)

    private enum DesignAlignEdge { case left, right, top, bottom, centerX }

    private func designCommitLayout(_ stageLayout: StageLayout) {
        do {
            try appModel.session.perform(UpdateStageLayoutCommand(layout: stageLayout))
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            designStageStatus = PrismErrorReporting.statusMessage(for: error, operation: "edit")
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
            designStageStatus = PrismErrorReporting.statusMessage(for: error, operation: "edit")
        }
    }

    private func designPlaceAllUnplaced() {
        do {
            try appModel.session.perform(PlaceAllUnplacedCommand())
            designStageStatus = "Placed all unplaced"
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            designStageStatus = PrismErrorReporting.statusMessage(for: error, operation: "edit")
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
            designStageStatus = PrismErrorReporting.statusMessage(for: error, operation: "edit")
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
}

// MARK: - Edit Stage left rail (docked DESIGN only; not part of Stage float surface)

struct DesignStageEditRail: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var rail: DesignStageRailTab
    var onStatus: (String?) -> Void = { _ in }

    var body: some View {
        let layout = appModel.session.project.stageLayout
        let placed = Set(layout.fixtures.map(\.fixtureID))
        let unplaced = appModel.session.project.fixtures.filter { !placed.contains($0.id) }
        let onStage = appModel.session.project.fixtures.filter { placed.contains($0.id) }

        return VStack(spacing: 0) {
            Picker("", selection: $rail) {
                ForEach(DesignStageRailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)

            if rail == .unplaced {
                HStack {
                    Text("\(unplaced.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Place All") { placeAllUnplaced() }
                        .controlSize(.mini)
                        .disabled(unplaced.isEmpty)
                }
                .padding(.horizontal, 8)
            }

            if rail == .objects {
                StageObjectPaletteView(
                    onPlaceStock: { asset in placeStock(asset) },
                    onPlaceShape: { kind in addShape(kind) },
                    onImportImage: { importImage() }
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    switch rail {
                    case .fixtures:
                        ForEach(appModel.session.project.fixtures.sorted {
                            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        }) { fx in
                            railRow(fx, badge: placed.contains(fx.id) ? nil : "unplaced")
                        }
                    case .unplaced:
                        if unplaced.isEmpty {
                            Text("All fixtures placed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(unplaced) { fx in
                                railRow(fx, badge: nil)
                                    .onDrag {
                                        NSItemProvider(object: fx.id.uuidString as NSString)
                                    }
                            }
                        }
                    case .onStage:
                        ForEach(onStage) { fx in
                            railRow(fx, badge: nil)
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

    private func railRow(_ fx: PatchedFixture, badge: String?) -> some View {
        HStack {
            Text(fx.name).font(.callout)
            Spacer()
            if let badge {
                Text(badge).font(.caption2).foregroundStyle(AuroraColor.warning)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appModel.session.selectFixturesOrdered([fx.id], extending: false)
            appModel.workspace.noteExplicitFixtureInspect(count: 1)
            appModel.notifyUI()
        }
    }

    private func commit(_ stageLayout: StageLayout, status: String? = nil) {
        do {
            try appModel.session.perform(UpdateStageLayoutCommand(layout: stageLayout))
            appModel.engine.updateProject(appModel.session.project)
            onStatus(status)
            appModel.notifyUI()
        } catch {
            onStatus(PrismErrorReporting.statusMessage(for: error, operation: "edit"))
        }
    }

    private func placeAllUnplaced() {
        do {
            try appModel.session.perform(PlaceAllUnplacedCommand())
            onStatus("Placed all unplaced")
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            onStatus(PrismErrorReporting.statusMessage(for: error, operation: "edit"))
        }
    }

    private func addShape(_ kind: StageScenicKind) {
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
        commit(layout, status: "Added \(obj.name)")
    }

    private func placeStock(_ asset: StageStockAsset) {
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
        commit(layout, status: "Placed \(asset.displayName)")
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
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
            onStatus(appModel.documentURL == nil
                ? "Imported image (staged until Save)"
                : "Imported image (project media)")
            appModel.engine.updateProject(appModel.session.project)
            appModel.notifyUI()
        } catch {
            onStatus(PrismErrorReporting.statusMessage(for: error, operation: "edit"))
        }
    }
}

enum DesignStageRailTab: String, CaseIterable {
    case fixtures = "Fixtures"
    case unplaced = "Unplaced"
    case onStage = "On Stage"
    case objects = "Objects"
}
