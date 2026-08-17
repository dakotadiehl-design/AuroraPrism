import AuroraCore
import AuroraEngine
import AuroraModel
import SwiftUI

/// Build-mode Programmer — multi-fixture truthful state (UI-03 Pass 2).
public struct ProgrammerPanel: View {
    public var context: WorkspacePanelContext
    public var programmer: Programmer
    public var project: ShowProject
    public var presentation: ProgrammerAttributePresentation
    public var presentationRevision: UInt64
    public var onChanged: () -> Void

    @State private var activeFamily: AttributeFamily = .color
    @State private var fanCenter: Double = 0.5
    @State private var fanSpread: Double = 0.25
    @State private var showTechnicalColor = false
    @State private var showFanTools = false

    @State private var draftIntensity: Double = 0
    @State private var draftPan: Double = 0.5
    @State private var draftTilt: Double = 0.5
    @State private var draftHue: Double = 0.08
    @State private var draftSat: Double = 0.8
    @State private var draftVal: Double = 1
    @State private var draftRGB: [String: Double] = [:]
    @State private var draftExtended: [String: Double] = [:]
    @State private var showBeam = true
    @State private var showStrobe = true
    @State private var showGeneric = false

    public enum AttributeFamily: String, CaseIterable, Sendable {
        case intensity = "Intensity"
        case color = "Color"
        case position = "Position"
        case beam = "Beam"
        case effects = "Effects"
        // Legacy aliases used by fan/align tools
        case pan = "Pan"
        case tilt = "Tilt"
        case strobe = "Strobe"
        case generic = "Generic"

        /// Primary Color Engine tab bar (reference layout).
        public static var colorEngineTabs: [AttributeFamily] {
            [.color, .position, .beam, .effects]
        }
    }

    public init(
        context: WorkspacePanelContext,
        programmer: Programmer,
        project: ShowProject,
        presentation: ProgrammerAttributePresentation = .empty,
        presentationRevision: UInt64 = 0,
        onChanged: @escaping () -> Void = {}
    ) {
        self.context = context
        self.programmer = programmer
        self.project = project
        self.presentation = presentation
        self.presentationRevision = presentationRevision
        self.onChanged = onChanged
    }

    private var orderedIDs: [UUID] {
        let fromPres = presentation.orderedFixtureIDs
        if !fromPres.isEmpty { return fromPres }
        return context.session.selection.snapshot.orderedFixtureIDs
    }

    /// First-wins on duplicate fixture IDs (never traps on malformed project data).
    private var fixtureNames: [UUID: String] {
        var map: [UUID: String] = [:]
        map.reserveCapacity(project.fixtures.count)
        for fx in project.fixtures {
            if map[fx.id] == nil { map[fx.id] = fx.name }
        }
        return map
    }

