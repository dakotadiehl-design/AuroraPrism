import AuroraModel
import AuroraUI
import Foundation

/// What the Inspector is currently presenting (UI-02B).
/// Independent of Programmer fixture selection so cues/groups can be inspected without clearing fixtures.
enum InspectorFocus: Equatable, Sendable {
    case project
    case fixtures
    case multiFixtures
    case group(UUID)
    case cue(UUID)
    case palette(UUID)
    case preset(UUID)
    case song(UUID)
}

/// Primary Build destinations (Checkpoint A shell → C2 DESIGN integration).
/// `program` case is the DESIGN creative workspace (display label: Design).
enum BuildWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case program = "Program"
    case patch = "Patch"
    case stage = "Stage"
    case profiles = "Profiles"
    var id: String { rawValue }

    /// Mode bar / menu label (C2: Program surfaces as Design).
    var displayName: String {
        switch self {
        case .program: return "Design"
        case .patch: return "Patch"
        case .stage: return "Stage"
        case .profiles: return "Profiles"
        }
    }
}

/// Simple DESIGN layout focus presets (C2 — not a full docking system).
enum DesignFocusPreset: String, CaseIterable, Identifiable, Sendable {
    case balanced = "Balanced"
    case programmerFocus = "Programmer Focus"
    case previewFocus = "Preview Focus"
    case cueFocus = "Cue Focus"
    var id: String { rawValue }
}

/// Left-column tools **within Program mode** (Browser / Groups only).
/// Profiles is a top-level Build mode, not a left tab.
enum BuildLeftTool: String, CaseIterable, Identifiable, Sendable {
    case browser = "Browser"
    case groups = "Groups"
    var id: String { rawValue }

    var layoutPanelID: WorkspacePanelID {
        switch self {
        case .browser: return .fixtureBrowser
        case .groups: return .groups
        }
    }

    /// Tools shown in Program left rail.
    static var programTools: [BuildLeftTool] { [.browser, .groups] }

    static func fromLayoutTab(_ id: WorkspacePanelID) -> BuildLeftTool {
        switch id {
        case .groups: return .groups
        default: return .browser
        }
    }
}

/// Lower region tools (UI-02E Option A + Diagnostics).
enum BuildLowerTool: String, CaseIterable, Identifiable, Sendable {
    case cueBlocks = "Cue Blocks"
    case palettes = "Palettes"
    case cues = "Cues"
    case song = "Song"
    case diagnostics = "Diagnostics"
    var id: String { rawValue }

    var layoutPanelID: WorkspacePanelID {
        switch self {
        case .cueBlocks: return .cueBlocks
        case .palettes: return .palettes
        case .cues: return .cueList
        case .song: return .song
        case .diagnostics: return .console
        }
    }

    static func fromLayoutTab(_ id: WorkspacePanelID) -> BuildLowerTool {
        switch id {
        case .cueBlocks: return .cueBlocks
        case .palettes: return .palettes
        case .song: return .song
        case .console, .universeMonitor: return .diagnostics
        default: return .cues
        }
    }
}

/// Build/Perform mode, panel layout, and UI-only workspace state (Stage C / UI-02).
@MainActor
final class WorkspaceController: ObservableObject {
    @Published var layout: WorkspaceLayout
    /// C5: docked / floating / hidden presentation for detachable surfaces.
    @Published var floatState: WorkspaceFloatState
    @Published private(set) var screenMode: WorkspaceScreenMode
    @Published var mode: WorkspaceMode = .build
    /// Explicit Welcome vs empty document (DOC-01). Not inferred from fixture/cue counts.
    @Published var showsWelcomeScreen: Bool = true
    /// Explicit Inspector context — not a hidden priority over selection sets.
    @Published var inspectorFocus: InspectorFocus = .project
    /// DESIGN | PATCH | STAGE | PROFILES — first-class Build destinations.
    @Published var buildWorkspaceMode: BuildWorkspaceMode = .program
    @Published var leftTool: BuildLeftTool = .browser
    @Published var lowerTool: BuildLowerTool = .cues
    /// One-shot Reveal on Stage target (cleared by consumer after pan).
    @Published var stageRevealFixtureID: UUID?
    /// Bumps when the document is replaced so panel `@State` can self-heal (UI-02 B2/B3).
    @Published private(set) var documentEpoch: Int = 0
    /// Last applied DESIGN focus preset (session UI; layout fractions are authoritative).
    @Published var designFocusPreset: DesignFocusPreset = .balanced
    /// C3: in-place Stage geometry editing on the DESIGN canvas (not a separate workspace).
    @Published var stageEditActive: Bool = false

