import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Reusable Stage visualization surface (C1–C3.1).
///
/// Camera pan, live fixture drag (transient), and geometry commit are separated:
/// - document: `project.stageLayout`
/// - camera: `pan` / `scale` bindings
/// - interaction: pan origin, Space pan, fixture drag state
public struct StageCanvasView: View {
    public var context: WorkspacePanelContext
    public var preview: StagePreviewSnapshot
    public var interactionMode: StageInteractionMode
    public var geometryEditingEnabled: Bool
    public var selectedIDs: Set<UUID>
    /// Selected layout object IDs (stock/scenic/import) — C4.
    @Binding public var selectedObjectIDs: Set<UUID>
    public var onSelectFixtures: ([UUID]) -> Void
    public var onLayoutChanged: () -> Void
    public var revealFixtureID: UUID?
    public var statusNote: Binding<String?>?
    /// C4.3: toolbar Rotation slider live preview (radians by layout object id). Not document state.
    public var toolbarRotationPreview: Binding<[UUID: Double]>

    @Binding public var scale: CGFloat
    @Binding public var pan: CGSize

    @State private var canvasSize: CGSize = .zero
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var panAtDragStart: CGSize?
    @State private var isPanning = false
    @State private var fixtureDrag: StageFixtureDragState?
    @State private var objectResize: StageObjectResizeState?
    @State private var objectRotate: StageObjectRotateState?
    @State private var fixtureAim: StageFixtureAimState?
    /// C4.2: exclusive owner of the current pointer drag.
    @State private var activeTransform: StageTransformInteraction = .none
    @ObservedObject private var keys = StageCanvasKeyState.shared

    public init(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        interactionMode: StageInteractionMode = .programSelect,
        geometryEditingEnabled: Bool = false,
        selectedIDs: Set<UUID>,
        selectedObjectIDs: Binding<Set<UUID>> = .constant([]),
        scale: Binding<CGFloat>,
        pan: Binding<CGSize>,
        onSelectFixtures: @escaping ([UUID]) -> Void,
        onLayoutChanged: @escaping () -> Void = {},
        revealFixtureID: UUID? = nil,
        statusNote: Binding<String?>? = nil,
        toolbarRotationPreview: Binding<[UUID: Double]> = .constant([:])
    ) {
        self.context = context
        self.preview = preview
        self.interactionMode = interactionMode
        self.geometryEditingEnabled = geometryEditingEnabled
        self.selectedIDs = selectedIDs
        self._selectedObjectIDs = selectedObjectIDs
        self._scale = scale
        self._pan = pan
        self.onSelectFixtures = onSelectFixtures
        self.onLayoutChanged = onLayoutChanged
        self.revealFixtureID = revealFixtureID
        self.statusNote = statusNote
        self.toolbarRotationPreview = toolbarRotationPreview
    }

    private var layout: StageLayout { context.project.stageLayout }

    private var canEditGeometry: Bool {
        geometryEditingEnabled && interactionMode == .editGeometry
    }

    private var spaceHeld: Bool { keys.spaceHeld }