    private var livePresentation: ProgrammerAttributePresentation {
        if presentation.selectionCount == orderedIDs.count, !orderedIDs.isEmpty {
            return presentation
        }
        return ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: orderedIDs,
            project: project,
            programmer: programmer.snapshot()
        )
    }

    public var body: some View {
        let pres = livePresentation
        Group {
            if orderedIDs.isEmpty {
                AuroraEmptyState(
                    title: "No selection",
                    detail: "Select fixtures on Stage Preview, in the browser, or via Groups.",
                    systemImage: "slider.horizontal.3"
                )
                .background(AuroraColor.surfacePanel)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    headerBar(pres)
                        .padding(.horizontal, AuroraSpacing.md)
                        .padding(.top, AuroraSpacing.sm)
                    familyTabBar(pres)
                        .padding(.horizontal, AuroraSpacing.md)
                        .padding(.vertical, 6)
                    Divider().background(AuroraColor.separator)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AuroraSpacing.md) {
                            familyBody(pres)
                            if showFanTools {
                                fanToolStrip
                            }
                        }
                        .padding(AuroraSpacing.md)
                    }
                }
                .background(AuroraColor.surfacePanel)
            }
        }
        .onAppear {
            syncDrafts(from: pres)
            selectAvailableFamily(in: pres)
        }
        .onChange(of: presentationRevision) { _, _ in
            syncDrafts(from: livePresentation)
            selectAvailableFamily(in: livePresentation)
        }
        .onChange(of: orderedIDs) { _, _ in
            syncDrafts(from: livePresentation)
            selectAvailableFamily(in: livePresentation)
        }
    }

    // MARK: - Header / order

    private func headerBar(_ pres: ProgrammerAttributePresentation) -> some View {
        HStack {
            Text("\(pres.selectionCount) fixtures")
                .font(AuroraTypography.sectionHeading)
                .foregroundStyle(AuroraColor.accentBright)
            Text(selectedNames)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(1)
            Spacer()
            Toggle("Blind", isOn: Binding(
                get: { programmer.snapshot().isBlind },
                set: { programmer.setBlind($0); onChanged() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            Toggle("HL", isOn: Binding(
                get: { programmer.snapshot().isHighlight },
                set: { programmer.setHighlight($0); onChanged() }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Highlight")
            shelfActions(pres)
        }
    }

    private func orderStrip(_ pres: ProgrammerAttributePresentation) -> some View {
        let names = fixtureNames
        let preview = pres.orderedFixtureIDs.prefix(12).enumerated().map { idx, id in
            "\(idx + 1).\(names[id] ?? "·")"
        }
        let extra = pres.selectionCount > 12 ? " … +\(pres.selectionCount - 12)" : ""
        return VStack(alignment: .leading, spacing: 2) {
            Text("ORDER (Fan phase)")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            Text(preview.joined(separator: " → ") + extra)
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(2)
        }
    }

    private var selectedNames: String {
        let names = fixtureNames
        let list = orderedIDs.prefix(4).compactMap { names[$0] }
        let extra = orderedIDs.count > 4 ? " +\(orderedIDs.count - 4)" : ""
        return list.joined(separator: ", ") + extra
    }

    // MARK: - Family tabs + body

    private func familyTabBar(_ pres: ProgrammerAttributePresentation) -> some View {
        HStack(spacing: 2) {
            ForEach(availableFamilyTabs(pres), id: \.self) { tab in
                let selected = activeTab == tab
                Button {
                    activeFamily = tab == .position ? .pan : tab
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(AuroraTypography.controlLabel)
                        .tracking(0.4)
                        .foregroundStyle(selected ? AuroraColor.accentBright : AuroraColor.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? AuroraColor.accentMuted : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func availableFamilyTabs(_ pres: ProgrammerAttributePresentation) -> [AttributeFamily] {
        AttributeFamily.colorEngineTabs.filter { tabEnabled($0, pres: pres) }
    }

    private func selectAvailableFamily(in pres: ProgrammerAttributePresentation) {
        let available = availableFamilyTabs(pres)
        guard !available.contains(activeTab), let first = available.first else { return }
        activeFamily = first
    }

    private var activeTab: AttributeFamily {
        switch activeFamily {
        case .pan, .tilt, .position: return .position
        case .strobe, .effects: return .effects
        case .generic: return .beam
        default: return activeFamily
        }
    }

    private func tabEnabled(_ tab: AttributeFamily, pres: ProgrammerAttributePresentation) -> Bool {
        switch tab {
        case .intensity: return pres.hasIntensity
        case .color: return pres.hasColor || pres.hasIntensity
        case .position: return pres.hasPosition
        case .beam: return pres.hasBeam
        case .effects: return pres.hasStrobe || pres.hasGeneric
        default: return true
        }
    }

    @ViewBuilder
    private func familyBody(_ pres: ProgrammerAttributePresentation) -> some View {
        switch activeTab {
        case .color:
            let colorPres = ProgrammerColorPresentationResolver.resolve(
                orderedFixtureIDs: orderedIDs,
                project: project,
                programmer: programmer.snapshot()
            )
            ProgrammerColorEngineView(
                color: colorPres,
                programmer: programmer,
                project: project,
                onChanged: onChanged
            )
            .frame(minHeight: 280)
            if pres.hasTechnicalColor {
                Button(showTechnicalColor ? "Hide Technical Channels" : "Technical Channels…") {
                    showTechnicalColor.toggle()
                }
                .font(AuroraTypography.metadata)
                .buttonStyle(AuroraButtonStyle(kind: .quiet))
                .foregroundStyle(AuroraColor.accentBright)
                if showTechnicalColor {
                    technicalColorSection(pres)
                }
            }
        case .intensity:
            HStack(alignment: .top, spacing: AuroraSpacing.lg) {
                if pres.hasIntensity {
                    intensityControl(pres.intensity)
                }
            }
        case .position:
            if pres.hasPosition {
                positionControls(pres)
            }
        case .beam:
            if pres.hasBeam {
                extendedFamilySection(
                    title: "BEAM",
                    attributes: pres.beamAttributes,
                    expanded: $showBeam,
                    family: .beam,
                    pres: pres
                )
            }
            if pres.hasGeneric {
                extendedFamilySection(
                    title: "GENERIC / RAW",
                    attributes: pres.genericAttributes,
                    expanded: $showGeneric,
                    family: .generic,
                    pres: pres
                )
            }
        case .effects:
            if pres.hasStrobe {
                extendedFamilySection(
                    title: "SHUTTER / STROBE",
                    attributes: pres.strobeAttributes,
                    expanded: $showStrobe,
                    family: .strobe,
                    pres: pres
                )
            }
            if pres.hasGeneric {
                extendedFamilySection(
                    title: "GENERIC / RAW",
                    attributes: pres.genericAttributes,
                    expanded: $showGeneric,
                    family: .generic,
                    pres: pres
                )
            }
        default:
            controlsRowLegacy(pres)
        }
    }

    /// Fallback combined row (legacy).
    private func controlsRowLegacy(_ pres: ProgrammerAttributePresentation) -> some View {
        HStack(alignment: .top, spacing: AuroraSpacing.lg) {
            if pres.hasIntensity {
                intensityControl(pres.intensity)
            }
            if pres.hasPosition {
                positionControls(pres)
            }
        }
    }

    private func intensityControl(_ state: ProgrammerAttributeState) -> some View {
        // Virtual intensity defaults to effective 100% when presentation reports .common(1.0).
        let untreated = state.displayValue ?? 0
        let display = displayValue(for: state, untreated: untreated)
        return VStack(spacing: 4) {
            attributeChrome(state, label: "Intensity")
            AuroraFader(
                value: Binding(
                    get: { draftIntensity },
                    set: { newValue in
                        draftIntensity = newValue
                        applyCommon(attribute: "intensity", value: newValue)
                        activeFamily = .intensity
                    }
                ),
                label: "Intensity",
                iconName: AuroraLightingIcon.intensity.rawValue,
                showsOwnedChrome: !state.isUntouched && !state.isMixed,
                display: display
            )
        }
    }

    private func positionControls(_ pres: ProgrammerAttributePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if pres.pan.isSupported {
                    attributeChrome(pres.pan, label: "Pan")
                }
                if pres.tilt.isSupported {
                    attributeChrome(pres.tilt, label: "Tilt")
                }
            }
            AuroraPositionPad(
                pan: Binding(
                    get: { draftPan },
                    set: { newValue in
                        draftPan = newValue
                        if pres.pan.isSupported {
                            applyCommon(attribute: "pan", value: newValue)
                            activeFamily = .pan
                        }
                    }
                ),
                tilt: Binding(
                    get: { draftTilt },
                    set: { newValue in
                        draftTilt = newValue
                        if pres.tilt.isSupported {
                            applyCommon(attribute: "tilt", value: newValue)
                            activeFamily = .tilt
                        }
                    }
                ),
                supportsPan: pres.pan.isSupported,
                supportsTilt: pres.tilt.isSupported,
                panDisplay: displayValue(for: pres.pan, untreated: 0.5),
                tiltDisplay: displayValue(for: pres.tilt, untreated: 0.5)
            )
        }
    }

    private func technicalColorSection(_ pres: ProgrammerAttributePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TECHNICAL COLOR")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack(spacing: 8) {
                ForEach(pres.technicalColorAttributes, id: \.self) { attr in
                    let state = attributeState(attr, in: pres)
                    VStack {
                        attributeChrome(state, label: shortColorLabel(attr))
                        AuroraFader(
                            value: Binding(
                                get: { draftRGB[attr] ?? state.displayValue ?? 0 },
                                set: { v in
                                    draftRGB[attr] = v
                                    applyCommon(attribute: attr, value: v)
                                    activeFamily = .color
                                }
                            ),
                            label: shortColorLabel(attr),
                            showsOwnedChrome: !state.isUntouched && !state.isMixed,
                            display: displayValue(for: state, untreated: 0)
                        )
                        .frame(width: AuroraMetrics.valueFaderWidth)
                    }
                }
            }
        }
    }

    private func extendedFamilySection(
        title: String,
        attributes: [String],
        expanded: Binding<Bool>,
        family: AttributeFamily,
        pres: ProgrammerAttributePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack {
                    Text(title)
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(AuroraColor.textTertiary)
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if expanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                        ForEach(attributes, id: \.self) { attr in
                            let state = pres.state(for: attr)
                            VStack(alignment: .leading, spacing: 3) {
                                AuroraFader(
                                    value: Binding(
                                        get: {
                                            draftExtended[attr]
                                                ?? state.displayValue
                                                ?? 0
                                        },
                                        set: { v in
                                            draftExtended[attr] = v
                                            applyCommon(attribute: attr, value: v)
                                            activeFamily = family
                                        }
                                    ),
                                    label: shortAttrLabel(attr),
                                    showsOwnedChrome: !state.isUntouched && !state.isMixed,
                                    display: displayValue(for: state, untreated: 0),
                                    axis: .horizontal
                                )
                                .frame(minWidth: 220, maxWidth: 420)
                            }
                        }
                }
            }
        }
    }

    private func shortAttrLabel(_ attr: String) -> String {
        if attr.count <= 8 { return attr }
        if attr.contains("@") {
            let parts = attr.split(separator: "@")
            let base = String(parts.first ?? Substring(attr))
            let cell = parts.count > 1 ? String(parts[1]) : ""
            return "\(base.prefix(4))@\(cell)"
        }
        return String(attr.prefix(8))
    }

    private var fanToolStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FAN — \(activeFamily.rawValue)  (center + spread)")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack {
                Text("Center")
                    .font(AuroraTypography.metadata)
                Slider(value: $fanCenter, in: 0...1)
                Text("\(Int(fanCenter * 100))%")
                    .font(AuroraTypography.metadata)
                    .frame(width: 36)
            }
            HStack {
                Text("Spread")
                    .font(AuroraTypography.metadata)
                Slider(value: $fanSpread, in: 0...0.5)
                Text("\(Int(fanSpread * 100))%")
                    .font(AuroraTypography.metadata)
                    .frame(width: 36)
            }
            HStack {
                ForEach([AttributeFamily.intensity, .pan, .tilt], id: \.self) { fam in
                    Button(fam.rawValue) { activeFamily = fam }
                        .controlSize(.mini)
                        .buttonStyle(AuroraButtonStyle(kind: .secondary))
                        .tint(activeFamily == fam ? AuroraColor.accent : nil)
                }
                Spacer()
                AuroraButton("Apply Fan", kind: .primary) {
                    applyFan()
                }
            }
        }
        .padding(8)
        .background(AuroraColor.surfaceWell)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func shelfActions(_ pres: ProgrammerAttributePresentation) -> some View {
        Menu {
            Button("Locate", systemImage: "scope") {
                    programmer.locate(fixtureIDs: Set(orderedIDs), project: project)
                    onChanged()
            }
            Button("Home", systemImage: "house") {
                    programmer.home(fixtureIDs: Set(orderedIDs), project: project)
                    onChanged()
            }
            Divider()
            Button(showFanTools ? "Hide Fan Controls" : "Show Fan Controls", systemImage: "arrow.left.and.right") {
                showFanTools.toggle()
                seedFanFromPresentation(pres)
            }
            Button("Align to First", systemImage: "align.horizontal.left") {
                applyAlignToFirst(pres)
            }
            .disabled(!canAlign(pres))
            Divider()
            Button("Clear Selected", systemImage: "eraser") {
                    programmer.clear(fixtureIDs: Set(orderedIDs))
                    onChanged()
            }
            Button(role: .destructive) {
                programmer.clearAll()
                onChanged()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AuroraColor.textSecondary)
            }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Programmer actions")
    }

    // MARK: - Chrome / display

    private func displayValue(for state: ProgrammerAttributeState, untreated: Double) -> AuroraControlDisplayValue {
        guard state.isSupported else { return .unavailable }
        if state.isMixed { return .mixed }
        if case .common(let v) = state.value { return .value(v) }
        return .value(untreated)
    }

    private func attributeChrome(_ state: ProgrammerAttributeState, label: String) -> some View {
        HStack(spacing: 4) {
            AuroraAttributeStateChrome(state: visualState(state))
            Text(label.uppercased())
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
            if state.support == .partial {
                Text("partial")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.warning)
            }
        }
    }

    private func colorFamilyChrome(_ pres: ProgrammerAttributePresentation) -> some View {
        let fam = ProgrammerColorFamilyVisual.resolve(from: pres)
        let chrome: AuroraAttributeVisualState = {
            switch fam {
            case .unavailable: return .unavailable
            case .untouched: return .untouched
            case .owned: return .programmerOwned
            case .mixed: return .mixed
            }
        }()
        return HStack(spacing: 4) {
            AuroraAttributeStateChrome(state: chrome)
            Text("COLOR")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
        }
    }

    private func visualState(_ state: ProgrammerAttributeState) -> AuroraAttributeVisualState {
        guard state.isSupported else { return .unavailable }
        switch state.value {
        case .untouched: return .untouched
        case .common: return .programmerOwned
        case .mixed: return .mixed
        }
    }

    // MARK: - Apply

    private func applyCommon(attribute: String, value: Double) {
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: attribute,
            orderedFixtureIDs: orderedIDs,
            project: project
        )
        let map = ProgrammerGeometry.align(fixtureIDs: capable, value: value)
        programmer.setMany(attribute: attribute, values: map)
        onChanged()
    }

    private func applyFan() {
        let attribute: String
        switch activeFamily {
        case .intensity: attribute = "intensity"
        case .pan, .position: attribute = "pan"
        case .tilt: attribute = "tilt"
        case .color: attribute = "intensity"
        case .beam: attribute = "zoom"
        case .strobe, .effects: attribute = "strobe"
        case .generic: attribute = "intensity"
        }
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: attribute,
            orderedFixtureIDs: orderedIDs,
            project: project
        )
        guard !capable.isEmpty else { return }
        let map = ProgrammerGeometry.fan(fixtureIDs: capable, center: fanCenter, spread: fanSpread)
        programmer.setMany(attribute: attribute, values: map)
        onChanged()
    }

    private func canAlign(_ pres: ProgrammerAttributePresentation) -> Bool {
        let attribute: String
        switch activeFamily {
        case .intensity: attribute = "intensity"
        case .pan, .position: attribute = "pan"
        case .tilt: attribute = "tilt"
        case .color: attribute = "colorR"
        case .beam: attribute = pres.beamAttributes.first ?? "zoom"
        case .strobe, .effects: attribute = pres.strobeAttributes.first ?? "strobe"
        case .generic: attribute = pres.genericAttributes.first ?? "intensity"
        }
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: attribute,
            orderedFixtureIDs: orderedIDs,
            project: project
        )
        guard let first = capable.first else { return false }
        return programmer.snapshot().values[first]?[attribute] != nil
    }

    private func applyAlignToFirst(_ pres: ProgrammerAttributePresentation) {
        switch activeFamily {
        case .color:
            var any = false
            for attr in ColorAuthoringAttribute.all + ["colorR", "colorG", "colorB", "colorW", "colorA", "colorUV"] {
                if alignAttribute(attr) { any = true }
            }
            if any { onChanged() }
        case .intensity:
            if alignAttribute("intensity") { onChanged() }
        case .pan, .position:
            if alignAttribute("pan") { onChanged() }
        case .tilt:
            if alignAttribute("tilt") { onChanged() }
        case .beam:
            var any = false
            for attr in pres.beamAttributes where alignAttribute(attr) { any = true }
            if any { onChanged() }
        case .strobe, .effects:
            var any = false
            for attr in pres.strobeAttributes where alignAttribute(attr) { any = true }
            if any { onChanged() }
        case .generic:
            var any = false
            for attr in pres.genericAttributes.prefix(8) where alignAttribute(attr) { any = true }
            if any { onChanged() }
        }
    }

    @discardableResult
    private func alignAttribute(_ attribute: String) -> Bool {
        let capable: [UUID]
        if ColorAuthoringAttribute.isAuthoring(attribute) {
            capable = ProgrammerColorPresentationResolver.rgbCapableIDs(
                orderedFixtureIDs: orderedIDs,
                project: project
            )
        } else {
            capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
                attribute: attribute,
                orderedFixtureIDs: orderedIDs,
                project: project
            )
        }
        let snap = programmer.snapshot()
        var values: [UUID: Double] = [:]
        for id in capable {
            if let v = snap.values[id]?[attribute] {
                values[id] = v
            }
        }
        guard let map = ProgrammerGeometry.alignToFirst(fixtureIDs: capable, values: values) else {
            return false
        }
        programmer.setMany(attribute: attribute, values: map)
        return true
    }

    private func seedFanFromPresentation(_ pres: ProgrammerAttributePresentation) {
        let state: ProgrammerAttributeState
        switch activeFamily {
        case .intensity: state = pres.intensity
        case .pan, .position: state = pres.pan
        case .tilt: state = pres.tilt
        case .color: state = pres.intensity
        case .beam:
            state = pres.beamAttributes.first.map { pres.state(for: $0) } ?? .unsupported
        case .strobe, .effects:
            state = pres.strobeAttributes.first.map { pres.state(for: $0) } ?? .unsupported
        case .generic:
            state = pres.genericAttributes.first.map { pres.state(for: $0) } ?? .unsupported
        }
        if case .common(let v) = state.value {
            fanCenter = v
            fanSpread = 0.2
        } else if case .mixed = state.value {
            // keep user center/spread
        } else {
            fanCenter = 0.5
            fanSpread = 0.25
        }
    }

    private func syncDrafts(from pres: ProgrammerAttributePresentation) {
        if case .common(let v) = pres.intensity.value {
            // Includes virtual intensity effective default 1.0
            draftIntensity = v
        } else if case .untouched = pres.intensity.value {
            draftIntensity = 0
        }

        if case .common(let v) = pres.pan.value {
            draftPan = v
        } else if case .untouched = pres.pan.value {
            draftPan = 0.5
        }

        if case .common(let v) = pres.tilt.value {
            draftTilt = v
        } else if case .untouched = pres.tilt.value {
            draftTilt = 0.5
        }

        for attr in pres.technicalColorAttributes {
            let st = attributeState(attr, in: pres)
            if case .common(let v) = st.value {
                draftRGB[attr] = v
            }
        }
        for attr in pres.beamAttributes + pres.strobeAttributes + pres.genericAttributes {
            if case .common(let v) = pres.state(for: attr).value {
                draftExtended[attr] = v
            }
        }
        if case .common(let r) = pres.colorR.value,
           case .common(let g) = pres.colorG.value,
           case .common(let b) = pres.colorB.value {
            let hsv = ColorMath.hsv(from: RGBColor(r: r, g: g, b: b))
            draftHue = hsv.h / 360
            draftSat = hsv.s
            draftVal = hsv.v
        }
    }

    private func attributeState(_ attr: String, in pres: ProgrammerAttributePresentation) -> ProgrammerAttributeState {
        pres.state(for: attr)
    }

    private func shortColorLabel(_ attr: String) -> String {
        switch attr {
        case "colorR": return "R"
        case "colorG": return "G"
        case "colorB": return "B"
        case "colorW": return "W"
        case "colorCoolWhite": return "CW"
        case "colorWarmWhite": return "WW"
        case "colorA": return "A"
        case "colorUV": return "UV"
        case "colorLime": return "Li"
        case "colorCyan": return "Cy"
        case "cyan": return "C"
        case "magenta": return "M"
        case "yellow": return "Y"
        default: return attr
        }
    }
}
