import AuroraDesignSystem
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
    public var selectedTargets: Set<FixtureTarget>
    public var orderedSelectedTargets: [FixtureTarget]
    /// Selected layout object IDs (stock/scenic/import) — C4.
    @Binding public var selectedObjectIDs: Set<UUID>
    public var onSelectFixtures: ([UUID]) -> Void
    public var onSelectFixtureTargets: ([FixtureTarget]) -> Void
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
    @State private var fixtureRotate: StageObjectRotateState?
    @State private var fixtureAim: StageFixtureAimState?
    @State private var showExactRotationPrompt = false
    @State private var exactRotationText = "0"
    @State private var inspectedPhysicalElements: Set<String> = []
    @State private var hoveredFixtureID: UUID?
    @State private var hoverCardFixtureID: UUID?
    /// Fixture and canvas gestures see the same pointer sequence. Content claims
    /// the pointer on down so its up event cannot also clear selection as "blank".
    @State private var pointerClaimedByFixture = false
    /// C4.2: exclusive owner of the current pointer drag.
    @State private var activeTransform: StageTransformInteraction = .none
    @ObservedObject private var keys = StageCanvasKeyState.shared

    public init(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        interactionMode: StageInteractionMode = .programSelect,
        geometryEditingEnabled: Bool = false,
        selectedIDs: Set<UUID>,
        selectedTargets: Set<FixtureTarget>? = nil,
        orderedSelectedTargets: [FixtureTarget]? = nil,
        selectedObjectIDs: Binding<Set<UUID>> = .constant([]),
        scale: Binding<CGFloat>,
        pan: Binding<CGSize>,
        onSelectFixtures: @escaping ([UUID]) -> Void,
        onSelectFixtureTargets: (([FixtureTarget]) -> Void)? = nil,
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
        self.selectedTargets = selectedTargets ?? Set(selectedIDs.map { FixtureTarget(fixtureID: $0) })
        self.orderedSelectedTargets = orderedSelectedTargets ?? Array(self.selectedTargets).sorted {
            if $0.fixtureID != $1.fixtureID { return $0.fixtureID.uuidString < $1.fixtureID.uuidString }
            return ($0.elementID ?? "") < ($1.elementID ?? "")
        }
        self._selectedObjectIDs = selectedObjectIDs
        self._scale = scale
        self._pan = pan
        self.onSelectFixtures = onSelectFixtures
        self.onSelectFixtureTargets = onSelectFixtureTargets ?? { targets in
            onSelectFixtures(Array(Set(targets.map(\.fixtureID))))
        }
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

    private var canMarqueeSelect: Bool { interactionMode != .panOnly }

    /// Space-pan wins over marquee/fixture geometry.
    private var shouldCameraPan: Bool {
        if spaceHeld { return true }
        switch interactionMode {
        case .panOnly: return true
        case .programSelect, .editGeometry: return false
        }
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundLayer
                viewportGridLayer
                canvasContent
                    .scaleEffect(scale)
                    .offset(pan)
                    .contentShape(Rectangle())
                    .gesture(canvasGesture)
                #if canImport(AppKit)
                StageScrollZoomMonitor { delta, location in
                    zoomFromScroll(delta: delta, anchor: location)
                }
                .allowsHitTesting(false)
                #endif
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
            .task(id: hoveredFixtureID) {
                hoverCardFixtureID = nil
                guard let candidate = hoveredFixtureID else { return }
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, hoveredFixtureID == candidate, fixtureDrag == nil else { return }
                hoverCardFixtureID = candidate
            }
            .onChange(of: keys.escapeTick) { _, _ in
                if fixtureDrag != nil || objectResize != nil || objectRotate != nil || fixtureRotate != nil || fixtureAim != nil {
                    fixtureDrag = nil
                    objectResize = nil
                    objectRotate = nil
                    fixtureRotate = nil
                    fixtureAim = nil
                    activeTransform = .none
                    statusNote?.wrappedValue = "Transform cancelled"
                } else {
                    clearStageSelection()
                }
            }
            .onChange(of: keys.rotateStepTick) { _, _ in
                guard canEditGeometry, !selectedIDs.isEmpty else { return }
                rotateSelectedFixtures(byDegrees: 90)
            }
            .onChange(of: keys.rotateExactTick) { _, _ in
                guard canEditGeometry, !selectedIDs.isEmpty else { return }
                exactRotationText = selectedFixtureRotationDegrees.map { String(format: "%.1f", $0) } ?? "0"
                showExactRotationPrompt = true
            }
            .onChange(of: keys.zoomInTick) { _, _ in
                zoom(by: 1.18, anchor: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
            }
            .onChange(of: keys.zoomOutTick) { _, _ in
                zoom(by: 1 / 1.18, anchor: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2))
            }
            .alert("Rotate Fixtures", isPresented: $showExactRotationPrompt) {
                TextField("Degrees", text: $exactRotationText)
                Button("Cancel", role: .cancel) {}
                Button("Rotate") { applyExactFixtureRotation() }
            } message: {
                Text("Enter an angle from −180° to 180°.")
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        Color(red: 0.045, green: 0.047, blue: 0.058)
            .overlay {
                if preview.blackout {
                    Color.black
                } else {
                    RadialGradient(
                        colors: [dominantStageColor.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: max(canvasSize.width, canvasSize.height) * 0.7
                    )
                }
            }
        .animation(.easeInOut(duration: 0.25), value: preview.dominantColor)
    }

    private var dominantStageColor: Color {
        Color(
            red: preview.dominantColor.r,
            green: preview.dominantColor.g,
            blue: preview.dominantColor.b
        )
    }

    /// Screen-space grid derived from the camera. It fills the viewport instead
    /// of ending at the document's original canvas rectangle.
    private var viewportGridLayer: some View {
        Canvas { context, size in
            guard layout.gridSize > 0, scale > 0.01 else { return }
            let step = CGFloat(layout.gridSize) * scale
            guard step > 2 else { return }
            let worldOrigin = CGPoint(
                x: size.width / 2 + pan.width - CGFloat(layout.canvasWidth / 2) * scale,
                y: size.height / 2 + pan.height - CGFloat(layout.canvasHeight / 2) * scale
            )
            let firstX = worldOrigin.x + floor(-worldOrigin.x / step) * step
            let firstY = worldOrigin.y + floor(-worldOrigin.y / step) * step
            var minor = Path()
            var major = Path()
            var x = firstX
            while x <= size.width {
                let worldIndex = Int(round((x - worldOrigin.x) / step))
                var path = worldIndex.isMultiple(of: 5) ? major : minor
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                if worldIndex.isMultiple(of: 5) { major = path } else { minor = path }
                x += step
            }
            var y = firstY
            while y <= size.height {
                let worldIndex = Int(round((y - worldOrigin.y) / step))
                var path = worldIndex.isMultiple(of: 5) ? major : minor
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                if worldIndex.isMultiple(of: 5) { major = path } else { minor = path }
                y += step
            }
            context.stroke(minor, with: .color(Color.white.opacity(0.025)), lineWidth: 0.5)
            context.stroke(major, with: .color(Color.white.opacity(0.055)), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        var ids = StageEditTransientTargets.fixtureIDs(
            activeTransform: activeTransform,
            moveDragFixtureIDs: moveIDs,
            aimFixtureID: fixtureAim?.fixtureID
        )
        if let id = fixtureRotate?.objectID { ids.insert(id) }
        return ids
    }

    private var hasActiveTransformPreview: Bool {
        !transientLayoutObjectIDs.isEmpty || !transientFixtureIDs.isEmpty || isPanning
    }

    // MARK: - World content

    private var canvasContent: some View {
        ZStack {
            // The viewport supplies the charcoal base and unbounded grid. Keeping
            // this layer transparent prevents a legacy canvas rectangle edge.
            Color.clear
            if !preview.blackout {
                RadialGradient(
                    colors: [dominantStageColor.opacity(0.07), .clear],
                    center: .center,
                    startRadius: 30,
                    endRadius: min(layout.canvasWidth, layout.canvasHeight) * 0.62
                )
                .allowsHitTesting(false)
            }
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

            // Beams omit active targets from the committed path. Fixture gesture
            // hosts always remain at committed geometry; only their artwork moves
            // to the transient layer so SwiftUI cannot cancel the owning drag.
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
                displayPlacements.filter { !$0.hidden }
            ) { place in
                fixtureView(
                    place,
                    rendersArtwork: StageEditRenderEligibility.shouldRenderInCommittedLayer(
                        elementID: place.fixtureID,
                        transientElementIDs: transientFixtureIDs
                    ),
                    usesTransientGeometry: false
                )
            }

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
                    fixtureView(place, usesTransientGeometry: true)
                }
            }
            .transaction { $0.animation = nil }
            .allowsHitTesting(false) // fixture gestures stay on committed hosts

            // Aim handles above glyphs (C4.2); use transient geometry while aiming.
            if canEditGeometry {
                ForEach(
                    displayPlacements.filter {
                        !$0.hidden && !$0.locked && selectedIDs.contains($0.fixtureID)
                    }
                ) { place in
                    aimHandleView(for: place)
                    fixtureRotationHandle(for: place)
                }
            }
            if fixtureDrag == nil,
               let hoverCardFixtureID,
               hoveredFixtureID == hoverCardFixtureID,
               let hoveredPlacement = displayPlacements.first(where: { $0.fixtureID == hoverCardFixtureID && !$0.hidden }) {
                fixtureHoverCard(for: hoveredPlacement)
            }
            if let s = marqueeStart, let c = marqueeCurrent, !spaceHeld, canMarqueeSelect {
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
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let next = fixtureDrag == nil ? fixtureID(atStagePoint: location) : nil
                if hoveredFixtureID != next {
                    hoverCardFixtureID = nil
                    hoveredFixtureID = next
                }
            case .ended:
                hoverCardFixtureID = nil
                hoveredFixtureID = nil
            }
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
        ZStack {
            switch sk {
            case .stageArea:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(selected ? 0.62 : 0.28), lineWidth: selected ? 2 : 1.25)
                    )
                    .frame(width: obj.width, height: obj.height)
            case .truss:
                StageTrussShape()
                    .stroke(stroke, style: StrokeStyle(lineWidth: selected ? 2 : 1.35, lineCap: .round, lineJoin: .round))
                    .frame(width: obj.width, height: obj.height)
            case .line:
                Rectangle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: max(obj.width, 4), height: max(obj.height, 4))
            case .ellipse:
                Ellipse()
                    .strokeBorder(stroke, lineWidth: selected ? 2 : 1)
                    .background(Ellipse().fill(Color.white.opacity(0.04)))
                    .frame(width: obj.width, height: obj.height)
            case .region:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(stroke, lineWidth: selected ? 2 : 1)
                    )
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
            shapeLabel(obj.name.isEmpty ? sk.rawValue : obj.name, edgeAligned: sk == .stageArea || sk == .region)
        }
        .overlay(alignment: .topTrailing) {
            if obj.locked {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(AuroraColor.warning)
            }
        }
    }

    @ViewBuilder
    private func shapeLabel(_ text: String, edgeAligned: Bool) -> some View {
        Text(text)
            .font(.system(size: edgeAligned ? 10 : 9, weight: edgeAligned ? .semibold : .medium))
            .foregroundStyle(Color.white.opacity(0.82))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.52), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAligned ? .topLeading : .center)
            .padding(edgeAligned ? 7 : 0)
            .allowsHitTesting(false)
    }

    /// Lightweight procedural truss for scalable rigging runs. Detailed stock
    /// truss assets remain available from the Stage Objects palette.
    private struct StageTrussShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let inset = min(max(rect.height * 0.18, 2), 8)
            let top = rect.minY + inset
            let bottom = rect.maxY - inset
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: top))
            path.move(to: CGPoint(x: rect.minX, y: bottom))
            path.addLine(to: CGPoint(x: rect.maxX, y: bottom))

            let bayWidth = max(rect.height * 0.9, 18)
            var x = rect.minX
            var rises = true
            while x < rect.maxX {
                let next = min(x + bayWidth, rect.maxX)
                path.move(to: CGPoint(x: x, y: rises ? bottom : top))
                path.addLine(to: CGPoint(x: next, y: rises ? top : bottom))
                rises.toggle()
                x = next
            }
            return path
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
            let opacity = interactionMode == .editGeometry ? 0.075 : 0.026
            ctx.stroke(path, with: .color(Color.white.opacity(opacity)), lineWidth: 1)
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
                    guard hypot(value.translation.width, value.translation.height) >= 4 else { return }
                    activeTransform = .pan
                    beginOrUpdatePan(translation: value.translation)
                    return
                }
                // Empty-space drag selects; Space-drag is the sole camera-pan gesture.
                guard canMarqueeSelect, !spaceHeld else { return }
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                }
                marqueeCurrent = value.location
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                let performedPan = isPanning || panAtDragStart != nil
                let wasClaimedByFixture = pointerClaimedByFixture
                pointerClaimedByFixture = false
                if isPanning || panAtDragStart != nil {
                    endPan()
                }
                if case .pan = activeTransform { activeTransform = .none }
                if canMarqueeSelect, !spaceHeld, let s = marqueeStart, let c = marqueeCurrent {
                    let rect = CGRect(
                        x: min(s.x, c.x), y: min(s.y, c.y),
                        width: abs(c.x - s.x), height: abs(c.y - s.y)
                    )
                    if rect.width > 4 || rect.height > 4 {
                        applyMarquee(rect)
                    }
                }
                let performedMarquee = canMarqueeSelect && marqueeStart != nil && marqueeCurrent != nil
                    && hypot((marqueeCurrent?.x ?? 0) - (marqueeStart?.x ?? 0), (marqueeCurrent?.y ?? 0) - (marqueeStart?.y ?? 0)) >= 4
                if StagePointerArbitration.shouldClearSelection(
                    contentClaimed: wasClaimedByFixture,
                    performedPan: performedPan,
                    movement: moved,
                    performedMarquee: performedMarquee
                ) {
                    clearStageSelection()
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
        var p = place
        if let aim = fixtureAim, aim.fixtureID == place.fixtureID {
            p.aimDirection = aim.currentDirection
            p.beamLength = aim.currentLength
        }
        if let rotate = fixtureRotate, rotate.objectID == place.fixtureID {
            p.rotation = rotate.currentRotation
        }
        return p
    }

    @ViewBuilder
    private func beamLayer(for place: StageFixturePlacement) -> some View {
        let place = effectivePlacement(place)
        let fx = context.project.fixtures.first { $0.id == place.fixtureID }
        let def = fx.flatMap { context.project.definition(id: $0.definitionId) }
        let state = preview.fixtures.first { $0.fixtureID == place.fixtureID }
        let descriptor = def.map { context.project.visualizationDescriptor(for: $0) }
        let emitsBeam = descriptor?.form != .atmospheric && descriptor?.componentGroups.contains(where: { $0.topology == .noBeam }) != true
        let selected = selectedIDs.contains(place.fixtureID)
        let beamDetail = beamDetailLevel(selected: selected)
        let pos = displayPoint(for: place)
        // Show faint beam when aiming in Edit Stage even at low intensity
        let aiming = fixtureAim?.fixtureID == place.fixtureID
        let show = place.beamVisible && beamDetail > 0 && ((state?.intensity ?? 0) > 0.01 || aiming)
        let renderedEmitters = descriptor.flatMap { descriptor in
            def.map { physicalLiveEmitters(state: state, descriptor: descriptor, definition: $0) }
        } ?? state.map { $0.physicalEmitters.isEmpty ? $0.elements : $0.physicalEmitters } ?? []
        if show, emitsBeam, let state, !renderedEmitters.isEmpty {
            let aim = StageBeamDirectionResolver.renderedAimRadians(
                placement: place,
                livePan: aiming ? nil : state.pan,
                liveTilt: aiming ? nil : state.tilt,
                panRangeRadians: nil,
                hasPanTilt: !aiming && (def?.hasPanTilt == true || state.pan != nil)
            )
            let lengthScale = aiming ? 1.0 : StageBeamDirectionResolver.lengthScale(liveTilt: state.tilt)
            let spreadScale = aiming ? 1.0 : StageBeamDirectionResolver.spreadScale(liveTilt: state.tilt)
            let length = place.beamLength * lengthScale * (beamDetail >= 2 ? 1 : 0.75)
            let spread = place.beamSpread * spreadScale
            // A compound fixture's placement spread describes the assembly; each
            // independently emitting element needs a distinct optical cone.
            let elementSpread = min(spread, .pi / 9)
            let size: CGFloat = 28 * place.scale
            let glyphGeometry = descriptor.map {
                FixtureGlyphGeometryBuilder.build(descriptor: $0, baseHeight: Double(max(20, size + 8)), detailLevel: beamDetail)
            }
            let emitterOrigins = Array(renderedEmitters.enumerated()).map { index, element in
                glyphGeometry?.opticalOrigins[element.elementID].map {
                    glyphGeometry!.stagePoint(localPoint: $0, fixtureOrigin: pos, rotation: place.rotation)
                } ?? StageMultiElementGeometry.elementOrigin(
                    fixtureOrigin: pos,
                    fixtureRotation: place.rotation,
                    index: index,
                    count: renderedEmitters.count,
                    podDiameter: 14,
                    spacing: 3,
                    horizontal: true
                )
            }
            let linearForm = descriptor.map { $0.form == .linearBar || $0.form == .strip || $0.form == .multiHeadBar } ?? false
            if linearForm && place.beamRenderMode == .softGlow && !aiming {
                StageLinearGlowView(
                    origins: emitterOrigins,
                    colors: renderedEmitters.map { $0.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .white },
                    intensities: renderedEmitters.map(\.intensity)
                )
            } else {
                ForEach(Array(renderedEmitters.enumerated()), id: \.element.id) { index, element in
                    let origin = emitterOrigins[index]
                    if element.intensity > 0.01 || aiming {
                        StageBeamView(
                            origin: origin,
                            directionRadians: aim,
                            length: length,
                            spreadRadians: elementSpread,
                            color: element.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .white,
                            intensity: aiming ? max(element.intensity, 0.45) : element.intensity,
                            detailLevel: beamDetail
                        )
                    }
                }
            }
        } else if show, emitsBeam {
            let aim = StageBeamDirectionResolver.renderedAimRadians(
                placement: place,
                livePan: aiming ? nil : state?.pan,
                liveTilt: aiming ? nil : state?.tilt,
                panRangeRadians: nil,
                hasPanTilt: !aiming && (def?.hasPanTilt == true || state?.pan != nil)
            )
            let lengthScale = aiming ? 1.0 : StageBeamDirectionResolver.lengthScale(liveTilt: state?.tilt)
            let spreadScale = aiming ? 1.0 : StageBeamDirectionResolver.spreadScale(liveTilt: state?.tilt)
            StageBeamView(
                origin: pos,
                directionRadians: aim,
                length: place.beamLength * lengthScale * (beamDetail >= 2 ? 1 : 0.75),
                spreadRadians: place.beamSpread * spreadScale,
                color: state?.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .white,
                intensity: aiming ? max(state?.intensity ?? 0, 0.45) : state?.intensity ?? 0,
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

    private func fixtureView(
        _ originalPlace: StageFixturePlacement,
        rendersArtwork: Bool = true,
        usesTransientGeometry: Bool = true
    ) -> some View {
        let place = usesTransientGeometry ? effectivePlacement(originalPlace) : originalPlace
        let fx = context.project.fixtures.first { $0.id == place.fixtureID }
        let def = fx.flatMap { context.project.definition(id: $0.definitionId) }
        let state = preview.fixtures.first { $0.fixtureID == place.fixtureID }
        let intensity = state?.intensity ?? 0
        let color = state?.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? Color.white
        let selected = selectedIDs.contains(place.fixtureID)
            || fixtureDrag?.movableIDs.contains(place.fixtureID) == true
        let size: CGFloat = 28 * place.scale
        let pos = usesTransientGeometry
            ? displayPoint(for: place)
            : CGPoint(x: originalPlace.x, y: originalPlace.y)

        let descriptor = def.map { context.project.visualizationDescriptor(for: $0) }
        let detail = descriptor.map {
            FixtureGlyphLevelOfDetail.detailLevel(screenExtent: Double(max(20, size + 8) * scale * CGFloat(FixtureGlyphGeometryBuilder.canonicalAspect(form: $0.form, descriptorAspect: $0.aspectRatio))))
        } ?? 1
        let glyphGeometry = descriptor.map {
            FixtureGlyphGeometryBuilder.build(descriptor: $0, baseHeight: Double(max(20, size + 8)), detailLevel: detail)
        }

        return ZStack {
            if rendersArtwork, let descriptor, let def, let glyphGeometry {
                let affectedPhysicalIDs = Set(descriptor.emitters.compactMap { emitter in
                    let resolution = FixturePhysicalControlMapper.resolve(physicalEmitterID: emitter.id, descriptor: descriptor, definition: def)
                    let selectedByControl: Bool
                    switch resolution.disposition {
                    case .controls(let controls):
                        selectedByControl = controls.contains { selectedTargets.contains(FixtureTarget(fixtureID: place.fixtureID, elementID: $0)) }
                    case .wholeFixture:
                        selectedByControl = selectedTargets.contains(FixtureTarget(fixtureID: place.fixtureID))
                    case .inspectionOnly:
                        selectedByControl = false
                    }
                    return selectedByControl ? emitter.id : nil
                })
                // Selection chrome follows the resolved control target, not the one
                // physical aperture that happened to initiate it. A 4-pixel control
                // group must highlight all four pixels and clear as one unit.
                let selectedPhysicalIDs = affectedPhysicalIDs
                let atmosphericIndicator = descriptor.indicators.first { $0.kind == .atmosphereCloud }
                let atmosphericLevel = atmosphericIndicator.flatMap { state?.environmental[$0.attribute] } ?? 0
                FixtureGlyphRenderer(
                    descriptor: descriptor,
                    geometry: glyphGeometry,
                    liveEmitters: physicalLiveEmitters(state: state, descriptor: descriptor, definition: def),
                    selectedEmitterIDs: selectedPhysicalIDs,
                    affectedEmitterIDs: affectedPhysicalIDs.subtracting(selectedPhysicalIDs),
                    wholeSelected: selectedTargets.contains(FixtureTarget(fixtureID: place.fixtureID))
                        || fixtureDrag?.movableIDs.contains(place.fixtureID) == true,
                    atmosphericLevel: atmosphericLevel
                )
                // This recognizer is intentionally attached before fixture padding,
                // rotation, position, camera zoom, and camera pan. Its location is
                // therefore expressed in the exact coordinate system used to build
                // `glyphGeometry`.
                .highPriorityGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard !spaceHeld else { return }
                            pointerClaimedByFixture = true
                            if stageShiftModifierActive,
                               let aperture = glyphGeometry.interactionApertures.min(by: {
                                   hypot($0.center.x - value.location.x, $0.center.y - value.location.y)
                                       < hypot($1.center.x - value.location.x, $1.center.y - value.location.y)
                               }) {
                                applyPhysicalEmitterClickSelection(
                                    emitterID: aperture.id,
                                    fixtureID: place.fixtureID,
                                    descriptor: descriptor,
                                    definition: def,
                                    modifiers: [.shift]
                                )
                            } else {
                                applyPhysicalTargets([FixtureTarget(fixtureID: place.fixtureID)])
                            }
                            DispatchQueue.main.async { pointerClaimedByFixture = false }
                        }
                )
            } else if rendersArtwork {
                categoryShape(def?.category ?? "generic", color: color, intensity: intensity, size: size, selected: selected)
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            pointerClaimedByFixture = true
                            applyPhysicalTargets([FixtureTarget(fixtureID: place.fixtureID)])
                            DispatchQueue.main.async { pointerClaimedByFixture = false }
                        }
                    )
            }
            if rendersArtwork, place.labelVisible {
                Text(fx?.name ?? "?")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.62), in: Capsule())
                    .offset(y: size * 0.78)
            }
        }
        .frame(width: (glyphGeometry?.bodyBounds.width ?? size) + 24, height: (glyphGeometry?.bodyBounds.height ?? size) + 24)
        .contentShape(Rectangle())
        // Rotate around glyph center, then place; live drag uses offset only (no ghosting).
        .rotationEffect(.radians(place.rotation), anchor: .center)
        .position(x: pos.x, y: pos.y)
        .opacity(place.locked ? 0.85 : 1)
        .transaction { $0.animation = nil }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pointerClaimedByFixture = true
                    if activeTransform.blocksMove { return }
                    if case .aim = activeTransform { return }
                    if case .resize = activeTransform { return }
                    guard !spaceHeld else {
                        activeTransform = .pan
                        beginOrUpdatePan(translation: value.translation)
                        return
                    }
                    guard canEditGeometry, !place.locked else { return }
                    guard hypot(value.translation.width, value.translation.height) >= 6 else { return }
                    if activeTransform.isNone {
                        activeTransform = .move(objectID: place.fixtureID)
                    }
                    guard case .move = activeTransform else { return }
                    updateFixtureDrag(anchor: place, viewTranslation: value.translation)
                }
                .onEnded { value in
                    // Parent and child gesture callbacks finish in the same event
                    // turn. Clear on the next turn so the canvas can observe the
                    // claim regardless of callback ordering, while avoiding a stale
                    // claim if SwiftUI suppresses the parent callback.
                    DispatchQueue.main.async { pointerClaimedByFixture = false }
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
        .contextMenu {
            Button("Locate") {
                onSelectFixtures([place.fixtureID])
            }
            Button("Show DMX Output") {
                NotificationCenter.default.post(
                    name: Notification.Name("aurora.openDMXMonitor"),
                    object: place.fixtureID
                )
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

    private func fixtureHoverText(
        fixture: PatchedFixture?,
        definition: FixtureDefinition?,
        placement: StageFixturePlacement
    ) -> String {
        guard let fixture else { return "Unknown fixture" }
        let project = context.project
        return StageFixtureHoverInfo.text(
            fixture: fixture,
            definition: definition,
            universe: project.universe(id: fixture.universeId),
            footprint: project.channelCount(for: fixture),
            groupNames: project.groups
                .filter { $0.fixtureIds.contains(fixture.id) }
                .map(\.name),
            locked: placement.locked
        )
    }

    /// Canvas-level hover arbitration avoids stale per-view enter/exit events when
    /// SwiftUI swaps committed fixture artwork into the transient render layer.
    private func fixtureID(atStagePoint point: CGPoint) -> UUID? {
        for placement in displayPlacements.reversed() where !placement.hidden {
            let fixture = context.project.fixtures.first { $0.id == placement.fixtureID }
            let definition = fixture.flatMap { context.project.definition(id: $0.definitionId) }
            let descriptor = definition.map { context.project.visualizationDescriptor(for: $0) }
            let baseHeight = CGFloat(max(20, 28 * placement.scale + 8))
            let aspect = CGFloat(descriptor.map {
                FixtureGlyphGeometryBuilder.canonicalAspect(form: $0.form, descriptorAspect: $0.aspectRatio)
            } ?? 1)
            let halfWidth = (baseHeight * aspect + 24) / 2
            let halfHeight = (baseHeight + 24) / 2
            let dx = point.x - CGFloat(placement.x)
            let dy = point.y - CGFloat(placement.y)
            let c = CGFloat(cos(placement.rotation))
            let s = CGFloat(sin(placement.rotation))
            let localX = dx * c + dy * s
            let localY = -dx * s + dy * c
            if abs(localX) <= halfWidth, abs(localY) <= halfHeight {
                return placement.fixtureID
            }
        }
        return nil
    }

    private func fixtureHoverCard(for placement: StageFixturePlacement) -> some View {
        let fixture = context.project.fixtures.first { $0.id == placement.fixtureID }
        let definition = fixture.flatMap { context.project.definition(id: $0.definitionId) }
        let text = fixtureHoverText(fixture: fixture, definition: definition, placement: placement)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let cardWidth: CGFloat = 270
        let placementX = CGFloat(placement.x)
        let placementY = CGFloat(placement.y)
        let xOffset: CGFloat = placementX > CGFloat(layout.canvasWidth) - cardWidth - 36
            ? -(cardWidth / 2 + 34)
            : (cardWidth / 2 + 34)
        let yOffset: CGFloat = placementY < 120 ? 72 : -72

        return VStack(alignment: .leading, spacing: 5) {
            if let title = lines.first {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
            }
            ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.055, green: 0.058, blue: 0.072).opacity(0.97))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .position(x: placementX + xOffset, y: placementY + yOffset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .zIndex(10_000)
    }

    private func fixtureRotationHandle(for originalPlace: StageFixturePlacement) -> some View {
        let place = effectivePlacement(originalPlace)
        let center = displayPoint(for: place)
        let size: CGFloat = 28 * place.scale
        let offset = StageRotateMath.handleOffset(objectHeight: size + 24, margin: 12)
        let handle = CGPoint(
            x: center.x + offset.x * cos(place.rotation) - offset.y * sin(place.rotation),
            y: center.y + offset.x * sin(place.rotation) + offset.y * cos(place.rotation)
        )
        return ZStack {
            Path { p in
                p.move(to: center)
                p.addLine(to: handle)
            }
            .stroke(AuroraColor.accentBright.opacity(0.65), lineWidth: 1)
            Circle()
                .strokeBorder(AuroraColor.accentBright, lineWidth: 1.5)
                .background(Circle().fill(AuroraColor.surfaceRaised))
                .frame(width: 11, height: 11)
                .position(handle)
        }
        .contentShape(Circle().path(in: CGRect(x: handle.x - 10, y: handle.y - 10, width: 20, height: 20)))
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !spaceHeld, canEditGeometry, !place.locked else { return }
                    if activeTransform.blocksRotate,
                       case .rotate(let id) = activeTransform,
                       id != place.fixtureID { return }
                    if activeTransform.blocksRotate && fixtureRotate == nil { return }
                    let world = StageWorldDragMath.worldDelta(viewTranslation: value.translation, scale: scale)
                    if fixtureRotate == nil {
                        let angle0 = atan2(Double(handle.y - center.y), Double(handle.x - center.x))
                        fixtureRotate = StageObjectRotateState(
                            objectID: place.fixtureID,
                            originalRotation: originalPlace.rotation,
                            orientationOffset: originalPlace.rotation - angle0
                        )
                        fixtureAim = nil
                        fixtureDrag = nil
                        activeTransform = .rotate(objectID: place.fixtureID)
                    }
                    let pointer = CGPoint(x: handle.x + world.width, y: handle.y + world.height)
                    guard var rotate = fixtureRotate, rotate.objectID == place.fixtureID else { return }
                    rotate.currentRotation = StageRotateMath.rotationFromPointer(
                        center: center,
                        pointer: pointer,
                        orientationOffset: rotate.orientationOffset
                    )
                    fixtureRotate = rotate
                }
                .onEnded { _ in
                    commitFixtureRotate()
                    activeTransform = .none
                }
        )
        .help("Rotate fixture")
        .accessibilityLabel("Rotate fixture")
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
        // Keep first-drag selection local. Publishing an external selection here
        // rebuilds the fixture subtree while SwiftUI is delivering this gesture,
        // which can truncate the first move. Mouse-up publishes the selection.
        let workingSelection = StageFixtureDragSelection.workingSelection(
            current: selectedIDs,
            anchorID: anchor.fixtureID
        )
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
        let publishAnchorSelection = StageFixtureDragSelection.shouldPublishAfterDrag(
            current: selectedIDs,
            anchorID: drag.anchorID
        )
        fixtureDrag = nil
        // Production finalization path — same pure function as unit tests.
        if let next = StageLayoutDragFinalizer.finalizedLayout(
            layout: context.project.stageLayout,
            drag: drag,
            viewTranslation: viewTranslation,
            scale: scale
        ) {
            commitLayout(next, notify: true)
            let count = drag.originalPositions.count
            statusNote?.wrappedValue = count > 1
                ? "Moved \(count) items"
                : "Moved item"
        }
        if publishAnchorSelection {
            selectedObjectIDs = []
            onSelectFixtureTargets([FixtureTarget(fixtureID: drag.anchorID)])
        }
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

    private func commitFixtureRotate() {
        guard let rotate = fixtureRotate else { return }
        fixtureRotate = nil
        var next = context.project.stageLayout
        guard let i = next.fixtures.firstIndex(where: { $0.fixtureID == rotate.objectID }),
              !next.fixtures[i].locked
        else { return }
        guard abs(next.fixtures[i].rotation - rotate.currentRotation) >= 0.0005 else { return }
        next.fixtures[i].rotation = rotate.currentRotation
        commitLayout(next, notify: true)
        statusNote?.wrappedValue = "Rotated fixture"
    }

    private var selectedFixtureRotationDegrees: Double? {
        guard let firstID = selectedIDs.first,
              let place = layout.fixtures.first(where: { $0.fixtureID == firstID })
        else { return nil }
        return place.rotation * 180 / .pi
    }

    private func rotateSelectedFixtures(byDegrees degrees: Double) {
        var next = context.project.stageLayout
        var changed = 0
        let delta = degrees * .pi / 180
        for i in next.fixtures.indices
        where selectedIDs.contains(next.fixtures[i].fixtureID) && !next.fixtures[i].locked {
            next.fixtures[i].rotation = StageRotateMath.normalizedRadians(next.fixtures[i].rotation + delta)
            changed += 1
        }
        guard changed > 0 else { return }
        commitLayout(next, notify: true)
        statusNote?.wrappedValue = "Rotated \(changed) fixture\(changed == 1 ? "" : "s") 90°"
    }

    private func applyExactFixtureRotation() {
        let normalized = exactRotationText.replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let degrees = Double(normalized), degrees.isFinite else {
            statusNote?.wrappedValue = "Enter a valid rotation in degrees"
            return
        }
        var next = context.project.stageLayout
        var changed = 0
        let clamped = min(180, max(-180, degrees))
        let radians = StageRotateMath.normalizedRadians(clamped * .pi / 180)
        for i in next.fixtures.indices
        where selectedIDs.contains(next.fixtures[i].fixtureID) && !next.fixtures[i].locked {
            next.fixtures[i].rotation = radians
            changed += 1
        }
        guard changed > 0 else { return }
        commitLayout(next, notify: true)
        statusNote?.wrappedValue = "Set fixture rotation to \(Int(clamped.rounded()))°"
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
        fixtureRotate = nil
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

    private func applyElementClickSelection(_ target: FixtureTarget) {
        guard interactionMode == .programSelect, !spaceHeld, activeTransform.isNone else { return }
        let flags = NSEvent.modifierFlags
        var next = orderedSelectedTargets
        if flags.contains(.command) {
            if target.elementID == nil {
                next.removeAll { $0.fixtureID == target.fixtureID }
            } else {
                next.removeAll { $0 == FixtureTarget(fixtureID: target.fixtureID) }
            }
            if let index = next.firstIndex(of: target) { next.remove(at: index) } else { next.append(target) }
        } else if flags.contains(.shift) {
            if target.elementID == nil {
                next.removeAll { $0.fixtureID == target.fixtureID }
            } else {
                next.removeAll { $0 == FixtureTarget(fixtureID: target.fixtureID) }
            }
            if !next.contains(target) { next.append(target) }
        } else {
            next = [target]
            selectedObjectIDs = []
        }
        onSelectFixtureTargets(next)
    }

    private func applyPhysicalEmitterClickSelection(
        emitterID: String,
        fixtureID: UUID,
        descriptor: FixtureVisualizationDescriptor,
        definition: FixtureDefinition,
        modifiers: NSEvent.ModifierFlags? = nil
    ) {
        guard interactionMode != .panOnly, !spaceHeld, activeTransform.isNone else { return }
        let key = physicalInspectionKey(fixtureID: fixtureID, emitterID: emitterID)
        let flags = modifiers ?? NSEvent.modifierFlags
        if flags.contains(.shift) {
            if inspectedPhysicalElements.contains(key) { inspectedPhysicalElements.remove(key) }
            else { inspectedPhysicalElements.insert(key) }
        } else {
            inspectedPhysicalElements = [key]
        }
        let resolution = FixturePhysicalControlMapper.resolve(physicalEmitterID: emitterID, descriptor: descriptor, definition: definition)
        switch resolution.disposition {
        case .inspectionOnly:
            statusNote?.wrappedValue = "Physical element has no programmer control in this personality"
            return
        case .wholeFixture:
            applyPhysicalTargets([FixtureTarget(fixtureID: fixtureID)], modifiers: flags)
            statusNote?.wrappedValue = "This personality controls all physical emitters together"
        case .controls(let controls):
            applyPhysicalTargets(
                controls.map { FixtureTarget(fixtureID: fixtureID, elementID: $0) },
                modifiers: flags
            )
            statusNote?.wrappedValue = controls.count == 1
                ? "Selected sub-fixture \(controls.first ?? "")"
                : "Selected \(controls.count) linked sub-fixtures"
        }
    }

    /// SwiftUI's tap value does not carry modifiers. Combine the Stage monitor with
    /// the session-wide hardware state so Shift remains authoritative even when the
    /// key was pressed before the pointer entered this particular Stage view.
    private var stageShiftModifierActive: Bool {
        if keys.shiftHeld { return true }
        #if canImport(AppKit)
        if NSEvent.modifierFlags.contains(.shift) { return true }
        return CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)
        #else
        return false
        #endif
    }

    private func applyPhysicalTargets(
        _ targets: [FixtureTarget],
        modifiers: NSEvent.ModifierFlags? = nil
    ) {
        guard !targets.isEmpty else { return }
        let flags = modifiers ?? NSEvent.modifierFlags
        var next = orderedSelectedTargets
        if flags.contains(.command) || flags.contains(.shift) {
            for target in targets {
                if target.elementID == nil {
                    next.removeAll { $0.fixtureID == target.fixtureID }
                } else {
                    next.removeAll { $0 == FixtureTarget(fixtureID: target.fixtureID) }
                }
                if let index = next.firstIndex(of: target) { next.remove(at: index) } else { next.append(target) }
            }
        } else {
            next = targets
            selectedObjectIDs = []
        }
        onSelectFixtureTargets(next)
        if targets.allSatisfy({ $0.elementID == nil }) {
            statusNote?.wrappedValue = targets.count == 1 ? "Selected fixture" : "Selected \(targets.count) fixtures"
        }
    }

    private func physicalInspectionKey(fixtureID: UUID, emitterID: String) -> String {
        "\(fixtureID.uuidString)#\(emitterID)"
    }

    private func clearStageSelection() {
        inspectedPhysicalElements.removeAll()
        selectedObjectIDs.removeAll()
        onSelectFixtureTargets([])
        statusNote?.wrappedValue = "Selection cleared"
    }

    /// Projects authoritative personality state onto physical identities for legacy
    /// definitions which predate explicit mappings. Policy remains in the mapper;
    /// the glyph and beam renderer only consume physical live state.
    private func physicalLiveEmitters(state: FixturePreviewState?, descriptor: FixtureVisualizationDescriptor, definition: FixtureDefinition) -> [FixtureElementPreviewState] {
        guard let state else { return [] }
        let source = state.physicalEmitters.isEmpty ? state.elements : state.physicalEmitters
        return descriptor.emitters.map { emitter in
            if let exact = source.first(where: { $0.elementID == emitter.id }) { return exact }
            let mapping = FixturePhysicalControlMapper.resolve(physicalEmitterID: emitter.id, descriptor: descriptor, definition: definition)
            switch mapping.disposition {
            case .controls(let controls):
                if let mapped = source.first(where: { controls.contains($0.elementID) }) {
                    return FixtureElementPreviewState(elementID: emitter.id, intensity: mapped.intensity, color: mapped.color)
                }
            case .wholeFixture:
                return FixtureElementPreviewState(elementID: emitter.id, intensity: state.intensity, color: state.color)
            case .inspectionOnly:
                break
            }
            return FixtureElementPreviewState(elementID: emitter.id)
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
            statusNote?.wrappedValue = prismReportCommandFailure(error, operation: "edit")
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
                        statusNote?.wrappedValue = prismReportCommandFailure(error, operation: "edit")
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
            statusNote?.wrappedValue = prismReportCommandFailure(
                error,
                operation: "commit stage layout",
                category: .uiStage
            )
        }
    }

    // MARK: - Camera

    public func fitStage(in size: CGSize) {
        let camera = StageCanvasCamera.fitStage(layout: layout, in: size)
        scale = camera.scale
        pan = camera.pan
        panAtDragStart = nil
    }

    private func zoomFromScroll(delta: CGFloat, anchor: CGPoint) {
        guard delta != 0 else { return }
        zoom(by: pow(1.008, delta), anchor: anchor)
    }

    private func zoom(by factor: CGFloat, anchor: CGPoint) {
        let result = StageCanvasCamera.zoom(
            scale: scale,
            pan: pan,
            factor: factor,
            anchor: anchor,
            viewportSize: canvasSize
        )
        scale = result.scale
        pan = result.pan
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

#if canImport(AppKit)
/// Passive AppKit bridge for modifier-scroll. The view never claims hit testing;
/// its local monitor only consumes Command-scroll events over this Stage surface.
private struct StageScrollZoomMonitor: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class MonitorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator {
        weak var view: MonitorView?
        var onScroll: (CGFloat, CGPoint) -> Void
        private var monitor: Any?

        init(onScroll: @escaping (CGFloat, CGPoint) -> Void) {
            self.onScroll = onScroll
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view, event.window === view.window,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
                else { return event }
                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
                self.onScroll(delta, location)
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
#endif

// MARK: - Space / Escape tracking (scoped to active Stage surface)

/// Tracks Space for Stage pan **only** when the pointer is over a Stage canvas
/// and text editing is not active. Never steals Space from text fields.
@MainActor
final class StageCanvasKeyState: ObservableObject {
    static let shared = StageCanvasKeyState()

    @Published private(set) var spaceHeld = false
    @Published private(set) var shiftHeld = false
    /// Escape press generation — canvas can observe to cancel drag.
    @Published private(set) var escapeTick: UInt64 = 0
    @Published private(set) var rotateStepTick: UInt64 = 0
    @Published private(set) var rotateExactTick: UInt64 = 0
    @Published private(set) var zoomInTick: UInt64 = 0
    @Published private(set) var zoomOutTick: UInt64 = 0

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
            shiftHeld = false
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let shift = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            if self.shiftHeld != shift {
                Task { @MainActor in self.shiftHeld = shift }
            }
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
            if event.type == .keyDown,
               !event.isARepeat,
               event.charactersIgnoringModifiers?.lowercased() == "r",
               self.stageOwnsNavigationKeys {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.shift), !flags.contains(.command) {
                    Task { @MainActor in self.rotateExactTick &+= 1 }
                    return nil
                }
                if flags.contains(.command) {
                    Task { @MainActor in self.rotateStepTick &+= 1 }
                    return nil
                }
            }
            if event.type == .keyDown, !event.isARepeat, self.stageOwnsNavigationKeys {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains([.command, .shift]) {
                    if event.keyCode == 24 { // + / =
                        Task { @MainActor in self.zoomInTick &+= 1 }
                        return nil
                    }
                    if event.keyCode == 27 { // - / _
                        Task { @MainActor in self.zoomOutTick &+= 1 }
                        return nil
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
    public static let minimumScale: CGFloat = 0.08
    public static let maximumScale: CGFloat = 6

    /// Changes zoom while preserving the world coordinate beneath `anchor`.
    public static func zoom(
        scale oldScale: CGFloat,
        pan oldPan: CGSize,
        factor: CGFloat,
        anchor: CGPoint,
        viewportSize: CGSize
    ) -> (scale: CGFloat, pan: CGSize) {
        let safeOld = max(minimumScale, oldScale)
        let newScale = min(maximumScale, max(minimumScale, safeOld * factor))
        let ratio = newScale / safeOld
        let offset = CGPoint(x: anchor.x - viewportSize.width / 2, y: anchor.y - viewportSize.height / 2)
        return (
            newScale,
            CGSize(
                width: offset.x - (offset.x - oldPan.width) * ratio,
                height: offset.y - (offset.y - oldPan.height) * ratio
            )
        )
    }

    public static func fitStage(layout: StageLayout, in size: CGSize) -> (scale: CGFloat, pan: CGSize) {
        guard size.width > 1, size.height > 1 else { return (1, .zero) }
        let bounds = contentBounds(layout: layout)
        let padding = max(50, min(120, max(bounds.width, bounds.height) * 0.10))
        let fittedWidth = bounds.width + padding * 2
        let fittedHeight = bounds.height + padding * 2
        let sx = size.width / max(fittedWidth, 1)
        let sy = size.height / max(fittedHeight, 1)
        let scale = min(sx, sy, 1.5) * 0.94
        let pan = CGSize(
            width: (layout.canvasWidth / 2 - bounds.midX) * scale,
            height: (layout.canvasHeight / 2 - bounds.midY) * scale
        )
        return (scale, pan)
    }

    /// Visible fixture and scenic bounds used by explicit Fit Stage actions.
    /// Falls back to the full canvas for a genuinely empty layout.
    public static func contentBounds(layout: StageLayout) -> CGRect {
        var bounds: CGRect?
        for fixture in layout.fixtures where !fixture.hidden {
            let extent = max(28 * fixture.scale, 20) + 18
            let rect = CGRect(
                x: fixture.x - extent / 2,
                y: fixture.y - extent / 2,
                width: extent,
                height: extent
            )
            bounds = bounds.map { $0.union(rect) } ?? rect
        }
        for object in layout.objects where !object.hidden {
            let halfW = object.width / 2
            let halfH = object.height / 2
            let c = abs(cos(object.rotation))
            let s = abs(sin(object.rotation))
            let rotatedHalfW = halfW * c + halfH * s
            let rotatedHalfH = halfW * s + halfH * c
            let rect = CGRect(
                x: object.x - rotatedHalfW,
                y: object.y - rotatedHalfH,
                width: rotatedHalfW * 2,
                height: rotatedHalfH * 2
            )
            bounds = bounds.map { $0.union(rect) } ?? rect
        }
        return bounds ?? CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
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
