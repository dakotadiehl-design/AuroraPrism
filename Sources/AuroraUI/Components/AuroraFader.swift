import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Luminous value-thumb fader for channel and shelf controls.
public struct AuroraFader: View {
    @Binding public var value: Double
    public var label: String
    public var iconName: String?
    public var isEnabled: Bool
    public var showsOwnedChrome: Bool
    public var display: AuroraControlDisplayValue
    public var axis: Axis
    /// Optional vertical rail height supplied by a responsive container.
    public var channelHeight: CGFloat?
    /// Explicit fill/thumb accent. Prefer this for custom drawing; `nil` uses Aurora accent.
    public var accent: Color?
    /// Optional formatter for normalized values used by the thumb/readout and accessibility.
    public var valueFormatter: ((Double) -> String)?
    /// Mirrors Slider's editing lifecycle so callers can coalesce undo at drag end.
    public var onEditingChanged: ((Bool) -> Void)?

    @Environment(\.auroraDensity) private var density
    @Environment(\.isEnabled) private var environmentIsEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var isDragging = false
    @State private var activeDragOffset: CGFloat = 0

    public init(
        value: Binding<Double>,
        label: String = "",
        iconName: String? = nil,
        isEnabled: Bool = true,
        showsOwnedChrome: Bool = false,
        display: AuroraControlDisplayValue = .value(0),
        axis: Axis = .vertical,
        channelHeight: CGFloat? = nil,
        accent: Color? = nil,
        valueFormatter: ((Double) -> String)? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.label = label
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.showsOwnedChrome = showsOwnedChrome
        self.display = display
        self.axis = axis
        self.channelHeight = channelHeight
        self.accent = accent
        self.valueFormatter = valueFormatter
        self.onEditingChanged = onEditingChanged
    }

    private var interactive: Bool {
        isEnabled && environmentIsEnabled && display.isInteractive
    }

    private var isMixed: Bool {
        if case .mixed = display { return true }
        return false
    }

    private var isUnavailable: Bool {
        if case .unavailable = display { return true }
        return false
    }

    private var metrics: ValueFaderMetrics {
        let base = ValueFaderMetrics.forDensity(density)
        guard let channelHeight else { return base }
        return base.withChannelHeight(channelHeight)
    }

    private var resolvedAccent: Color {
        accent ?? AuroraColor.accent
    }

