import AuroraEngine
import AuroraModel
import SwiftUI

/// LightKey-style Color Programmer: Dimmer | Wheel | dedicated emitters.
public struct ProgrammerColorEngineView: View {
    public var color: ProgrammerColorPresentation
    public var programmer: Programmer
    public var project: ShowProject
    public var onChanged: () -> Void

    @Environment(\.auroraDensity) private var density

    @State private var draftHue: Double = 0
    @State private var draftSat: Double = 0.85
    @State private var draftVal: Double = 1
    @State private var draftWB: Double = 0
    @State private var draftDimmer: Double = 0
    @State private var draftEmitters: [String: Double] = [:]

    public init(
        color: ProgrammerColorPresentation,
        programmer: Programmer,
        project: ShowProject,
        onChanged: @escaping () -> Void = {}
    ) {
        self.color = color
        self.programmer = programmer
        self.project = project
        self.onChanged = onChanged
    }

    private var orderedIDs: [UUID] { color.orderedFixtureIDs }

    private var faderMetrics: ValueFaderMetrics {
        ValueFaderMetrics.forDensity(density)
    }

    /// Center preview always from presentation (mixed) or live authoring resolve when concrete.
    private var displayPreview: AuroraEngine.RGBColor {
        if color.isRGBMixed || color.isAuthoringMixed {
            return color.previewRGB
        }
        return ColorMath.resolvedRGB(
            hue: draftHue,
            saturation: draftSat,
            brightness: draftVal,
            whiteBalance: draftWB
        )
    }

    public var body: some View {
        colorEngineBody
            .frame(minHeight: faderMetrics.channelHeight + 48)
            .onAppear { rebuildDrafts(from: color) }
            .onChange(of: color.orderedFixtureIDs) { _, _ in rebuildDrafts(from: color) }
            .onChange(of: presentationIdentity) { _, _ in rebuildDrafts(from: color) }
    }

    /// Rebuild drafts when selection / support set changes — not on every live emitter sample.
    private var presentationIdentity: String {
        let ids = color.orderedFixtureIDs.map(\.uuidString).joined(separator: ",")
        let emitterKeys = color.emitters.map {
            "\($0.attribute):\($0.state.support)"
        }.joined(separator: ",")
        return [
            ids,
            emitterKeys,
            "\(color.hasRGB)",
            "\(color.dimmer.isSupported)",
            "\(color.isRGBMixed)",
            "\(color.isAuthoringMixed)",
            color.hue == nil ? "u" : "h",
            color.saturation == nil ? "u" : "s",
            color.brightness == nil ? "u" : "v",
            color.whiteBalance == nil ? "u" : "w",
            color.dimmer.isUntouched ? "du" : "do",
        ].joined(separator: "|")
    }