    /// C5.1: shared Stage camera across docked + floating DESIGN Stage hosts.
    @Published var designPreviewScale: CGFloat = 1
    @Published var designPreviewPan: CGSize = .zero

    /// Generation token so floating windows re-open when state reloads.
    @Published private(set) var floatEpoch: UInt64 = 0

    /// Explicit Reveal on Stage (C2/C3) — DESIGN workspace, expand preview, pan to fixture.
    /// Does not force Edit Stage (reveal is a programming/navigation action).
    func revealOnStage(fixtureID: UUID) {
        buildWorkspaceMode = .program
        if layout.stagePreviewCollapsed {
            layout.stagePreviewCollapsed = false
            WorkspaceLayoutStore.saveDebounced(layout)
        }
        stageRevealFixtureID = fixtureID
        objectWillChange.send()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.stageRevealFixtureID = nil
        }
    }

    /// Enter Edit Stage on DESIGN — geometry tools + Unplaced rail; same Stage model.
    func enterEditStage() {
        buildWorkspaceMode = .program
        stageEditActive = true
        if layout.stagePreviewCollapsed {
            layout.stagePreviewCollapsed = false
        }
        // Give the plot room while arranging.
        if layout.designPreviewFraction < 0.55 {
            layout.designPreviewFraction = 0.58
        }
        layout.clampToSafeGeometry()
        WorkspaceLayoutStore.saveDebounced(layout)
        objectWillChange.send()
    }

    func exitEditStage() {
        guard stageEditActive else { return }
        stageEditActive = false
        objectWillChange.send()
    }

    func toggleEditStage() {
        if stageEditActive {
            exitEditStage()
        } else {
            enterEditStage()
        }
    }

    /// Toggle Stage Preview collapse in DESIGN (View menu / chrome).
    func toggleStagePreviewCollapsed() {
        layout.stagePreviewCollapsed.toggle()
        if !layout.stagePreviewCollapsed {
            designFocusPreset = .balanced
        } else {
            designFocusPreset = .programmerFocus
        }
        WorkspaceLayoutStore.saveDebounced(layout)
        objectWillChange.send()
    }

    func setStagePreviewCollapsed(_ collapsed: Bool) {
        layout.stagePreviewCollapsed = collapsed
        WorkspaceLayoutStore.saveDebounced(layout)
        objectWillChange.send()
    }

    /// Apply a simple DESIGN focus preset (split states only — no show data change).
    func applyDesignFocus(_ preset: DesignFocusPreset) {
        designFocusPreset = preset
        switch preset {
        case .balanced:
            layout.stagePreviewCollapsed = false
            layout.lowerShelfCollapsed = false
            layout.designPreviewFraction = 0.52
            layout.bottomFraction = 0.26
            ensureLowerVisible(true)
        case .programmerFocus:
            layout.stagePreviewCollapsed = true
            layout.lowerShelfCollapsed = true
            layout.designPreviewFraction = 0.28
            // Preserve bottomFraction for expand restore
            ensureLowerVisible(true)
        case .previewFocus:
            layout.stagePreviewCollapsed = false
            layout.lowerShelfCollapsed = true
            layout.designPreviewFraction = 0.72
            ensureLowerVisible(true)
        case .cueFocus:
            layout.stagePreviewCollapsed = false
            layout.lowerShelfCollapsed = false
            layout.designPreviewFraction = 0.38
            layout.bottomFraction = 0.40
            ensureLowerVisible(true)
            lowerTool = .cues
            layout.bottomTab = .cueList
        }
        layout.clampToSafeGeometry()
        WorkspaceLayoutStore.save(layout)
        objectWillChange.send()
    }

    func toggleLowerShelfCollapsed() {
        layout.lowerShelfCollapsed.toggle()
        WorkspaceLayoutStore.saveDebounced(layout)
        objectWillChange.send()
    }

    func setLowerShelfCollapsed(_ collapsed: Bool) {
        layout.lowerShelfCollapsed = collapsed
        WorkspaceLayoutStore.saveDebounced(layout)
        objectWillChange.send()
    }

    private func ensureLowerVisible(_ visible: Bool) {
        if visible {
            if !layout.isVisible(.cueList)
                && !layout.isVisible(.cueBlocks)
                && !layout.isVisible(.palettes)
                && !layout.isVisible(.song)
                && !layout.isVisible(.console)
            {
                layout.visiblePanels.insert(.cueList)
            }
        }
    }

    func updateDesignPreviewFraction(_ value: Double, immediate: Bool = false) {
        layout.designPreviewFraction = value
        layout.clampToSafeGeometry()
        if immediate {
            WorkspaceLayoutStore.save(layout)
        } else {
            WorkspaceLayoutStore.saveDebounced(layout)
        }
        objectWillChange.send()
    }

    init(
        layout: WorkspaceLayout = WorkspaceLayoutStore.load(),
        floatState: WorkspaceFloatState? = nil
    ) {
        self.layout = layout
        // Load on MainActor inside init (default args are nonisolated).
        let screenMode = WorkspaceScreenModeStore.load()
        var resolvedFloatState = floatState ?? WorkspaceFloatStore.load()
        // Explicit state is used by previews/tests and should remain deterministic.
        // Launch-loaded state obeys the user's screen-mode preference.
        if floatState == nil, screenMode == .single {
            resolvedFloatState.dockAll()
        }
        self.floatState = resolvedFloatState
        self.screenMode = screenMode
        // Align tools from persisted layout (UI-11).
        self.leftTool = BuildLeftTool.fromLayoutTab(layout.leadingTab)
        self.lowerTool = BuildLowerTool.fromLayoutTab(layout.bottomTab)
    }

    // MARK: - C5 float / undock

    func setScreenMode(_ mode: WorkspaceScreenMode) {
        guard screenMode != mode else { return }
        screenMode = mode
        WorkspaceScreenModeStore.save(mode)
        objectWillChange.send()
    }

    func isFloating(_ surface: FloatSurfaceID) -> Bool {
        floatState.isFloating(surface)
    }

    func showsInMainWindow(_ surface: FloatSurfaceID) -> Bool {
        floatState.showsInMainWindow(surface)
    }

    /// Undock surface into a real macOS window (C5D). Caller should open the WindowGroup.
    func undock(
        _ surface: FloatSurfaceID,
        frame: CGRect? = nil,
        screenID: String? = nil,
        screenName: String? = nil
    ) {
        // Never float a hidden surface into a live window without an explicit undock.
        let defaultFrame = frame ?? CGRect(origin: .zero, size: surface.defaultSize)
        floatState.float(surface, frame: defaultFrame, screenID: screenID, screenName: screenName)
        floatEpoch &+= 1
        WorkspaceFloatStore.save(floatState)
        objectWillChange.send()
    }

    /// Redock floating surface into the main BUILD shell (C5D). Closing a float window redocks.
    /// Callers that own windows must also close the exact registered NSWindow (C5.1).
    func redock(_ surface: FloatSurfaceID) {
        guard floatState.isFloating(surface) else { return }
        floatState.dock(surface)
        floatEpoch &+= 1
        WorkspaceFloatStore.save(floatState)
        objectWillChange.send()
    }

    func updateFloatingFrame(
        _ surface: FloatSurfaceID,
        frame: CGRect,
        screenID: String?,
        screenName: String? = nil
    ) {
        var rec = floatState.record(for: surface)
        guard rec.kind == .floating else { return }
        rec.setFrame(frame)
        if let screenID { rec.screenID = screenID }
        if let screenName { rec.screenName = screenName }
        floatState.setRecord(rec, for: surface)
        WorkspaceFloatStore.saveDebounced(floatState)
    }

    /// C5E / C5.1: clamp saved frames onto currently available **visible** display frames.
    func recoverFloatingWindows(to screens: [ScreenVisibleRecord]) {
        if floatState.recoverFrames(to: screens) {
            WorkspaceFloatStore.save(floatState)
            floatEpoch &+= 1
            objectWillChange.send()
        }
    }

    /// Convenience when only CGRects are available (tests / legacy).
    func recoverFloatingWindows(to screenFrames: [CGRect]) {
        recoverFloatingWindows(to: screenFrames.enumerated().map {
            ScreenVisibleRecord(id: "screen-\($0.offset)", visibleFrame: $0.element)
        })
    }

    func flushFloatPersistence() {
        WorkspaceFloatStore.flushPending()
        WorkspaceFloatStore.save(floatState)
    }

    func setBuildWorkspaceMode(_ mode: BuildWorkspaceMode) {
        // C3: STAGE top-level is a transitional alias → DESIGN + Edit Stage (one canvas, one model).
        if mode == .stage {
            enterEditStage()
            return
        }
        if mode != .program {
            stageEditActive = false
        }
        buildWorkspaceMode = mode
        if mode == .program, !BuildLeftTool.programTools.contains(leftTool) {
            leftTool = .browser
        }
        objectWillChange.send()
    }

    /// Lower Cue/Palette/Song/Diagnostics: DESIGN multi-panel only by default.
    /// Patch/Stage hide lower chrome so the canvas owns vertical space (Checkpoint A).
    var showsLowerRegionInCurrentBuildMode: Bool {
        buildWorkspaceMode == .program
    }

    /// DESIGN Stage Preview is shown unless user collapsed it.
    var showsDesignStagePreview: Bool {
        buildWorkspaceMode == .program && !layout.stagePreviewCollapsed
    }

    /// Dismiss Welcome after New / Open / Demo (DOC-01).
    func enterDocumentWorkspace() {
        showsWelcomeScreen = false
        mode = .build
        objectWillChange.send()
    }

    func returnToWelcome() {
        showsWelcomeScreen = true
        mode = .build
        objectWillChange.send()
    }

    func togglePanel(_ id: WorkspacePanelID) {
        layout.toggle(id)
        WorkspaceLayoutStore.save(layout)
    }

    /// UI-11: apply named Build layout preset (not used for Perform — fixed shell A9).
    func applyNamedBuildLayout(_ name: String) {
        layout = WorkspaceLayout.namedBuildPreset(name)
        leftTool = BuildLeftTool.fromLayoutTab(layout.leadingTab)
        lowerTool = BuildLowerTool.fromLayoutTab(layout.bottomTab)
        WorkspaceLayoutStore.save(layout)
        objectWillChange.send()
    }

    func resetLayout() {
        layout = .default
        leftTool = .browser
        lowerTool = .cues
        WorkspaceLayoutStore.save(layout)
        objectWillChange.send()
    }

    /// Flush debounced layout persistence (UI11-05).
    func flushLayoutPersistence() {
        WorkspaceLayoutStore.flushPending()
        WorkspaceLayoutStore.save(layout)
        flushFloatPersistence()
    }

    func updateSplitFractions(leading: Double? = nil, trailing: Double? = nil, bottom: Double? = nil, immediate: Bool = false) {
        if let leading { layout.leadingFraction = leading }
        if let trailing { layout.trailingFraction = trailing }
        if let bottom { layout.bottomFraction = bottom }
        layout.clampToSafeGeometry()
        if immediate {
            WorkspaceLayoutStore.save(layout)
        } else {
            WorkspaceLayoutStore.saveDebounced(layout)
        }
    }

    func setMode(_ mode: WorkspaceMode) {
        self.mode = mode
    }

    func isVisible(_ id: WorkspacePanelID) -> Bool {
        layout.isVisible(id)
    }

    func setInspectorFocus(_ focus: InspectorFocus) {
        inspectorFocus = focus
    }

    func setLeftTool(_ tool: BuildLeftTool) {
        leftTool = tool
        layout.leadingTab = tool.layoutPanelID
        WorkspaceLayoutStore.saveDebounced(layout)
    }

    func setLowerTool(_ tool: BuildLowerTool) {
        lowerTool = tool
        layout.bottomTab = tool.layoutPanelID
        WorkspaceLayoutStore.saveDebounced(layout)
    }

    /// Programmatic fixture selection change — may keep sticky non-fixture Inspector focus.
    func noteFixtureSelectionChanged(count: Int) {
        switch inspectorFocus {
        case .cue, .group, .palette, .preset, .song:
            break
        default:
            applyFixtureFocus(count: count)
        }
    }

    /// User explicitly clicked fixtures for inspection.
    func noteExplicitFixtureInspect(count: Int) {
        applyFixtureFocus(count: count)
    }

    /// User explicitly clicked a group row for inspection.
    func noteExplicitGroupInspect(id: UUID) {
        inspectorFocus = .group(id)
    }

    private func applyFixtureFocus(count: Int) {
        if count == 0 {
            inspectorFocus = .project
        } else if count == 1 {
            inspectorFocus = .fixtures
        } else {
            inspectorFocus = .multiFixtures
        }
    }

    /// Reset document-scoped UI after New/Open/Demo (UI-02 B2 / LAYOUT-04 Option A).
    /// Does **not** change Build/Perform mode, layout fractions, or tool tabs —
    /// layout is an application preference that persists across document replacement.
    func didReplaceDocument(project: ShowProject) {
        inspectorFocus = .project
        // Keep leftTool/lowerTool aligned with persisted layout (do not reset to browser/cues).
        leftTool = BuildLeftTool.fromLayoutTab(layout.leadingTab)
        lowerTool = BuildLowerTool.fromLayoutTab(layout.bottomTab)
        documentEpoch &+= 1
        _ = project
    }
}