    public var body: some View {
        Group {
            if axis == .vertical {
                verticalBody
                    .focusable(interactive)
                    .focused($isFocused)
                    .onKeyPress(phases: .down) { press in
                        handleKeyPress(press)
                    }
            } else {
                horizontalBody
                    .focusable(interactive)
                    .focused($isFocused)
                    .onKeyPress(phases: .down) { press in
                        handleKeyPress(press)
                    }
            }
        }
        .opacity(opacityForState)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Fader" : label)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard interactive else { return }
            performDiscreteEdit {
                applyKeyboardDelta(
                    direction == .increment
                        ? ValueFaderGeometry.accessibilityStep
                        : -ValueFaderGeometry.accessibilityStep
                )
            }
        }
    }

    private var opacityForState: Double {
        if isUnavailable { return 0.35 }
        if !isEnabled || !environmentIsEnabled { return 0.4 }
        return 1
    }

    private var accessibilityValueText: String {
        switch display {
        case .mixed: return "mixed"
        case .unavailable: return "unavailable"
        case .value: return formattedValue
        }
    }

    // MARK: - Vertical (Option C value thumb)

    private var verticalBody: some View {
        let m = metrics
        return VStack(spacing: 6) {
            if !label.isEmpty || iconName != nil {
                labelHeader
            }

            ZStack {
                channelStack(metrics: m)
            }
            .frame(width: m.controlWidth, height: m.channelHeight)
            .contentShape(Rectangle())
            .gesture(verticalDrag(metrics: m))

            // Always reserve this slot so acquiring/releasing ownership cannot
            // change the stack height and make the fader jump vertically.
            Circle()
                .fill(AuroraColor.stateOwned)
                .frame(width: 6, height: 6)
                .opacity(showsOwnedChrome && !isMixed && !isUnavailable ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(width: m.controlWidth)
    }

    private var labelHeader: some View {
        HStack(spacing: 3) {
            if let iconName {
                AuroraAssetIcon(name: iconName, size: 11)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            if !label.isEmpty {
                Text(ProgrammerColorFaderLayout.displayLabel(label.uppercased()))
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func channelStack(metrics m: ValueFaderMetrics) -> some View {
        let paint = paintValue
        let centerY = isMixed
            ? m.channelHeight / 2
            : ValueFaderGeometry.thumbCenterY(
                value: paint,
                channelHeight: m.channelHeight,
                thumbHeight: m.thumbHeight
            )
        let fillHeight = max(0, m.channelHeight - centerY)

        return ZStack {
            // Deep console slot: a restrained outer bezel around a darker inner rail.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.075), Color.black.opacity(0.34)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: m.channelWidth, height: m.channelHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 3, x: 0, y: 2)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.78), AuroraColor.surfaceWell],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: m.channelWidth - 8, height: m.channelHeight - 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(resolvedAccent.opacity(0.20), lineWidth: 0.75)
                )

            // Major ticks
            tickMarks(metrics: m)

            // Active fill (bottom → thumb center)
            if !isMixed, !isUnavailable {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: max(2, m.trackWidth / 3), style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [resolvedAccent.opacity(0.80), resolvedAccent.opacity(0.42)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: m.trackWidth, height: max(m.trackWidth, fillHeight))
                        .overlay(
                            RoundedRectangle(cornerRadius: max(2, m.trackWidth / 3), style: .continuous)
                                .strokeBorder(resolvedAccent.opacity(0.65), lineWidth: 0.75)
                        )
                        .shadow(color: resolvedAccent.opacity(isDragging ? 0.42 : 0.25), radius: 2)
                }
                .frame(width: m.channelWidth, height: m.channelHeight)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            // Thumb / badge
            thumbView(metrics: m, centerY: centerY)
        }
        .frame(width: m.controlWidth, height: m.channelHeight)
    }

    private func tickMarks(metrics m: ValueFaderMetrics) -> some View {
        let tickCount = 17
        return ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let f = CGFloat(index) / CGFloat(tickCount - 1)
                let major = index % 4 == 0
                let y = ValueFaderGeometry.thumbCenterY(
                    value: Double(f),
                    channelHeight: m.channelHeight,
                    thumbHeight: m.thumbHeight
                )
                HStack {
                    Rectangle()
                        .fill(resolvedAccent.opacity(major ? 0.62 : 0.34))
                        .frame(width: major ? 8 : 5, height: major ? 1.25 : 0.75)
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(resolvedAccent.opacity(major ? 0.62 : 0.34))
                        .frame(width: major ? 8 : 5, height: major ? 1.25 : 0.75)
                }
                .frame(width: m.channelWidth - max(2, m.tickInset))
                .position(x: m.controlWidth / 2, y: y)
            }
        }
        .frame(width: m.controlWidth, height: m.channelHeight)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func thumbView(metrics m: ValueFaderMetrics, centerY: CGFloat) -> some View {
        let visualThumbWidth = max(52, m.thumbWidth - 6)
        if isUnavailable {
            ValueThumbShape()
                .fill(AuroraColor.surfaceRaised.opacity(0.60))
                .frame(width: visualThumbWidth, height: m.thumbHeight)
                .overlay(
                    Text("N/A")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AuroraColor.textTertiary)
                )
                .overlay(ValueThumbShape().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .position(x: m.controlWidth / 2, y: m.channelHeight / 2)
        } else if isMixed {
            ValueThumbShape()
                .fill(AuroraColor.surfaceRaised.opacity(0.48))
                .frame(width: visualThumbWidth, height: m.thumbHeight)
                .overlay(
                    Text("MIXED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AuroraColor.stateMixed)
                )
                .overlay(ValueThumbShape().stroke(AuroraColor.stateMixed, lineWidth: 1.5))
                .position(x: m.controlWidth / 2, y: centerY)
        } else {
            let palette = thumbPalette
            ValueThumbShape()
                .fill(Color.black.opacity(0.72))
                .shadow(color: Color.black.opacity(isDragging ? 0.62 : 0.48), radius: isDragging ? 6 : 4, y: 2)
                .overlay {
                    ValueThumbShape()
                        .fill(
                            LinearGradient(
                                colors: palette.fill,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(2)
                        .overlay(
                            ValueThumbShape()
                                .stroke(thumbBorderColor(palette: palette), lineWidth: isFocused ? m.focusRingWidth : 1)
                                .padding(2)
                        )
                }
                .frame(width: visualThumbWidth, height: m.thumbHeight)
                .overlay {
                    // Soft edge vignette gives the cap the molded, shaded contour from the render.
                    LinearGradient(
                        colors: [Color.black.opacity(0.16), .clear, Color.black.opacity(0.22)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(ValueThumbShape())
                    .padding(2)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    ValueThumbShape()
                        .stroke(Color.white.opacity(palette.usesDarkText ? 0.46 : 0.28), lineWidth: 0.8)
                        .padding(3)
                        .mask(
                            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)
                        )
                }
                .overlay {
                    VStack(spacing: 1) {
                        Text(formattedValue)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.usesDarkText ? Color.black.opacity(0.88) : Color.white)
                        Capsule()
                            .fill(palette.usesDarkText ? Color.black.opacity(0.36) : Color.white.opacity(0.52))
                            .frame(width: 17, height: 1.5)
                    }
                }
                .scaleEffect(isDragging ? 1.025 : 1)
                .brightness(isHovered && !isDragging ? 0.045 : 0)
                .position(x: m.controlWidth / 2, y: centerY)
        }
    }

    private struct ThumbPalette {
        var fill: [Color]
        var usesDarkText: Bool
        var border: Color
    }

    private var thumbPalette: ThumbPalette {
        let normalized = label.lowercased()
        if normalized.contains("amber") || normalized == "a" {
            return ThumbPalette(
                fill: [
                    Color(red: 1.0, green: 0.82, blue: 0.34),
                    Color(red: 0.98, green: 0.57, blue: 0.08),
                    Color(red: 0.55, green: 0.23, blue: 0.01),
                ],
                usesDarkText: true,
                border: Color(red: 1.0, green: 0.72, blue: 0.18)
            )
        }
        if normalized.contains("white") || normalized == "w" || normalized == "cw" || normalized == "ww" {
            return ThumbPalette(
                fill: [
                    Color.white,
                    Color(red: 0.76, green: 0.92, blue: 0.97),
                    Color(red: 0.39, green: 0.63, blue: 0.70),
                ],
                usesDarkText: true,
                border: Color(red: 0.80, green: 0.95, blue: 1.0)
            )
        }
        if normalized == "uv" || normalized.contains("ultraviolet") {
            return ThumbPalette(
                fill: [
                    Color(red: 0.72, green: 0.42, blue: 1.0),
                    Color(red: 0.48, green: 0.18, blue: 0.82),
                    Color(red: 0.17, green: 0.05, blue: 0.34),
                ],
                usesDarkText: false,
                border: Color(red: 0.76, green: 0.48, blue: 1.0)
            )
        }
        if normalized.contains("dimmer") || normalized.contains("intensity") || accent == nil {
            return ThumbPalette(
                fill: [Color(white: 0.98), Color(white: 0.72), Color(white: 0.34)],
                usesDarkText: true,
                border: Color.white.opacity(0.72)
            )
        }

        let darkText = accentLuminance(resolvedAccent) > 0.62
        return ThumbPalette(
            fill: [
                resolvedAccent.opacity(1.0),
                resolvedAccent.opacity(darkText ? 0.78 : 0.68),
                resolvedAccent.opacity(darkText ? 0.48 : 0.38),
            ],
            usesDarkText: darkText,
            border: resolvedAccent.opacity(0.92)
        )
    }

    private func thumbBorderColor(palette: ThumbPalette) -> Color {
        if isFocused { return AuroraColor.focusRing }
        if isDragging { return palette.border }
        if isHovered { return palette.border.opacity(0.92) }
        return palette.border.opacity(0.66)
    }

    private func accentLuminance(_ color: Color) -> Double {
        // Approximate via resolved RGB in sRGB space when possible.
        #if canImport(AppKit)
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * Double(rgb.redComponent)
            + 0.7152 * Double(rgb.greenComponent)
            + 0.0722 * Double(rgb.blueComponent)
        #else
        return 0.5
        #endif
    }

    private func verticalDrag(metrics m: ValueFaderMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { drag in
                guard interactive else { return }
                if !isDragging {
                    isDragging = true
                    onEditingChanged?(true)
                    let centerY = isMixed
                        ? m.channelHeight / 2
                        : ValueFaderGeometry.thumbCenterY(
                            value: paintValue,
                            channelHeight: m.channelHeight,
                            thumbHeight: m.thumbHeight
                        )
                    if ValueFaderGeometry.pointerHitsThumb(
                        pointerY: drag.startLocation.y,
                        thumbCenterY: centerY,
                        thumbHeight: m.thumbHeight
                    ) {
                        activeDragOffset = ValueFaderGeometry.dragOffset(
                            pointerY: drag.startLocation.y,
                            thumbCenterY: centerY
                        )
                    } else {
                        activeDragOffset = 0
                    }
                }
                value = ValueFaderGeometry.value(
                    fromPointerY: drag.location.y,
                    dragOffset: activeDragOffset,
                    channelHeight: m.channelHeight,
                    thumbHeight: m.thumbHeight
                )
            }
            .onEnded { _ in
                isDragging = false
                activeDragOffset = 0
                onEditingChanged?(false)
            }
    }

    // MARK: - Keyboard

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard interactive else { return .ignored }
        let mods = press.modifiers
        let shift = mods.contains(.shift)
        let option = mods.contains(.option)
        let step = ValueFaderGeometry.keyboardStep(shift: shift, option: option)

        switch press.key {
        case .upArrow, .rightArrow:
            performDiscreteEdit { applyKeyboardDelta(step) }
            return .handled
        case .downArrow, .leftArrow:
            performDiscreteEdit { applyKeyboardDelta(-step) }
            return .handled
        case .home:
            performDiscreteEdit { value = 0 }
            return .handled
        case .end:
            performDiscreteEdit { value = 1 }
            return .handled
        default:
            return .ignored
        }
    }

    private func applyKeyboardDelta(_ delta: Double) {
        if isMixed {
            value = ValueFaderGeometry.mixedFirstKeyboardValue(increment: delta > 0)
        } else {
            value = ValueFaderGeometry.applyStep(current: paintValue, delta: delta)
        }
    }

    private func performDiscreteEdit(_ update: () -> Void) {
        onEditingChanged?(true)
        update()
        onEditingChanged?(false)
    }

    // MARK: - Horizontal value thumb

    private var horizontalBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                Spacer()
                Text(valueLabel)
                    .font(AuroraTypography.primaryValue)
                    .foregroundStyle(valueLabelColor)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let thumbWidth: CGFloat = 46
                let thumbHeight: CGFloat = 28
                let x = isMixed ? w * 0.5 : ValueFaderGeometry.thumbCenterX(
                    value: clamped,
                    trackWidth: w,
                    thumbWidth: thumbWidth
                )
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AuroraColor.surfaceWell)
                        .frame(height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    if !isMixed, case .value = display {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [resolvedAccent.opacity(0.65), resolvedAccent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, x), height: 16)
                    }
                    if isMixed {
                        ValueThumbShape()
                            .fill(AuroraColor.surfaceRaised)
                            .overlay(ValueThumbShape().stroke(AuroraColor.stateMixed, lineWidth: 1.5))
                            .frame(width: thumbWidth, height: thumbHeight)
                            .overlay(Text("MIX").font(.system(size: 8, weight: .bold)).foregroundStyle(AuroraColor.stateMixed))
                            .position(x: x, y: geo.size.height / 2)
                    } else if case .value = display {
                        ValueThumbShape()
                            .fill(AuroraColor.surfaceRaised)
                            .overlay(ValueThumbShape().stroke(resolvedAccent.opacity(0.9), lineWidth: 1))
                            .frame(width: thumbWidth, height: thumbHeight)
                            .overlay(Text(formattedValue).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(AuroraColor.textPrimary))
                            .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(horizontalDrag(size: geo.size, thumbWidth: thumbWidth))
            }
            .frame(height: 32)
        }
    }

    private func horizontalDrag(size: CGSize, thumbWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard interactive else { return }
                if !isDragging {
                    isDragging = true
                    onEditingChanged?(true)
                    let center = isMixed ? size.width / 2 : ValueFaderGeometry.thumbCenterX(
                        value: paintValue,
                        trackWidth: size.width,
                        thumbWidth: thumbWidth
                    )
                    activeDragOffset = ValueFaderGeometry.pointerHitsThumb(
                        pointerX: drag.startLocation.x,
                        thumbCenterX: center,
                        thumbWidth: thumbWidth
                    ) ? drag.startLocation.x - center : 0
                }
                value = ValueFaderGeometry.value(
                    fromPointerX: drag.location.x,
                    dragOffset: activeDragOffset,
                    trackWidth: size.width,
                    thumbWidth: thumbWidth
                )
            }
            .onEnded { _ in
                isDragging = false
                activeDragOffset = 0
                onEditingChanged?(false)
            }
    }

    // MARK: - Shared value helpers

    /// Paint source: live binding when interactive; display snapshot otherwise.
    private var paintValue: Double {
        if interactive {
            if isMixed { return 0.5 } // visual mid only
            return ValueFaderGeometry.clamp01(value)
        }
        if case .value(let v) = display { return ValueFaderGeometry.clamp01(v) }
        return ValueFaderGeometry.clamp01(value)
    }

    private var clamped: Double {
        if interactive {
            return ValueFaderGeometry.clamp01(value)
        }
        if case .value(let v) = display { return ValueFaderGeometry.clamp01(v) }
        return ValueFaderGeometry.clamp01(value)
    }

    private var percent: Int {
        if isMixed { return 0 }
        return Int((paintValue * 100).rounded())
    }

    private var formattedValue: String {
        valueFormatter?(paintValue) ?? "\(percent)%"
    }

    private var valueLabel: String {
        switch display {
        case .mixed: return "MIXED"
        case .unavailable: return "—"
        case .value: return formattedValue
        }
    }

    private var valueLabelColor: Color {
        switch display {
        case .mixed: return AuroraColor.stateMixed
        case .unavailable: return AuroraColor.textTertiary
        case .value: return showsOwnedChrome ? AuroraColor.accentBright : AuroraColor.textPrimary
        }
    }
}

/// Stepped lighting-console cap used by the Option C vertical fader.
/// The side ears make the draggable element visually unmistakable without enlarging its hit box.
private struct ValueThumbShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let ear = min(5, w * 0.08)
        let shoulderY = h * 0.26
        let lowerShoulderY = h * 0.74
        let corner = min(7, h * 0.23)
        var path = Path()

        path.move(to: CGPoint(x: ear + corner, y: 0))
        path.addLine(to: CGPoint(x: w - ear - corner, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: w - ear, y: corner),
            control: CGPoint(x: w - ear, y: 0)
        )
        path.addLine(to: CGPoint(x: w - ear, y: shoulderY))
        path.addLine(to: CGPoint(x: w - 1.5, y: shoulderY))
        path.addQuadCurve(
            to: CGPoint(x: w, y: shoulderY + 1.5),
            control: CGPoint(x: w, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: w, y: lowerShoulderY - 1.5))
        path.addQuadCurve(
            to: CGPoint(x: w - 1.5, y: lowerShoulderY),
            control: CGPoint(x: w, y: lowerShoulderY)
        )
        path.addLine(to: CGPoint(x: w - ear, y: lowerShoulderY))
        path.addLine(to: CGPoint(x: w - ear, y: h - corner))
        path.addQuadCurve(
            to: CGPoint(x: w - ear - corner, y: h),
            control: CGPoint(x: w - ear, y: h)
        )
        path.addLine(to: CGPoint(x: ear + corner, y: h))
        path.addQuadCurve(
            to: CGPoint(x: ear, y: h - corner),
            control: CGPoint(x: ear, y: h)
        )
        path.addLine(to: CGPoint(x: ear, y: lowerShoulderY))
        path.addLine(to: CGPoint(x: 1.5, y: lowerShoulderY))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: lowerShoulderY - 1.5),
            control: CGPoint(x: 0, y: lowerShoulderY)
        )
        path.addLine(to: CGPoint(x: 0, y: shoulderY + 1.5))
        path.addQuadCurve(
            to: CGPoint(x: 1.5, y: shoulderY),
            control: CGPoint(x: 0, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: ear, y: shoulderY))
        path.addLine(to: CGPoint(x: ear, y: corner))
        path.addQuadCurve(
            to: CGPoint(x: ear + corner, y: 0),
            control: CGPoint(x: ear, y: 0)
        )
        path.closeSubpath()
        return path
    }
}