    /// Space-pan wins over marquee/fixture geometry.
    private var shouldCameraPan: Bool {
        if spaceHeld { return true }
        switch interactionMode {
        case .panOnly, .programSelect: return true
        case .editGeometry: return false
        }
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer
                canvasContent
                    .scaleEffect(scale)
                    .offset(pan)
                    .gesture(canvasGesture)
            }
            .clipShape(Rectangle())
            .background(AuroraColor.surfaceWorkspace)
            .onAppear {
                canvasSize = geo.size
                if scale <= 0.01 { fitStage(in: geo.size) }
                StageCanvasKeyState.shared.retain()
            }
            .onDisappear {
                StageCanvasKeyState.shared.setPointerInsideStage(false)
                StageCanvasKeyState.shared.release()
                clearTransientInteraction()
            }
            .onHover { inside in
                StageCanvasKeyState.shared.setPointerInsideStage(inside)
            }
            .onChange(of: geo.size) { _, size in canvasSize = size }
            .onChange(of: revealFixtureID) { _, id in
                if let id { reveal(fixtureID: id) }
            }
            .onChange(of: geometryEditingEnabled) { _, enabled in
                if !enabled { clearTransientInteraction() }
            }
            .onChange(of: interactionMode) { _, _ in
                clearTransientInteraction()
            }
            .onChange(of: keys.escapeTick) { _, _ in
                if fixtureDrag != nil || objectResize != nil || objectRotate != nil || fixtureAim != nil {
                    fixtureDrag = nil
                    objectResize = nil
                    objectRotate = nil
                    fixtureAim = nil
                    activeTransform = .none
                    statusNote?.wrappedValue = "Transform cancelled"
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        (preview.blackout
            ? Color.black
            : Color(
                red: preview.dominantColor.r,
                green: preview.dominantColor.g,
                blue: preview.dominantColor.b
            )
        )
        .opacity(preview.blackout ? 1 : 0.18)
        .animation(.easeInOut(duration: 0.25), value: preview.dominantColor)
    }

    // MARK: - Transient target sets (C4.3 single-render)

    /// Layout objects currently owned by a live transform — omitted from committed layer.
    private var transientLayoutObjectIDs: Set<UUID> {
        var moveIDs = Set<UUID>()
        if let drag = fixtureDrag {
            for id in drag.originalPositions.keys where layout.object(id: id) != nil {
                moveIDs.insert(id)
            }
        }
        return StageEditTransientTargets.layoutObjectIDs(
            activeTransform: activeTransform,
            moveDragIDs: moveIDs,
            resizeObjectID: objectResize?.objectID,
            rotateObjectID: objectRotate?.objectID,
            toolbarRotationPreviewIDs: Set(toolbarRotationPreview.wrappedValue.keys)
        )
    }

    private var transientFixtureIDs: Set<UUID> {
        var moveIDs = Set<UUID>()
        if let drag = fixtureDrag {
            for id in drag.originalPositions.keys where layout.fixtures.contains(where: { $0.fixtureID == id }) {
                moveIDs.insert(id)
            }
        }
        return StageEditTransientTargets.fixtureIDs(
            activeTransform: activeTransform,
            moveDragFixtureIDs: moveIDs,
            aimFixtureID: fixtureAim?.fixtureID
        )
    }

    private var hasActiveTransformPreview: Bool {
        !transientLayoutObjectIDs.isEmpty || !transientFixtureIDs.isEmpty || isPanning
    }

    // MARK: - World content

    private var canvasContent: some View {
        ZStack {
            // Charcoal stage base (C4F — not brown checkpoint wash)
            Color(red: 0.07, green: 0.07, blue: 0.085)
            gridLayer

            // —— C4.4 committed layout-object layer ——
            // Artwork only when NOT in transient set. Gesture proxies always stay here so
            // SwiftUI gesture ownership is independent of the moving visual (Approach B).
            ForEach(layout.objects.filter { !$0.hidden }.sorted { $0.zIndex < $1.zIndex }) { obj in
                committedLayoutObjectHost(obj)
            }

            // —— C4.4 transient layout-object layer: the ONLY visual while transforming ——
            ZStack {
                ForEach(
                    layout.objects
                        .filter {
                            !$0.hidden
                                && StageEditRenderEligibility.shouldRenderInTransientLayer(
                                    elementID: $0.id,
                                    transientElementIDs: transientLayoutObjectIDs
                                )
                        }
                        .sorted { $0.zIndex < $1.zIndex }
                ) { obj in
                    transientLayoutObjectView(obj)
                }
            }
            .transaction { $0.animation = nil }
            .allowsHitTesting(false) // gestures live on committed proxies only

            // Fixtures/beams: omit active targets from committed path, render once in transient stack.
            ForEach(
                displayPlacements.filter {
                    !$0.hidden
                        && StageEditRenderEligibility.shouldRenderInCommittedLayer(
                            elementID: $0.fixtureID,
                            transientElementIDs: transientFixtureIDs
                        )
                }
            ) { beamLayer(for: $0) }

            ForEach(
                displayPlacements.filter {
                    !$0.hidden
                        && StageEditRenderEligibility.shouldRenderInCommittedLayer(
                            elementID: $0.fixtureID,
                            transientElementIDs: transientFixtureIDs
                        )
                }
            ) { fixtureView($0) }

            ZStack {
                ForEach(
                    displayPlacements.filter {
                        !$0.hidden
                            && StageEditRenderEligibility.shouldRenderInTransientLayer(
                                elementID: $0.fixtureID,
                                transientElementIDs: transientFixtureIDs
                            )
                    }
                ) { place in
                    beamLayer(for: place)
                    fixtureView(place)
                }
            }
            .transaction { $0.animation = nil }

            // Aim handles above glyphs (C4.2); use transient geometry while aiming.
            if canEditGeometry {
                ForEach(
                    displayPlacements.filter {
                        !$0.hidden && !$0.locked && selectedIDs.contains($0.fixtureID)
                    }
                ) { place in
                    aimHandleView(for: place)
                }
            }
            if let s = marqueeStart, let c = marqueeCurrent, !spaceHeld {
                Rectangle()
                    .strokeBorder(AuroraColor.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    .background(AuroraColor.accent.opacity(0.08))
                    .frame(width: abs(c.x - s.x), height: abs(c.y - s.y))
                    .position(x: (s.x + c.x) / 2, y: (s.y + c.y) / 2)
            }
        }
        .frame(width: layout.canvasWidth, height: layout.canvasHeight)
        .transaction { txn in
            if hasActiveTransformPreview { txn.animation = nil }
        }
        // C4.4: do NOT drawingGroup the live transform path — offscreen compositing worsened trails.
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard canEditGeometry, !spaceHeld else { return false }
            handleDrop(providers)
            return true
        }
    }

    /// Live display center (committed + transient move/resize) — absolute Stage world point.
    private func objectDisplayPoint(_ obj: StageLayoutObject) -> CGPoint {
        if let r = objectResize, r.objectID == obj.id {
            return CGPoint(x: r.currentX, y: r.currentY)
        }
        if let live = fixtureDrag?.displayPosition(for: obj.id) {
            return live
        }
        return CGPoint(x: obj.x, y: obj.y)
    }

    private func objectDisplayRotation(_ obj: StageLayoutObject) -> Double {
        if let r = objectRotate, r.objectID == obj.id {
            return r.currentRotation
        }
        if let preview = toolbarRotationPreview.wrappedValue[obj.id] {
            return preview
        }
        return obj.rotation
    }

    /// Live width/height while resizing (or committed size).
    private func objectDisplaySize(_ obj: StageLayoutObject) -> CGSize {
        if let r = objectResize, r.objectID == obj.id {
            return CGSize(width: r.currentWidth, height: r.currentHeight)
        }
        return CGSize(width: obj.width, height: obj.height)
    }

    // MARK: - C4.4 committed host (gesture + optional committed artwork)

    /// Stable host at **committed** geometry. Owns all drag gestures.
    /// When the object is in the transient set, artwork is omitted here (proxy only).
    @ViewBuilder
    private func committedLayoutObjectHost(_ obj: StageLayoutObject) -> some View {
        let selected = selectedObjectIDs.contains(obj.id)
        let showArtwork = StageEditRenderEligibility.shouldRenderInCommittedLayer(
            elementID: obj.id,
            transientElementIDs: transientLayoutObjectIDs
        )
        let size = CGSize(width: obj.width, height: obj.height)
        let showChrome = canEditGeometry && selected && !obj.locked
        let showGlyphSelection = selected && (!canEditGeometry || obj.locked) && showArtwork

        ZStack {
            if showArtwork {
                objectBody(obj, size: size, showGlyphSelection: showGlyphSelection)
                    .frame(width: size.width, height: size.height, alignment: .center)
                    .opacity(obj.locked ? 0.85 : 1)
            }
            // Invisible body hit target — always present so move gesture survives visual transfer.
            if canEditGeometry, !obj.locked {
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .highPriorityGesture(objectMoveGesture(for: obj))
            }
            // Handle hit targets stay at committed corners (Approach B); chrome visuals follow transient.
            if showChrome {
                transformChrome(for: obj, size: size, visual: showArtwork)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
        .rotationEffect(.radians(obj.rotation), anchor: .center)
        .position(x: obj.x, y: obj.y)
        .onTapGesture {
            guard interactionMode != .panOnly, !spaceHeld else { return }
            guard activeTransform.isNone else { return }
            applyObjectClickSelection(obj.id)
        }
        .contextMenu {
            if canEditGeometry {
                Button("Bring to Front") { zOrderObjects([obj.id], .front) }
                Button("Send to Back") { zOrderObjects([obj.id], .back) }
                Button("Bring Forward") { zOrderObjects([obj.id], .forward) }
                Button("Send Backward") { zOrderObjects([obj.id], .backward) }
                Divider()
                Button("Duplicate") { duplicateObjects([obj.id]) }
                if obj.locked {
                    Button("Unlock") { setObjectLocked(obj.id, false) }
                } else {
                    Button("Lock") { setObjectLocked(obj.id, true) }
                }
                Button("Delete", role: .destructive) { deleteObjects([obj.id]) }
            }
        }
    }

    // MARK: - C4.4 transient visual (artwork + chrome only; no gestures)

    @ViewBuilder
    private func transientLayoutObjectView(_ obj: StageLayoutObject) -> some View {
        let selected = selectedObjectIDs.contains(obj.id)
        let size = objectDisplaySize(obj)
        let rot = objectDisplayRotation(obj)
        let displayObj = sizedObject(obj, size: size)
        let pos = objectDisplayPoint(obj)
        let showGlyphSelection = selected && (!canEditGeometry || obj.locked)
        ZStack {
            objectBody(displayObj, size: size, showGlyphSelection: showGlyphSelection)
                .frame(width: size.width, height: size.height, alignment: .center)
            if canEditGeometry, selected, !obj.locked {
                // Visual chrome only — hit testing is on committed proxies.
                transformChrome(for: obj, size: size, visual: true, interactive: false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
        .rotationEffect(.radians(rot), anchor: .center)
        .position(x: pos.x, y: pos.y)
        .opacity(obj.locked ? 0.85 : 1)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func objectBody(_ displayObj: StageLayoutObject, size: CGSize, showGlyphSelection: Bool) -> some View {
        switch displayObj.kind {
        case .stockImage:
            StageStockGlyphView(
                assetKey: displayObj.assetKey ?? "",
                opacity: displayObj.opacity,
                selected: showGlyphSelection,
                locked: displayObj.locked,
                size: size
            )
        case .importedImage:
            importedImageView(displayObj, selected: showGlyphSelection)
        case .shape:
            shapeBody(displayObj, selected: showGlyphSelection)
        case .text:
            Text(displayObj.text.isEmpty ? displayObj.name : displayObj.text)
                .font(.system(size: max(10, min(size.height * 0.4, 28))))
                .foregroundStyle(Color.white.opacity(displayObj.opacity))
                .frame(width: size.width, height: size.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(showGlyphSelection ? AuroraColor.accentBright : Color.clear, lineWidth: 1.5)
                )
        }
    }

    private func objectMoveGesture(for obj: StageLayoutObject) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Exclusive ownership: resize/rotate/aim win over move.
                if activeTransform.blocksMove { return }
                if case .resize = activeTransform { return }
                if case .rotate = activeTransform { return }
                if case .aim = activeTransform { return }
                guard objectResize == nil, objectRotate == nil, fixtureAim == nil else { return }
                guard !spaceHeld else {
                    if activeTransform.isNone || activeTransform == .pan {
                        activeTransform = .pan
                        beginOrUpdatePan(translation: value.translation)
                    }
                    return
                }
                guard canEditGeometry, !obj.locked else { return }
                if activeTransform.isNone {
                    activeTransform = .move(objectID: obj.id)
                }
                guard case .move = activeTransform else { return }
                updateObjectDrag(anchor: obj, viewTranslation: value.translation)
            }
            .onEnded { value in
                if case .pan = activeTransform {
                    endPan()
                    activeTransform = .none
                    return
                }
                guard case .move(let id) = activeTransform, id == obj.id else {
                    if spaceHeld || isPanning { endPan() }
                    return
                }
                let worldTranslation = Self.localDragToWorldTranslation(
                    viewTranslation: value.translation,
                    objectRotation: obj.rotation,
                    scale: scale
                )
                commitObjectDrag(viewTranslation: worldTranslation, translationAlreadyWorld: true)
                activeTransform = .none
            }
    }

    private func sizedObject(_ obj: StageLayoutObject, size: CGSize) -> StageLayoutObject {
        var o = obj
        o.width = size.width
        o.height = size.height
        return o
    }

    /// Selection frame + four corner handles + rotation handle.
    /// - `visual`: draw chrome markers
    /// - `interactive`: attach gestures (committed proxy host only)
    @ViewBuilder
    private func transformChrome(
        for obj: StageLayoutObject,
        size: CGSize,
        visual: Bool = true,
        interactive: Bool = true
    ) -> some View {
        let visible: CGFloat = 7
        let hit: CGFloat = 16
        if visual {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(AuroraColor.accentBright.opacity(0.9), lineWidth: 1)
                .frame(width: size.width + 2, height: size.height + 2)
                .allowsHitTesting(false)
        }
        ForEach(StageResizeCorner.allCases, id: \.self) { corner in
            resizeHandle(
                for: obj,
                size: size,
                corner: corner,
                visible: visible,
                hit: hit,
                visual: visual,
                interactive: interactive
            )
        }
        rotationHandle(for: obj, size: size, visual: visual, interactive: interactive)
    }

    private func resizeHandle(
        for obj: StageLayoutObject,
        size: CGSize,
        corner: StageResizeCorner,
        visible: CGFloat,
        hit: CGFloat,
        visual: Bool,
        interactive: Bool
    ) -> some View {
        let ox: CGFloat
        let oy: CGFloat
        switch corner {
        case .northWest: ox = -size.width / 2; oy = -size.height / 2
        case .northEast: ox = size.width / 2; oy = -size.height / 2
        case .southWest: ox = -size.width / 2; oy = size.height / 2
        case .southEast: ox = size.width / 2; oy = size.height / 2
        }
        return ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: hit, height: hit)
            if visual {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AuroraColor.accentBright)
                    .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.white.opacity(0.95), lineWidth: 1))
                    .frame(width: visible, height: visible)
            }
        }
        .offset(x: ox, y: oy)
        .onHover { inside in
            guard interactive else { return }
            #if canImport(AppKit)
            if inside {
                if #available(macOS 15.0, *) {
                    switch corner {
                    case .northWest, .southEast:
                        NSCursor.frameResize(position: .topLeft, directions: [.all]).push()
                    case .northEast, .southWest:
                        NSCursor.frameResize(position: .topRight, directions: [.all]).push()
                    }
                } else {
                    NSCursor.crosshair.push()
                }
            } else {
                NSCursor.pop()
            }
            #endif
        }
        .highPriorityGesture(
            interactive
                ? DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !spaceHeld, canEditGeometry, !obj.locked else { return }
                        if activeTransform.blocksResize, case .resize(let id) = activeTransform, id != obj.id {
                            return
                        }
                        if case .move = activeTransform { return }
                        if case .aim = activeTransform { return }
                        if case .rotate = activeTransform { return }
                        let shift = NSEvent.modifierFlags.contains(.shift)
                        if objectResize == nil {
                            activeTransform = .resize(objectID: obj.id)
                            fixtureDrag = nil
                            objectRotate = nil
                            fixtureAim = nil
                            objectResize = StageObjectResizeState(
                                objectID: obj.id,
                                corner: corner,
                                originalX: obj.x,
                                originalY: obj.y,
                                originalWidth: obj.width,
                                originalHeight: obj.height,
                                originalRotation: obj.rotation,
                                aspectPolicy: StageResizeAspectPolicy.policy(for: obj.kind, shapeKind: obj.shapeKind)
                            )
                        }
                        guard var r = objectResize, r.objectID == obj.id, r.corner == corner else { return }
                        activeTransform = .resize(objectID: obj.id)
                        let live = StageLayoutResizeFinalizer.liveGeometry(
                            resize: r,
                            viewTranslation: value.translation,
                            scale: scale,
                            shiftHeld: shift,
                            translationIsLocal: true
                        )
                        r.currentX = live.x
                        r.currentY = live.y
                        r.currentWidth = live.width
                        r.currentHeight = live.height
                        objectResize = r
                    }
                    .onEnded { value in
                        let shift = NSEvent.modifierFlags.contains(.shift)
                        if case .resize = activeTransform {
                            commitObjectResize(
                                viewTranslation: value.translation,
                                shiftHeld: shift,
                                translationIsLocal: true
                            )
                        }
                        activeTransform = .none
                        #if canImport(AppKit)
                        NSCursor.pop()
                        #endif
                    }
                : nil
        )
        .help(interactive ? "Resize" : "")
        .accessibilityLabel(interactive ? "Resize \(corner.rawValue)" : "")
    }

    /// Direct rotation handle above object (C4.2).
    private func rotationHandle(
        for obj: StageLayoutObject,
        size: CGSize,
        visual: Bool,
        interactive: Bool
    ) -> some View {
        let offset = StageRotateMath.handleOffset(objectHeight: size.height)
        return ZStack {
            if visual {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: -size.height / 2))
                    p.addLine(to: CGPoint(x: offset.x, y: offset.y))
                }
                .stroke(AuroraColor.accentBright.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
            }
            Circle()
                .fill(Color.clear)
                .frame(width: 18, height: 18)
            if visual {
                Circle()
                    .strokeBorder(AuroraColor.accentBright, lineWidth: 1.5)
                    .background(Circle().fill(AuroraColor.surfaceRaised))
                    .frame(width: 10, height: 10)
            }
        }
        .offset(x: offset.x, y: offset.y)
        .highPriorityGesture(
            interactive
                ? DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !spaceHeld, canEditGeometry, !obj.locked else { return }
                        if activeTransform.blocksRotate, case .rotate(let id) = activeTransform, id != obj.id {
                            return
                        }
                        if case .resize = activeTransform { return }
                        if case .move = activeTransform { return }
                        if case .aim = activeTransform { return }

                        // Use committed center for handle math (gesture host is committed).
                        let center = CGPoint(x: obj.x, y: obj.y)
                        let startHandle = CGPoint(
                            x: center.x + offset.x * cos(obj.rotation) - offset.y * sin(obj.rotation),
                            y: center.y + offset.x * sin(obj.rotation) + offset.y * cos(obj.rotation)
                        )
                        let world = StageWorldDragMath.worldDelta(viewTranslation: value.translation, scale: scale)
                        if objectRotate == nil {
                            let pointer0 = startHandle
                            let angle0 = atan2(Double(pointer0.y - center.y), Double(pointer0.x - center.x))
                            objectRotate = StageObjectRotateState(
                                objectID: obj.id,
                                originalRotation: obj.rotation,
                                orientationOffset: obj.rotation - angle0
                            )
                            objectResize = nil
                            fixtureDrag = nil
                            activeTransform = .rotate(objectID: obj.id)
                        }
                        let pointer = CGPoint(
                            x: startHandle.x + world.width,
                            y: startHandle.y + world.height
                        )
                        guard var r = objectRotate, r.objectID == obj.id else { return }
                        r.currentRotation = StageRotateMath.rotationFromPointer(
                            center: center,
                            pointer: pointer,
                            orientationOffset: r.orientationOffset
                        )
                        objectRotate = r
                        activeTransform = .rotate(objectID: obj.id)
                        var preview = toolbarRotationPreview.wrappedValue
                        preview[obj.id] = r.currentRotation
                        toolbarRotationPreview.wrappedValue = preview
                    }
                    .onEnded { _ in
                        commitObjectRotate()
                        activeTransform = .none
                    }
                : nil
        )
        .help(interactive ? "Rotate" : "")
        .accessibilityLabel(interactive ? "Rotate object" : "")
    }

    @ViewBuilder
    private func shapeBody(_ obj: StageLayoutObject, selected: Bool) -> some View {
        let sk = obj.shapeKind ?? .rectangle
        let stroke = selected ? AuroraColor.accentBright : Color.white.opacity(0.35)
        Group {
            switch sk {
            case .stageArea:
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(AuroraColor.accent.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(AuroraColor.accent.opacity(0.06))
                    .frame(width: obj.width, height: obj.height)
            case .truss, .line:
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: max(obj.width, 4), height: max(obj.height, 4))
            case .ellipse, .region:
                Ellipse()
                    .strokeBorder(stroke, lineWidth: selected ? 2 : 1)
                    .background(Ellipse().fill(Color.white.opacity(0.04)))
                    .frame(width: obj.width, height: obj.height)
            case .triangle:
                TriangleShape()
                    .stroke(stroke, lineWidth: selected ? 2 : 1)
                    .background(TriangleShape().fill(Color.white.opacity(0.04)))
                    .frame(width: obj.width, height: obj.height)
            case .roundedRectangle:
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(stroke, lineWidth: selected ? 2 : 1)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                    .frame(width: obj.width, height: obj.height)
            default:
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(stroke, lineWidth: selected ? 2 : 1)
                    .background(Color.white.opacity(0.04))
                    .frame(width: obj.width, height: obj.height)
            }
        }
        .overlay(
            Text(obj.name.isEmpty ? sk.rawValue : obj.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        )
        .overlay(alignment: .topTrailing) {
            if obj.locked {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(AuroraColor.warning)
            }
        }
    }

    private struct TriangleShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    @ViewBuilder
    private func importedImageView(_ obj: StageLayoutObject, selected: Bool) -> some View {
        let size = CGSize(width: obj.width, height: obj.height)
        ZStack {
            if let ref = obj.mediaRef,
               let url = StageMediaSupport.resolveFileURL(
                mediaRef: ref,
                packageRoot: context.packageURL
               ),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .opacity(obj.opacity)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: size.width, height: size.height)
                    .overlay(Text("Missing").font(.caption2).foregroundStyle(.secondary))
            }
            if selected {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(AuroraColor.accentBright, lineWidth: 1.5)
                    .frame(width: size.width + 6, height: size.height + 6)
            }
            if obj.locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AuroraColor.warning)
                    .offset(x: size.width * 0.35, y: -size.height * 0.4)
            }
        }
    }

    private var gridLayer: some View {
        Canvas { ctx, _ in
            guard layout.gridSize > 0 else { return }
            let step = layout.gridSize
            var path = Path()
            var x: Double = 0
            while x <= layout.canvasWidth {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: layout.canvasHeight))
                x += step
            }
            var y: Double = 0
            while y <= layout.canvasHeight {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.canvasWidth, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
        }
        .frame(width: layout.canvasWidth, height: layout.canvasHeight)
        .allowsHitTesting(false)
    }

    private var displayPlacements: [StageFixturePlacement] {
        layout.fixtures.sorted { $0.zIndex < $1.zIndex }
    }

    private func displayPoint(for place: StageFixturePlacement) -> CGPoint {
        if let live = fixtureDrag?.displayPosition(for: place.fixtureID) {
            return live
        }
        return CGPoint(x: place.x, y: place.y)
    }

    // MARK: - Canvas pan / marquee

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Never steal an in-progress object/fixture transform.
                if !activeTransform.isNone, activeTransform != .pan { return }
                if shouldCameraPan {
                    activeTransform = .pan
                    beginOrUpdatePan(translation: value.translation)
                    return
                }
                // Edit Stage empty-space marquee (not while Space-panning)
                guard canEditGeometry, !spaceHeld else { return }
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                }
                marqueeCurrent = value.location
            }
            .onEnded { _ in
                if isPanning || panAtDragStart != nil {
                    endPan()
                }
                if case .pan = activeTransform { activeTransform = .none }
                if canEditGeometry, !spaceHeld, let s = marqueeStart, let c = marqueeCurrent {
                    let rect = CGRect(
                        x: min(s.x, c.x), y: min(s.y, c.y),
                        width: abs(c.x - s.x), height: abs(c.y - s.y)
                    )
                    if rect.width > 4 || rect.height > 4 {
                        applyMarquee(rect)
                    }
                }
                marqueeStart = nil
                marqueeCurrent = nil
            }
    }

    private func beginOrUpdatePan(translation: CGSize) {
        if panAtDragStart == nil {
            panAtDragStart = pan
            isPanning = true
            #if canImport(AppKit)
            NSCursor.closedHand.push()
            #endif
        }
        guard let start = panAtDragStart else { return }
        pan = StageCameraPan.displayedPan(start: start, translation: translation)
    }

    private func endPan() {
        panAtDragStart = nil
        if isPanning {
            isPanning = false
            #if canImport(AppKit)
            NSCursor.pop()
            #endif
        }
    }

    // MARK: - Fixture beam (C4.1 wedge) + glyph

    /// Effective physical aim during live drag (C4.2).
    private func effectivePlacement(_ place: StageFixturePlacement) -> StageFixturePlacement {
        guard let aim = fixtureAim, aim.fixtureID == place.fixtureID else { return place }
        var p = place
        p.aimDirection = aim.currentDirection
        p.beamLength = aim.currentLength
        return p
    }

    @ViewBuilder
    private func beamLayer(for place: StageFixturePlacement) -> some View {
        let place = effectivePlacement(place)
        let fx = context.project.fixtures.first { $0.id == place.fixtureID }
        let def = fx.flatMap { context.project.definition(id: $0.definitionId) }
        let state = preview.fixtures.first { $0.fixtureID == place.fixtureID }
        let intensity = state?.intensity ?? 0
        let selected = selectedIDs.contains(place.fixtureID)
        let beamDetail = beamDetailLevel(selected: selected)
        let pos = displayPoint(for: place)
        // Show faint beam when aiming in Edit Stage even at low intensity
        let aiming = fixtureAim?.fixtureID == place.fixtureID
        let show = place.beamVisible && beamDetail > 0 && (intensity > 0.01 || aiming)
        if show {
            let aim = StageBeamDirectionResolver.renderedAimRadians(
                placement: place,
                livePan: aiming ? nil : state?.pan,
                liveTilt: aiming ? nil : state?.tilt,
                panRangeRadians: nil,
                hasPanTilt: !aiming && (def?.hasPanTilt == true || state?.pan != nil)
            )
            let lengthScale = aiming ? 1.0 : StageBeamDirectionResolver.lengthScale(liveTilt: state?.tilt)
            let spreadScale = aiming ? 1.0 : StageBeamDirectionResolver.spreadScale(liveTilt: state?.tilt)
            let length = place.beamLength * lengthScale * (beamDetail >= 2 ? 1 : 0.75)
            let spread = place.beamSpread * spreadScale
            let color = state?.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
                ?? Color.white
            let visIntensity = aiming ? max(intensity, 0.45) : intensity
            StageBeamView(
                origin: pos,
                directionRadians: aim,
                length: length,
                spreadRadians: spread,
                color: color,
                intensity: visIntensity,
                detailLevel: beamDetail
            )
        }
    }

    /// Direct beam aim handle at beam tip (Edit Stage only).
    private func aimHandleView(for place: StageFixturePlacement) -> some View {
        let place = effectivePlacement(place)
        let center = displayPoint(for: place)
        let handle = StageAimMath.handlePoint(
            fixtureCenter: center,
            direction: place.aimDirection,
            length: place.beamLength
        )
        return ZStack {
            // Centerline guide
            Path { p in
                p.move(to: center)
                p.addLine(to: handle)
            }
            .stroke(AuroraColor.accentBright.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .allowsHitTesting(false)
            Circle()
                .fill(Color.clear)
                .frame(width: 22, height: 22)
            Circle()
                .fill(AuroraColor.warning.opacity(0.95))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                .frame(width: 12, height: 12)
        }
        .position(x: handle.x, y: handle.y)
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !spaceHeld, canEditGeometry, !place.locked else { return }
                    if activeTransform.blocksAim, case .aim(let id) = activeTransform, id != place.fixtureID {
                        return
                    }
                    if case .resize = activeTransform { return }
                    if case .move = activeTransform { return }
                    if case .rotate = activeTransform { return }

                    if fixtureAim == nil {
                        let committed = layout.fixtures.first(where: { $0.fixtureID == place.fixtureID }) ?? place
                        fixtureAim = StageFixtureAimState(
                            fixtureID: place.fixtureID,
                            originalDirection: committed.aimDirection,
                            originalLength: committed.beamLength
                        )
                        fixtureDrag = nil
                        objectResize = nil
                        objectRotate = nil
                        activeTransform = .aim(fixtureID: place.fixtureID)
                    }
                    let world = StageWorldDragMath.worldDelta(viewTranslation: value.translation, scale: scale)
                    // Start handle was at original tip; pointer = start tip + world delta
                    let startTip = StageAimMath.handlePoint(
                        fixtureCenter: center,
                        direction: fixtureAim!.originalDirection,
                        length: fixtureAim!.originalLength
                    )
                    let pointer = CGPoint(x: startTip.x + world.width, y: startTip.y + world.height)
                    let result = StageAimMath.aimFromPointer(fixtureCenter: center, pointer: pointer)
                    guard var aim = fixtureAim else { return }
                    aim.currentDirection = result.direction
                    aim.currentLength = result.length
                    fixtureAim = aim
                    activeTransform = .aim(fixtureID: place.fixtureID)
                }
                .onEnded { _ in
                    commitFixtureAim()
                    activeTransform = .none
                }
        )
        .help("Aim beam")
        .accessibilityLabel("Aim beam")
    }

    private func fixtureView(_ place: StageFixturePlacement) -> some View {
        let fx = context.project.fixtures.first { $0.id == place.fixtureID }
        let def = fx.flatMap { context.project.definition(id: $0.definitionId) }
        let state = preview.fixtures.first { $0.fixtureID == place.fixtureID }
        let intensity = state?.intensity ?? 0
        let color = state?.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? Color.white
        let selected = selectedIDs.contains(place.fixtureID)
        let category = def?.category ?? "generic"
        let size: CGFloat = 28 * place.scale
        let pos = displayPoint(for: place)

        return ZStack {
            categoryShape(category, color: color, intensity: intensity, size: size, selected: selected)
            if place.labelVisible {
                Text(fx?.name ?? "?")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.9))
                    .offset(y: size * 0.7)
            }
        }
        .frame(width: size + 24, height: size + 24)
        .contentShape(Rectangle())
        // Rotate around glyph center, then place; live drag uses offset only (no ghosting).
        .rotationEffect(.radians(place.rotation), anchor: .center)
        .position(x: pos.x, y: pos.y)
        .opacity(place.locked ? 0.85 : 1)
        .transaction { $0.animation = nil }
        .highPriorityGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if activeTransform.blocksMove { return }
                    if case .aim = activeTransform { return }
                    if case .resize = activeTransform { return }
                    guard !spaceHeld else {
                        activeTransform = .pan
                        beginOrUpdatePan(translation: value.translation)
                        return
                    }
                    guard canEditGeometry, !place.locked else { return }
                    if activeTransform.isNone {
                        activeTransform = .move(objectID: place.fixtureID)
                    }
                    guard case .move = activeTransform else { return }
                    updateFixtureDrag(anchor: place, viewTranslation: value.translation)
                }
                .onEnded { value in
                    if case .pan = activeTransform {
                        endPan()
                        activeTransform = .none
                        return
                    }
                    guard case .move = activeTransform else {
                        if spaceHeld || isPanning { endPan() }
                        return
                    }
                    commitFixtureDrag(viewTranslation: value.translation)
                    activeTransform = .none
                }
        )
        .onTapGesture {
            guard interactionMode != .panOnly, !spaceHeld else { return }
            guard activeTransform.isNone else { return }
            applyClickSelection(place.fixtureID)
        }
        .contextMenu {
            Button("Locate") {
                onSelectFixtures([place.fixtureID])
            }
            if canEditGeometry {
                Button("Remove From Stage", role: .destructive) {
                    removeFromStage(ids: [place.fixtureID])
                }
                if place.locked {
                    Button("Unlock") { setLocked(place.fixtureID, false) }
                } else {
                    Button("Lock") { setLocked(place.fixtureID, true) }
                }
            }
        }
    }

    // MARK: - Live multi-fixture drag

    private func updateFixtureDrag(anchor: StageFixturePlacement, viewTranslation: CGSize) {
        if fixtureDrag == nil {
            beginFixtureDrag(anchor: anchor)
        }
        guard var drag = fixtureDrag else { return }
        drag.currentDelta = StageLayoutDragFinalizer.liveDelta(
            layout: layout,
            drag: drag,
            viewTranslation: viewTranslation,
            scale: scale
        )
        fixtureDrag = drag
    }

    private func beginFixtureDrag(anchor: StageFixturePlacement) {
        // Selection semantics: if anchor not selected, select it (replace).
        var workingSelection = selectedIDs
        if !workingSelection.contains(anchor.fixtureID) {
            workingSelection = [anchor.fixtureID]
            onSelectFixtures([anchor.fixtureID])
            selectedObjectIDs = []
        }
        if anchor.locked {
            fixtureDrag = nil
            return
        }

        let origins = StageLayoutDragFinalizer.fixtureOrigins(
            layout: layout,
            selection: workingSelection,
            anchorID: anchor.fixtureID
        )
        guard !origins.isEmpty else {
            fixtureDrag = nil
            return
        }
        fixtureDrag = StageObjectDragState(
            anchorID: anchor.fixtureID,
            originalPositions: origins
        )
    }

    private func commitFixtureDrag(viewTranslation: CGSize) {
        guard let drag = fixtureDrag else { return }
        fixtureDrag = nil
        // Production finalization path — same pure function as unit tests.
        guard let next = StageLayoutDragFinalizer.finalizedLayout(
            layout: context.project.stageLayout,
            drag: drag,
            viewTranslation: viewTranslation,
            scale: scale
        ) else { return }
        commitLayout(next, notify: true)
        let count = drag.originalPositions.count
        statusNote?.wrappedValue = count > 1
            ? "Moved \(count) items"
            : "Moved item"
    }

    private func updateObjectDrag(anchor: StageLayoutObject, viewTranslation: CGSize) {
        if fixtureDrag == nil {
            beginObjectDrag(anchor: anchor)
        }
        guard var drag = fixtureDrag else { return }
        // Gesture lives inside a rotationEffect; map local drag into Stage world axes.
        let worldTranslation = Self.localDragToWorldTranslation(
            viewTranslation: viewTranslation,
            objectRotation: anchor.rotation,
            scale: scale
        )
        drag.currentDelta = StageLayoutDragFinalizer.liveDelta(
            layout: layout,
            drag: drag,
            viewTranslation: worldTranslation,
            scale: 1 // already converted to world pixels
        )
        fixtureDrag = drag
    }

    /// Convert a drag translation from an object-local (rotated) view into Stage world deltas.
    /// `scale` is the canvas camera zoom applied outside the object.
    private static func localDragToWorldTranslation(
        viewTranslation: CGSize,
        objectRotation: Double,
        scale: CGFloat
    ) -> CGSize {
        let local = StageWorldDragMath.worldDelta(viewTranslation: viewTranslation, scale: scale)
        let c = cos(objectRotation)
        let s = sin(objectRotation)
        // Local +X/+Y → world (rotation maps local axes into world).
        return CGSize(
            width: local.width * c - local.height * s,
            height: local.width * s + local.height * c
        )
    }

    private func beginObjectDrag(anchor: StageLayoutObject) {
        var working = selectedObjectIDs
        if !working.contains(anchor.id) {
            working = [anchor.id]
            selectedObjectIDs = working
            onSelectFixtures([])
        }
        if anchor.locked {
            fixtureDrag = nil
            return
        }
        let origins = StageLayoutDragFinalizer.objectOrigins(
            layout: layout,
            selection: working,
            anchorID: anchor.id
        )
        guard !origins.isEmpty else {
            fixtureDrag = nil
            return
        }
        fixtureDrag = StageObjectDragState(anchorID: anchor.id, originalPositions: origins)
    }

    private func commitObjectDrag(viewTranslation: CGSize, translationAlreadyWorld: Bool = false) {
        guard let drag = fixtureDrag else { return }
        fixtureDrag = nil
        let scaleForFinalize: CGFloat = translationAlreadyWorld ? 1 : scale
        guard let next = StageLayoutDragFinalizer.finalizedLayout(
            layout: context.project.stageLayout,
            drag: drag,
            viewTranslation: viewTranslation,
            scale: scaleForFinalize
        ) else { return }
        commitLayout(next, notify: true)
        let count = drag.originalPositions.count
        statusNote?.wrappedValue = count > 1 ? "Moved \(count) items" : "Moved item"
    }

    private func commitObjectResize(
        viewTranslation: CGSize,
        shiftHeld: Bool = false,
        translationIsLocal: Bool = false
    ) {
        guard let resize = objectResize else { return }
        objectResize = nil
        guard let next = StageLayoutResizeFinalizer.finalizedLayout(
            layout: context.project.stageLayout,
            resize: resize,
            viewTranslation: viewTranslation,
            scale: scale,
            shiftHeld: shiftHeld,
            translationIsLocal: translationIsLocal
        ) else { return }
        commitLayout(next, notify: true)
        statusNote?.wrappedValue = "Resized object"
    }

    private func commitObjectRotate() {
        guard let rotate = objectRotate else { return }
        objectRotate = nil
        var preview = toolbarRotationPreview.wrappedValue
        preview.removeValue(forKey: rotate.objectID)
        toolbarRotationPreview.wrappedValue = preview
        var next = context.project.stageLayout
        guard let i = next.objects.firstIndex(where: { $0.id == rotate.objectID }) else { return }
        guard !next.objects[i].locked else { return }
        if abs(next.objects[i].rotation - rotate.currentRotation) < 0.0005 { return }
        next.objects[i].rotation = rotate.currentRotation
        commitLayout(next, notify: true)
        statusNote?.wrappedValue = "Rotated object"
    }

    private func commitFixtureAim() {
        guard let aim = fixtureAim else { return }
        fixtureAim = nil
        var next = context.project.stageLayout
        guard let i = next.fixtures.firstIndex(where: { $0.fixtureID == aim.fixtureID }) else { return }
        guard !next.fixtures[i].locked else { return }
        let unchanged =
            abs(next.fixtures[i].aimDirection - aim.currentDirection) < 0.0005
            && abs(next.fixtures[i].beamLength - aim.currentLength) < 0.5
        if unchanged { return }
        next.fixtures[i].aimDirection = aim.currentDirection
        next.fixtures[i].beamLength = max(8, aim.currentLength)
        commitLayout(next, notify: true)
        statusNote?.wrappedValue = "Aimed fixture"
    }

    private func duplicateObjects(_ ids: [UUID]) {
        guard canEditGeometry, !ids.isEmpty else { return }
        var next = layout
        var newIDs: [UUID] = []
        let offset: Double = 24
        for id in ids {
            guard let src = next.objects.first(where: { $0.id == id }) else { continue }
            var copy = src
            copy.id = UUID()
            copy.x += offset
            copy.y += offset
            copy.zIndex = next.nextZIndex
            copy.locked = false
            next.appendObject(copy)
            newIDs.append(copy.id)
        }
        guard !newIDs.isEmpty else { return }
        commitLayout(next)
        selectedObjectIDs = Set(newIDs)
        onSelectFixtures([])
        statusNote?.wrappedValue = newIDs.count == 1 ? "Duplicated object" : "Duplicated \(newIDs.count) objects"
    }

    private func applyObjectClickSelection(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        var next = selectedObjectIDs
        if flags.contains(.command) {
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
        } else if flags.contains(.shift) {
            next.insert(id)
        } else {
            next = [id]
            onSelectFixtures([])
        }
        selectedObjectIDs = next
    }

    private enum ZOrderOp { case front, back, forward, backward }

    private func zOrderObjects(_ ids: [UUID], _ op: ZOrderOp) {
        guard canEditGeometry, !ids.isEmpty else { return }
        var next = layout
        let idSet = Set(ids)
        var objs = next.objects
        switch op {
        case .front:
            let maxZ = (objs.map(\.zIndex).max() ?? 0) + 1
            for i in objs.indices where idSet.contains(objs[i].id) {
                objs[i].zIndex = maxZ + i
            }
        case .back:
            let minZ = (objs.map(\.zIndex).min() ?? 0) - ids.count
            var k = 0
            for i in objs.indices where idSet.contains(objs[i].id) {
                objs[i].zIndex = minZ + k
                k += 1
            }
        case .forward:
            for i in objs.indices where idSet.contains(objs[i].id) {
                objs[i].zIndex += 1
            }
        case .backward:
            for i in objs.indices where idSet.contains(objs[i].id) {
                objs[i].zIndex -= 1
            }
        }
        next.objects = objs
        commitLayout(next)
        statusNote?.wrappedValue = "Z-order updated"
    }

    private func setObjectLocked(_ id: UUID, _ locked: Bool) {
        var next = layout
        if let i = next.objects.firstIndex(where: { $0.id == id }) {
            next.objects[i].locked = locked
            commitLayout(next)
        }
    }

    private func deleteObjects(_ ids: [UUID]) {
        guard canEditGeometry else { return }
        var next = layout
        let set = Set(ids)
        next.objects.removeAll { set.contains($0.id) }
        selectedObjectIDs.subtract(set)
        commitLayout(next)
        statusNote?.wrappedValue = "Deleted object(s)"
    }

    private func clearTransientInteraction() {
        fixtureDrag = nil
        objectResize = nil
        objectRotate = nil
        fixtureAim = nil
        activeTransform = .none
        marqueeStart = nil
        marqueeCurrent = nil
        if panAtDragStart != nil || isPanning {
            endPan()
        }
    }

    // MARK: - Drawing helpers

    private func beamDetailLevel(selected: Bool) -> Int {
        let n = preview.fixtures.count
        if selected { return 2 }
        if n > 60 { return 0 }
        if n > 30 { return 1 }
        return 2
    }

    @ViewBuilder
    private func categoryShape(
        _ category: String,
        color: Color,
        intensity: Double,
        size: CGFloat,
        selected: Bool
    ) -> some View {
        let c = category.lowercased()
        let fill = color.opacity(0.22 + 0.78 * intensity)
        let stroke = selected ? AuroraColor.accent : Color.white.opacity(0.4)
        Group {
            if c.contains("bar") || c.contains("pixel") || c.contains("batten") {
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
                    .frame(width: size * 1.7, height: size * 0.38)
            } else if c.contains("head") || c.contains("spot") || c.contains("profile") || c.contains("beam") {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill)
                    .frame(width: size * 0.85, height: size * 0.85)
                    .rotationEffect(.degrees(45))
            } else if c.contains("blinder") || c.contains("strobe") {
                RoundedRectangle(cornerRadius: 2)
                    .fill(fill)
                    .frame(width: size, height: size)
            } else if c.contains("fog") || c.contains("haze") || c.contains("laser") {
                Circle()
                    .strokeBorder(color.opacity(0.85), lineWidth: 2)
                    .background(Circle().fill(fill.opacity(0.5)))
                    .frame(width: size * 0.75, height: size * 0.75)
            } else {
                Circle()
                    .fill(fill)
                    .frame(width: size, height: size)
                    .shadow(color: color.opacity(intensity), radius: 8 * intensity)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(stroke, lineWidth: selected ? 2 : 1)
                .frame(width: size + 4, height: size + 4)
        )
    }

    private func scenicView(_ obj: StageScenicObject) -> some View {
        Group {
            if obj.kind == .stageArea {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(AuroraColor.accent.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(AuroraColor.accent.opacity(0.06))
                    .frame(width: obj.width, height: obj.height)
            } else if obj.kind == .truss || obj.kind == .line {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: max(obj.width, 4), height: max(obj.height, 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    .background(Color.white.opacity(0.04))
                    .frame(width: obj.width, height: obj.height)
            }
        }
        .overlay(
            Text(obj.name.isEmpty ? obj.kind.rawValue : obj.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        )
        .position(x: obj.x, y: obj.y)
        .contextMenu {
            if canEditGeometry {
                Button("Delete scenic", role: .destructive) {
                    removeScenic(id: obj.id)
                }
            }
        }
    }

    // MARK: - Selection

    private func applyClickSelection(_ id: UUID) {
        let flags = NSEvent.modifierFlags
        var next = selectedIDs
        if flags.contains(.command) {
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            onSelectFixtures(Array(next))
        } else if flags.contains(.shift) {
            next.insert(id)
            onSelectFixtures(Array(next))
        } else {
            onSelectFixtures([id])
            selectedObjectIDs = []
        }
    }

    private func applyMarquee(_ rect: CGRect) {
        let flags = NSEvent.modifierFlags
        let hitFixtures = displayPlacements.filter { place in
            !place.hidden && rect.contains(CGPoint(x: place.x, y: place.y))
        }.map(\.fixtureID)
        let hitObjects = layout.objects.filter { obj in
            !obj.hidden && rect.contains(CGPoint(x: obj.x, y: obj.y))
        }.map(\.id)

        var nextFx = selectedIDs
        var nextObj = selectedObjectIDs
        if flags.contains(.shift) {
            nextFx.formUnion(hitFixtures)
            nextObj.formUnion(hitObjects)
        } else if flags.contains(.command) {
            for id in hitFixtures {
                if nextFx.contains(id) { nextFx.remove(id) } else { nextFx.insert(id) }
            }
            for id in hitObjects {
                if nextObj.contains(id) { nextObj.remove(id) } else { nextObj.insert(id) }
            }
        } else {
            nextFx = Set(hitFixtures)
            nextObj = Set(hitObjects)
        }
        onSelectFixtures(Array(nextFx))
        selectedObjectIDs = nextObj
    }

    // MARK: - Layout mutations (edit only)

    private func removeFromStage(ids: [UUID]) {
        guard canEditGeometry else { return }
        do {
            try context.session.perform(RemoveFromStageCommand(fixtureIDs: ids))
            statusNote?.wrappedValue = "Removed from Stage (still patched)"
            onLayoutChanged()
        } catch {
            statusNote?.wrappedValue = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard canEditGeometry else { return }
        for p in providers {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String, let id = UUID(uuidString: s) else { return }
                DispatchQueue.main.async {
                    let x = layout.canvasWidth / 2
                    let y = layout.canvasHeight / 2
                    do {
                        try context.session.perform(PlaceFixtureOnStageCommand(fixtureID: id, x: x, y: y))
                        onSelectFixtures([id])
                        onLayoutChanged()
                        statusNote?.wrappedValue = "Placed on Stage"
                    } catch {
                        statusNote?.wrappedValue = error.localizedDescription
                    }
                }
            }
        }
    }

    private func removeScenic(id: UUID) {
        deleteObjects([id])
    }

    private func setLocked(_ fixtureID: UUID, _ locked: Bool) {
        guard canEditGeometry else { return }
        var layout = context.project.stageLayout
        if let i = layout.fixtures.firstIndex(where: { $0.fixtureID == fixtureID }) {
            layout.fixtures[i].locked = locked
            commitLayout(layout)
        }
    }

    private func commitLayout(_ layout: StageLayout, notify: Bool = true) {
        do {
            try context.session.perform(UpdateStageLayoutCommand(layout: layout))
            if notify { onLayoutChanged() }
        } catch {
            // Never silently discard Stage document mutations (Post-C6 audit).
            let message = error.localizedDescription
            statusNote?.wrappedValue = message
            // Best-effort diagnostic surface when available via layout callback chain.
            #if DEBUG
            print("Stage layout commit failed: \(message)")
            #endif
        }
    }

    // MARK: - Camera

    public func fitStage(in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let sx = size.width / layout.canvasWidth
        let sy = size.height / layout.canvasHeight
        scale = min(sx, sy, 1.5) * 0.92
        pan = .zero
        panAtDragStart = nil
    }

    private func reveal(fixtureID: UUID) {
        guard let place = layout.fixtures.first(where: { $0.fixtureID == fixtureID }) else {
            statusNote?.wrappedValue = "Fixture not on Stage"
            return
        }
        scale = max(scale, 1.2)
        pan = CGSize(
            width: canvasSize.width / 2 - CGFloat(place.x) * scale,
            height: canvasSize.height / 2 - CGFloat(place.y) * scale
        )
        panAtDragStart = nil
        onSelectFixtures([fixtureID])
        statusNote?.wrappedValue = "Revealed on Stage"
    }
}

// MARK: - Space / Escape tracking (scoped to active Stage surface)

/// Tracks Space for Stage pan **only** when the pointer is over a Stage canvas
/// and text editing is not active. Never steals Space from text fields.
@MainActor
final class StageCanvasKeyState: ObservableObject {
    static let shared = StageCanvasKeyState()

    @Published private(set) var spaceHeld = false
    /// Escape press generation — canvas can observe to cancel drag.
    @Published private(set) var escapeTick: UInt64 = 0

    private var retainCount = 0
    private var hoverCount = 0
    private var keyMonitor: Any?
    private var pushedPanCursor = false

    private init() {}

    /// True when at least one Stage canvas is mounted and the pointer is inside it.
    var stageOwnsNavigationKeys: Bool {
        retainCount > 0 && hoverCount > 0 && !AuroraKeyboardGate.isTextEditingActive
    }

    func retain() {
        retainCount += 1
        guard retainCount == 1 else { return }
        installMonitor()
    }

    func release() {
        retainCount = max(0, retainCount - 1)
        if retainCount == 0 {
            hoverCount = 0
            tearDownMonitor()
            clearSpaceHeld(restoreCursor: true)
        }
    }

    func setPointerInsideStage(_ inside: Bool) {
        if inside {
            hoverCount += 1
        } else {
            hoverCount = max(0, hoverCount - 1)
            // Leaving Stage while Space held: release pan mode without forcing global arrow
            // if we didn't push a pan cursor, or pop only our push.
            if hoverCount == 0 {
                clearSpaceHeld(restoreCursor: true)
            }
        }
    }

    private func installMonitor() {
        #if canImport(AppKit)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            // 49 = Space, 53 = Escape
            if event.keyCode == 49 {
                return self.handleSpaceEvent(event)
            }
            if event.type == .keyDown, event.keyCode == 53 {
                // Escape cancel only when Stage owns interaction (not typing).
                if !AuroraKeyboardGate.isTextEditingActive, self.retainCount > 0 {
                    Task { @MainActor in
                        self.escapeTick &+= 1
                    }
                }
            }
            return event
        }
        #endif
    }

    private func tearDownMonitor() {
        #if canImport(AppKit)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        #endif
    }

    #if canImport(AppKit)
    private func handleSpaceEvent(_ event: NSEvent) -> NSEvent? {
        // Never intercept Space while typing in text fields / search / field editor.
        if AuroraKeyboardGate.isTextEditingActive {
            if event.type == .keyUp {
                Task { @MainActor in self.clearSpaceHeld(restoreCursor: true) }
            }
            return event
        }
        // Stage must be mounted and pointer over Stage for navigation ownership.
        guard retainCount > 0, hoverCount > 0 else {
            if event.type == .keyUp {
                Task { @MainActor in self.clearSpaceHeld(restoreCursor: true) }
            }
            return event
        }

        if event.type == .keyDown, !event.isARepeat {
            Task { @MainActor in
                self.spaceHeld = true
                if !self.pushedPanCursor {
                    NSCursor.openHand.push()
                    self.pushedPanCursor = true
                }
            }
            // Consume only when Stage owns Space for pan navigation.
            return nil
        }
        if event.type == .keyUp {
            Task { @MainActor in
                self.clearSpaceHeld(restoreCursor: true)
            }
            return nil
        }
        return event
    }
    #endif

    private func clearSpaceHeld(restoreCursor: Bool) {
        spaceHeld = false
        #if canImport(AppKit)
        if restoreCursor, pushedPanCursor {
            NSCursor.pop()
            pushedPanCursor = false
        }
        #endif
    }
}

// MARK: - Camera helpers for hosts

public enum StageCanvasCamera {
    public static func fitStage(layout: StageLayout, in size: CGSize) -> (scale: CGFloat, pan: CGSize) {
        guard size.width > 1, size.height > 1 else { return (1, .zero) }
        let sx = size.width / layout.canvasWidth
        let sy = size.height / layout.canvasHeight
        let scale = min(sx, sy, 1.5) * 0.92
        return (scale, .zero)
    }

    public static func fitSelection(
        placements: [StageFixturePlacement],
        selectedIDs: Set<UUID>,
        in size: CGSize
    ) -> (scale: CGFloat, pan: CGSize)? {
        let places = placements.filter { selectedIDs.contains($0.fixtureID) }
        guard let minX = places.map(\.x).min(),
              let maxX = places.map(\.x).max(),
              let minY = places.map(\.y).min(),
              let maxY = places.map(\.y).max()
        else { return nil }
        let w = max(maxX - minX, 80)
        let h = max(maxY - minY, 80)
        let sx = size.width / (w + 80)
        let sy = size.height / (h + 80)
        let scale = min(sx, sy, 2.5)
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let pan = CGSize(
            width: size.width / 2 - CGFloat(cx) * scale,
            height: size.height / 2 - CGFloat(cy) * scale
        )
        return (scale, pan)
    }
}
