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

    @State private var activeFamily: AttributeFamily = .intensity
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

    public enum AttributeFamily: String, CaseIterable, Sendable {
        case intensity = "Intensity"
        case pan = "Pan"
        case tilt = "Tilt"
        case color = "Color"
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

    private var fixtureNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: project.fixtures.map { ($0.id, $0.name) })
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
                    detail: "Select fixtures in the browser to create a look.",
                    systemImage: "slider.horizontal.3"
                )
                .background(AuroraColor.surfacePanel)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AuroraSpacing.md) {
                        headerBar(pres)
                        orderStrip(pres)
                        controlsRow(pres)
                        if pres.hasTechnicalColor,
                           showTechnicalColor || !pres.hasRGBColor {
                            technicalColorSection(pres)
                        }
                        if showFanTools {
                            fanToolStrip
                        }
                        fixtureChips
                        toolRow(pres)
                    }
                    .padding(AuroraSpacing.md)
                }
                .background(AuroraColor.surfacePanel)
            }
        }
        .onAppear { syncDrafts(from: pres) }
        .onChange(of: presentationRevision) { _, _ in
            syncDrafts(from: livePresentation)
        }
        .onChange(of: orderedIDs) { _, _ in
            syncDrafts(from: livePresentation)
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

    // MARK: - Controls

    private func controlsRow(_ pres: ProgrammerAttributePresentation) -> some View {
        HStack(alignment: .top, spacing: AuroraSpacing.lg) {
            if pres.hasIntensity {
                intensityControl(pres.intensity)
            }
            if pres.hasPosition {
                positionControls(pres)
            }
            if pres.hasRGBColor {
                rgbColorControls(pres)
            } else if pres.hasTechnicalColor {
                // Technical-only: no HSV wheel
                VStack(alignment: .leading, spacing: 6) {
                    colorFamilyChrome(pres)
                    Button(showTechnicalColor ? "Hide Channels" : "Show Channels") {
                        showTechnicalColor.toggle()
                    }
                    .font(AuroraTypography.metadata)
                    .buttonStyle(.borderless)
                    .foregroundStyle(AuroraColor.accentBright)
                }
            }
        }
    }

    private func intensityControl(_ state: ProgrammerAttributeState) -> some View {
        let display = displayValue(for: state, untreated: 0)
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

    private func rgbColorControls(_ pres: ProgrammerAttributePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            colorFamilyChrome(pres)
            AuroraColorWheel(
                hue: $draftHue,
                saturation: $draftSat,
                brightness: draftVal,
                size: 120,
                isMixed: pres.isRGBMixed
            )
            .onChange(of: draftHue) { _, _ in applyHSV(pres); activeFamily = .color }
            .onChange(of: draftSat) { _, _ in applyHSV(pres); activeFamily = .color }
            if pres.hasTechnicalColor {
                Button(showTechnicalColor ? "Hide Channels" : "Technical Channels") {
                    showTechnicalColor.toggle()
                }
                .font(AuroraTypography.metadata)
                .buttonStyle(.borderless)
                .foregroundStyle(AuroraColor.accentBright)
            }
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
                        .frame(width: 48)
                    }
                }
            }
        }
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
                        .buttonStyle(.bordered)
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

    private var fixtureChips: some View {
        let names = fixtureNames
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(orderedIDs.enumerated()), id: \.element) { idx, id in
                    AuroraFixtureChip(name: "\(idx + 1) \(names[id] ?? "·")", isSelected: true)
                }
            }
        }
    }

    private func toolRow(_ pres: ProgrammerAttributePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AuroraButton("Locate", kind: .secondary) {
                    programmer.locate(fixtureIDs: Set(orderedIDs), project: project)
                    onChanged()
                }
                AuroraButton("Home", kind: .secondary) {
                    programmer.home(fixtureIDs: Set(orderedIDs), project: project)
                    onChanged()
                }
                AuroraButton("Clear", kind: .quiet) {
                    programmer.clear(fixtureIDs: Set(orderedIDs))
                    onChanged()
                }
                AuroraButton("Clear All", kind: .quiet) {
                    programmer.clearAll()
                    onChanged()
                }
                Spacer()
            }
            HStack(spacing: 8) {
                AuroraButton(showFanTools ? "Hide Fan" : "Fan…", kind: .secondary) {
                    showFanTools.toggle()
                    seedFanFromPresentation(pres)
                }
                AuroraButton("Align to First", kind: .secondary) {
                    applyAlignToFirst(pres)
                }
                .disabled(!canAlign(pres))
                .help("Set all capable fixtures to the first ordered fixture’s Programmer value")
                Spacer()
            }
        }
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

    /// One capability map, one multi-attr batch, one presentation refresh.
    private func applyHSV(_ pres: ProgrammerAttributePresentation) {
        let rgb = ColorMath.rgb(from: HSVColor(h: draftHue * 360, s: draftSat, v: draftVal))
        let includeW = pres.colorW.isSupported
        let attrs = ColorMath.programmerAttributes(from: rgb, includeWhite: includeW)
        let caps = ProgrammerAttributePresentationResolver.capabilityMap(
            orderedFixtureIDs: orderedIDs,
            project: project
        )
        var batch: [UUID: [String: Double]] = [:]
        for (attr, value) in attrs {
            let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
                attribute: attr,
                orderedFixtureIDs: orderedIDs,
                caps: caps
            )
            for id in capable {
                var map = batch[id] ?? [:]
                map[attr] = value
                batch[id] = map
            }
            draftRGB[attr] = value
        }
        programmer.setMany(batch)
        onChanged()
    }

    private func applyFan() {
        let attribute: String
        switch activeFamily {
        case .intensity: attribute = "intensity"
        case .pan: attribute = "pan"
        case .tilt: attribute = "tilt"
        case .color: attribute = "intensity"
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
        case .pan: attribute = "pan"
        case .tilt: attribute = "tilt"
        case .color: attribute = "colorR"
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
            for attr in ["colorR", "colorG", "colorB", "colorW"] where attributeState(attr, in: pres).isSupported {
                if alignAttribute(attr) { any = true }
            }
            if any { onChanged() }
        case .intensity:
            if alignAttribute("intensity") { onChanged() }
        case .pan:
            if alignAttribute("pan") { onChanged() }
        case .tilt:
            if alignAttribute("tilt") { onChanged() }
        }
    }

    @discardableResult
    private func alignAttribute(_ attribute: String) -> Bool {
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: attribute,
            orderedFixtureIDs: orderedIDs,
            project: project
        )
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
        case .pan: state = pres.pan
        case .tilt: state = pres.tilt
        case .color: state = pres.intensity
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
        switch attr {
        case "intensity": return pres.intensity
        case "pan": return pres.pan
        case "tilt": return pres.tilt
        case "colorR": return pres.colorR
        case "colorG": return pres.colorG
        case "colorB": return pres.colorB
        case "colorW": return pres.colorW
        default:
            let caps = ProgrammerAttributePresentationResolver.capabilityMap(
                orderedFixtureIDs: orderedIDs,
                project: project
            )
            return ProgrammerAttributePresentationResolver.resolveAttribute(
                attr,
                ordered: orderedIDs,
                caps: caps,
                values: programmer.snapshot().values
            )
        }
    }

    private func shortColorLabel(_ attr: String) -> String {
        switch attr {
        case "colorR": return "R"
        case "colorG": return "G"
        case "colorB": return "B"
        case "colorW": return "W"
        case "colorA": return "A"
        case "colorUV": return "UV"
        case "cyan": return "C"
        case "magenta": return "M"
        case "yellow": return "Y"
        default: return attr
        }
    }
}
