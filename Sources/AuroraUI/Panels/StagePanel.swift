import AuroraDesignSystem
import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Stage destination host — composes Unplaced rail + edit chrome around shared `StageCanvasView` (C1).
public struct StagePanel: View {
    public var context: WorkspacePanelContext
    public var preview: StagePreviewSnapshot
    public var onLayoutChanged: () -> Void
    public var onSelectFixtures: ([UUID]) -> Void
    public var revealFixtureID: UUID?
    public var glyphStyle: StageGlyphStyle

    @State private var mode: Mode = .live
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var rotationDegrees: Double = 0
    @State private var leftRail: LeftRail = .unplaced
    @State private var statusNote: String?

    public enum Mode: String, CaseIterable {
        case edit = "Edit"
        case live = "Live"
    }

    private enum LeftRail: String, CaseIterable {
        case unplaced = "Unplaced"
        case onStage = "On Stage"
    }

    public init(
        context: WorkspacePanelContext,
        preview: StagePreviewSnapshot,
        onLayoutChanged: @escaping () -> Void,
        onSelectFixtures: @escaping ([UUID]) -> Void,
        revealFixtureID: UUID? = nil,
        glyphStyle: StageGlyphStyle = .legacyV1
    ) {
        self.context = context
        self.preview = preview
        self.onLayoutChanged = onLayoutChanged
        self.onSelectFixtures = onSelectFixtures
        self.revealFixtureID = revealFixtureID
        self.glyphStyle = glyphStyle
    }

    private var layout: StageLayout { context.project.stageLayout }

    private var selectedIDs: Set<UUID> {
        context.session.selection.snapshot.fixtureIDs
    }

    private var placedIDs: Set<UUID> {
        Set(layout.fixtures.map(\.fixtureID))
    }

    private var unplacedFixtures: [PatchedFixture] {
        context.project.fixtures.filter { !placedIDs.contains($0.id) }
    }

    private var onStageFixtures: [PatchedFixture] {
        context.project.fixtures.filter { placedIDs.contains($0.id) }
    }