    private var colorEngineBody: some View {
        GeometryReader { geo in
            let baseMetrics = faderMetrics
            let responsiveHeight = ProgrammerColorFaderLayout.responsiveChannelHeight(
                availableHeight: geo.size.height,
                baseChannelHeight: baseMetrics.channelHeight,
                basePanelHeight: baseMetrics.channelHeight + 48
            )
            let m = baseMetrics.withChannelHeight(responsiveHeight)
            let spacing: CGFloat = 16
            let wheelMin = ProgrammerColorFaderLayout.defaultWheelMinWidth
            let dimmerW = showsDimmer ? m.controlWidth : 0
            let emitterCount = color.emitters.count
            let emittersNatural = ProgrammerColorFaderLayout.emittersContentWidth(
                emitterCount: emitterCount,
                faderWidth: m.controlWidth,
                spacing: ProgrammerColorFaderLayout.defaultSpacing
            )
            // Remaining after dimmer + gaps; wheel keeps protected min via layoutPriority.
            let afterDimmer = max(0, geo.size.width - dimmerW - spacing)
            let wheelTarget = min(280, max(wheelMin, min(geo.size.width * 0.42, geo.size.height - 48)))
            let emitterAvailable = max(0, afterDimmer - wheelTarget - spacing)

            HStack(alignment: .center, spacing: spacing) {
                if showsDimmer {
                    dimmerColumn(metrics: m)
                        .frame(width: m.controlWidth)
                        .layoutPriority(2)
                }

                centerCluster(wheelSize: wheelTarget)
                    .frame(minWidth: wheelMin)
                    .layoutPriority(3)

                if emitterCount > 0 {
                    emitterRegion(
                        availableWidth: emitterAvailable,
                        naturalWidth: emittersNatural,
                        metrics: m
                    )
                    .layoutPriority(1)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var showsDimmer: Bool {
        color.dimmer.isSupported || color.hasRGB || !color.emitters.isEmpty
    }

    private func centerCluster(wheelSize: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text("COLOR")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            wheelOrPlaceholder(wheelSize: wheelSize)
            if color.hasRGB {
                swatchRow
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func wheelOrPlaceholder(wheelSize: CGFloat) -> some View {
        if color.hasRGB {
            AuroraProgrammerColorWheel(
                hue: $draftHue,
                saturation: $draftSat,
                brightness: $draftVal,
                whiteBalance: $draftWB,
                previewRGB: displayPreview,
                size: wheelSize,
                isMixed: color.isRGBMixed || color.isAuthoringMixed,
                onLiveEdit: { applyAuthoring() }
            )
            .frame(maxWidth: .infinity)
        } else {
            Text("No RGB color mixing on this selection")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
                .frame(maxWidth: .infinity, minHeight: wheelSize * 0.5)
        }
    }

    // MARK: - Dimmer

    private func dimmerColumn(metrics m: ValueFaderMetrics) -> some View {
        let state = color.dimmer
        return AuroraFader(
            value: Binding(
                get: { draftDimmer },
                set: { v in
                    draftDimmer = v
                    applyEmitterOrDimmer(attribute: "intensity", value: v)
                }
            ),
            label: "Dimmer",
            iconName: AuroraLightingIcon.intensity.rawValue,
            showsOwnedChrome: !state.isUntouched && !state.isMixed,
            display: displayValue(for: state),
            channelHeight: m.channelHeight,
            accent: nil
        )
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Emitters

    private func emitterRegion(
        availableWidth: CGFloat,
        naturalWidth: CGFloat,
        metrics m: ValueFaderMetrics
    ) -> some View {
        let needsScroll = ProgrammerColorFaderLayout.emitterRegionNeedsScroll(
            availableWidth: availableWidth,
            emitterCount: color.emitters.count,
            faderWidth: m.controlWidth,
            spacing: ProgrammerColorFaderLayout.defaultSpacing
        )
        let width = needsScroll
            ? max(m.controlWidth, availableWidth)
            : min(naturalWidth, max(m.controlWidth, availableWidth))

        return Group {
            if needsScroll {
                ScrollView(.horizontal, showsIndicators: true) {
                    emitterRow(metrics: m)
                        .padding(.trailing, 4)
                }
            } else {
                emitterRow(metrics: m)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func emitterRow(metrics m: ValueFaderMetrics) -> some View {
        HStack(alignment: .bottom, spacing: ProgrammerColorFaderLayout.defaultSpacing) {
            ForEach(color.emitters) { emitter in
                emitterFader(emitter, metrics: m)
            }
        }
    }

    private func emitterFader(_ emitter: EmitterControlPresentation, metrics m: ValueFaderMetrics) -> some View {
        let state = emitter.state
        let key = emitter.attribute
        return VStack(spacing: 4) {
            if state.support == .partial {
                Text("partial")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(AuroraColor.warning)
            }
            AuroraFader(
                value: Binding(
                    get: { draftEmitters[key] ?? state.displayValue ?? 0 },
                    set: { v in
                        draftEmitters[key] = v
                        applyEmitterOrDimmer(attribute: key, value: v)
                    }
                ),
                label: emitter.kind.displayName,
                showsOwnedChrome: !state.isUntouched && !state.isMixed,
                display: displayValue(for: state),
                channelHeight: m.channelHeight,
                accent: trackColor(for: emitter.accent)
            )
            .frame(width: m.controlWidth)
            .frame(maxHeight: .infinity)
        }
        .frame(width: m.controlWidth)
        .opacity(state.support == .partial ? 0.92 : 1)
    }

    private func trackColor(for accent: EmitterAccent) -> Color {
        switch accent {
        case .white: return Color(red: 0.82, green: 0.90, blue: 0.98)
        case .amber: return Color(red: 1.0, green: 0.62, blue: 0.12)
        case .uv: return Color(red: 0.62, green: 0.35, blue: 1.0)
        case .neutral: return AuroraColor.accent
        }
    }

    // MARK: - Swatches

    private var swatchRow: some View {
        HStack(spacing: 6) {
            ForEach(color.swatches) { swatch in
                Button {
                    applySwatch(swatch)
                } label: {
                    Circle()
                        .fill(swatchColor(swatch))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 4)
    }

    private func swatchColor(_ s: ColorSwatchDefinition) -> Color {
        let rgb = ColorMath.resolvedRGB(from: s.authoring)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    // MARK: - Apply

    private func applyAuthoring() {
        let capable = ProgrammerColorPresentationResolver.rgbCapableIDs(
            orderedFixtureIDs: orderedIDs,
            project: project
        )
        guard !capable.isEmpty else { return }
        let authoring = ColorAuthoringState(
            hue: draftHue,
            saturation: draftSat,
            brightness: draftVal,
            whiteBalance: draftWB
        )
        let attrs = ColorMath.programmerColorBatch(from: authoring)
        var batch: [UUID: [String: Double]] = [:]
        for id in capable {
            batch[id] = attrs
        }
        programmer.setMany(batch)
        onChanged()
    }

    private func applySwatch(_ swatch: ColorSwatchDefinition) {
        draftHue = swatch.hue
        draftSat = swatch.saturation
        draftVal = swatch.brightness
        draftWB = 0
        applyAuthoring()
    }

    private func applyEmitterOrDimmer(attribute: String, value: Double) {
        let capable = ProgrammerAttributePresentationResolver.capableFixtureIDs(
            attribute: attribute,
            orderedFixtureIDs: orderedIDs,
            project: project
        )
        guard !capable.isEmpty else { return }
        var batch: [UUID: [String: Double]] = [:]
        for id in capable {
            batch[id] = [attribute: value]
        }
        programmer.setMany(batch)
        onChanged()
    }

    private func rebuildDrafts(from presentation: ProgrammerColorPresentation) {
        draftHue = presentation.hue ?? 0
        draftSat = presentation.saturation ?? (presentation.hasRGB ? 0.85 : 0)
        draftVal = presentation.brightness ?? (presentation.hasRGB ? 1 : 0)
        draftWB = presentation.whiteBalance ?? 0
        draftDimmer = presentation.dimmer.displayValue ?? (presentation.dimmer.isSupported ? 1.0 : 0)
        draftEmitters = [:]
        for emitter in presentation.emitters {
            if let v = emitter.state.displayValue, !emitter.state.isMixed {
                draftEmitters[emitter.attribute] = v
            } else {
                draftEmitters[emitter.attribute] = 0
            }
        }
    }

    private func displayValue(for state: ProgrammerAttributeState) -> AuroraControlDisplayValue {
        if !state.isSupported { return .unavailable }
        if state.isMixed { return .mixed }
        if let v = state.displayValue { return .value(v) }
        return .value(0)
    }
}