    private var interactionMode: StageInteractionMode {
        mode == .edit ? .editGeometry : .programSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            stageFixtureRail
                .frame(width: 168)
            Divider().overlay(AuroraColor.separator)
            VStack(spacing: 0) {
                toolbar
                if mode == .edit {
                    editTools
                }
                StageCanvasView(
                    context: context,
                    preview: preview,
                    interactionMode: interactionMode,
                    geometryEditingEnabled: mode == .edit,
                    selectedIDs: selectedIDs,
                    selectedTargets: context.session.selection.snapshot.fixtureTargets,
                    orderedSelectedTargets: context.session.selection.snapshot.orderedFixtureTargets,
                    glyphStyle: glyphStyle,
                    scale: $scale,
                    pan: $pan,
                    onSelectFixtures: onSelectFixtures,
                    onSelectFixtureTargets: { targets in
                        context.session.selectFixtureTargetsOrdered(targets, extending: false)
                    },
                    onLayoutChanged: onLayoutChanged,
                    revealFixtureID: revealFixtureID,
                    statusNote: $statusNote
                )
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                canvasSize = geo.size
                                let cam = StageCanvasCamera.fitStage(layout: layout, in: geo.size)
                                scale = cam.scale
                                pan = cam.pan
                            }
                            .onChange(of: geo.size) { _, size in canvasSize = size }
                    }
                )
                statusBar
            }
        }
    }

    // MARK: - Unplaced / On Stage rail

    private var stageFixtureRail: some View {
        VStack(spacing: 0) {
            Picker("", selection: $leftRail) {
                ForEach(LeftRail.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)
            if leftRail == .unplaced {
                HStack {
                    Text("\(unplacedFixtures.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Place All") { placeAllUnplaced() }
                        .controlSize(.mini)
                        .disabled(unplacedFixtures.isEmpty)
                }
                .padding(.horizontal, 8)
            }
            List {
                if leftRail == .unplaced {
                    if unplacedFixtures.isEmpty {
                        Text("All fixtures placed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unplacedFixtures) { fx in
                            Text(fx.name)
                                .font(.callout)
                                .onTapGesture {
                                    onSelectFixtures([fx.id])
                                }
                                .onDrag {
                                    NSItemProvider(object: fx.id.uuidString as NSString)
                                }
                        }
                    }
                } else {
                    ForEach(onStageFixtures) { fx in
                        Text(fx.name)
                            .font(.callout)
                            .onTapGesture {
                                onSelectFixtures([fx.id])
                            }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(AuroraColor.surfacePanel)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)

            Menu("Fit") {
                Button("Fit Stage") {
                    let cam = StageCanvasCamera.fitStage(layout: layout, in: canvasSize)
                    scale = cam.scale
                    pan = cam.pan
                }
                Button("Fit Selection") {
                    if let cam = StageCanvasCamera.fitSelection(
                        placements: layout.fixtures,
                        selectedIDs: selectedIDs,
                        in: canvasSize
                    ) {
                        scale = cam.scale
                        pan = cam.pan
                    }
                }
                .disabled(selectedIDs.isEmpty)
                Button("100%") { scale = 1; pan = .zero }
            }
            .controlSize(.small)

            HStack(spacing: 4) {
                Button { scale = max(0.2, scale * 0.85) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .controlSize(.small)
                Text("\(Int(scale * 100))%")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 36)
                    .foregroundStyle(.secondary)
                Button { scale = min(4, scale * 1.15) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .controlSize(.small)
            }
            .buttonStyle(AuroraButtonStyle(kind: .quiet))

            if !selectedIDs.isEmpty {
                Button("Reveal") {
                    if let id = selectedIDs.first {
                        if let place = layout.fixtures.first(where: { $0.fixtureID == id }) {
                            scale = max(scale, 1.2)
                            pan = CGSize(
                                width: canvasSize.width / 2 - CGFloat(place.x) * scale,
                                height: canvasSize.height / 2 - CGFloat(place.y) * scale
                            )
                            onSelectFixtures([id])
                            statusNote = "Revealed on Stage"
                        } else {
                            statusNote = "Fixture not on Stage"
                        }
                    }
                }
                .controlSize(.small)
            }

            if mode == .edit {
                Menu("Align") {
                    Button("Left") { align(.left) }
                    Button("Center X") { align(.centerX) }
                    Button("Right") { align(.right) }
                    Button("Top") { align(.top) }
                    Button("Bottom") { align(.bottom) }
                }
                .controlSize(.small)
                .disabled(selectedIDs.count < 2)

                Menu("Distribute") {
                    Button("Horizontally") { distribute(horizontal: true) }
                    Button("Vertically") { distribute(horizontal: false) }
                }
                .controlSize(.small)
                .disabled(selectedIDs.count < 3)

                Menu("Add") {
                    Button("Stage Area") { addStageArea() }
                    Button("Rectangle") { addScenicRect() }
                    Button("Truss") { addTruss() }
                }
                .controlSize(.small)

                if !selectedIDs.isEmpty {
                    Button("Remove From Stage", role: .destructive) { removeFromStage() }
                        .controlSize(.small)
                }
            }

            if preview.freeze {
                Text("FROZEN").font(.caption.weight(.bold)).foregroundStyle(.orange)
            }
            if preview.blackout {
                Text("BLACKOUT").font(.caption.weight(.bold)).foregroundStyle(.red)
            }
            Spacer()
            Text("Master \(Int(preview.masterIntensity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var editTools: some View {
        Group {
            if mode == .edit, !selectedIDs.isEmpty {
                HStack(spacing: 8) {
                    Text("Rotation")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $rotationDegrees, in: -180...180) { editing in
                        if !editing { applyRotation() }
                    }
                    .frame(maxWidth: 160)
                    Text("\(Int(rotationDegrees))°")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Layout ops (edit chrome)

    private enum AlignEdge { case left, right, top, bottom, centerX }

    private func align(_ edge: AlignEdge) {
        guard selectedIDs.count >= 2 else { return }
        var layout = context.project.stageLayout
        let places = layout.fixtures.filter { selectedIDs.contains($0.fixtureID) && !$0.locked }
        guard !places.isEmpty else { return }
        switch edge {
        case .left:
            let v = places.map(\.x).min() ?? 0
            for i in layout.fixtures.indices where selectedIDs.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].x = v
            }
        case .right:
            let v = places.map(\.x).max() ?? 0
            for i in layout.fixtures.indices where selectedIDs.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].x = v
            }
        case .top:
            let v = places.map(\.y).min() ?? 0
            for i in layout.fixtures.indices where selectedIDs.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].y = v
            }
        case .bottom:
            let v = places.map(\.y).max() ?? 0
            for i in layout.fixtures.indices where selectedIDs.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].y = v
            }
        case .centerX:
            let v = places.map(\.x).reduce(0, +) / Double(places.count)
            for i in layout.fixtures.indices where selectedIDs.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
                layout.fixtures[i].x = v
            }
        }
        commitLayout(layout)
    }

    private func distribute(horizontal: Bool) {
        guard selectedIDs.count >= 3 else { return }
        var layout = context.project.stageLayout
        var places = layout.fixtures.filter { selectedIDs.contains($0.fixtureID) && !$0.locked }
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
        commitLayout(layout)
    }

    private func applyRotation() {
        guard !selectedIDs.isEmpty else { return }
        var layout = context.project.stageLayout
        let rad = rotationDegrees * .pi / 180
        for i in layout.fixtures.indices where selectedIDs.contains(layout.fixtures[i].fixtureID) && !layout.fixtures[i].locked {
            layout.fixtures[i].rotation = rad
        }
        commitLayout(layout)
    }

    private func placeAllUnplaced() {
        do {
            try context.session.perform(PlaceAllUnplacedCommand())
            statusNote = "Placed all unplaced fixtures"
            onLayoutChanged()
        } catch {
            statusNote = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func removeFromStage(ids: [UUID]? = nil) {
        let targets = ids ?? Array(selectedIDs)
        do {
            try context.session.perform(RemoveFromStageCommand(fixtureIDs: targets))
            statusNote = "Removed from Stage (still patched)"
            onLayoutChanged()
        } catch {
            statusNote = prismReportCommandFailure(error, operation: "edit")
        }
    }

    private func addStageArea() {
        var layout = context.project.stageLayout
        layout.scenic.append(StageScenicObject(
            kind: .stageArea,
            name: "Stage",
            x: layout.canvasWidth / 2,
            y: layout.canvasHeight * 0.72,
            width: 480,
            height: 160
        ))
        commitLayout(layout)
    }

    private func addScenicRect() {
        var layout = context.project.stageLayout
        layout.scenic.append(StageScenicObject(
            kind: .rectangle,
            name: "Scenic",
            x: layout.canvasWidth / 2,
            y: layout.canvasHeight / 2,
            width: 120,
            height: 40
        ))
        commitLayout(layout)
    }

    private func addTruss() {
        var layout = context.project.stageLayout
        layout.scenic.append(StageScenicObject(
            kind: .truss,
            name: "Truss",
            x: layout.canvasWidth / 2,
            y: layout.canvasHeight * 0.28,
            width: 400,
            height: 8
        ))
        commitLayout(layout)
    }

    private func commitLayout(_ layout: StageLayout) {
        do {
            try context.session.perform(UpdateStageLayoutCommand(layout: layout))
            onLayoutChanged()
        } catch {
            statusNote = prismReportCommandFailure(error, operation: "commit stage layout", category: .uiStage)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(mode == .edit
                 ? "Edit — drag · marquee · place from Unplaced · Remove From Stage ≠ delete"
                 : "Live — select & program · geometry locked · pan/zoom/reveal")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let statusNote {
                Text("· \(statusNote)")
                    .font(.caption)
                    .foregroundStyle(AuroraColor.accentBright)
            }
            Spacer()
            Text("\(selectedIDs.count) sel · \(unplacedFixtures.count) unplaced · \(preview.fixtures.count) live · canvas shared")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(6)
    }
}
