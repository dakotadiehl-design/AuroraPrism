import SwiftUI

/// Luminous vertical fader (render pack) + horizontal master support.
public struct AuroraFader: View {
    @Binding public var value: Double
    public var label: String
    /// Optional catalog asset name (e.g. IntensityIcon). Caller styles via environment if needed.
    public var iconName: String?
    public var isEnabled: Bool
    public var showsOwnedChrome: Bool
    public var axis: Axis

    @Environment(\.auroraDensity) private var density
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    public init(
        value: Binding<Double>,
        label: String = "",
        iconName: String? = nil,
        isEnabled: Bool = true,
        showsOwnedChrome: Bool = false,
        axis: Axis = .vertical
    ) {
        self._value = value
        self.label = label
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.showsOwnedChrome = showsOwnedChrome
        self.axis = axis
    }

    public var body: some View {
        Group {
            if axis == .vertical { verticalBody } else { horizontalBody }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Fader" : label)
        .accessibilityValue("\(percent)%")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: value = min(1, clamped + 0.05)
            case .decrement: value = max(0, clamped - 0.05)
            @unknown default: break
            }
        }
    }

    private var verticalBody: some View {
        VStack(spacing: 4) {
            if !label.isEmpty || iconName != nil {
                HStack(spacing: 3) {
                    if let iconName {
                        AuroraAssetIcon(name: iconName, size: 11)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                    if !label.isEmpty {
                        Text(label.uppercased())
                            .font(AuroraTypography.controlLabel)
                            .foregroundStyle(AuroraColor.textTertiary)
                            .tracking(0.5)
                    }
                }
            }
            Text("\(percent)%")
                .font(AuroraTypography.faderValue)
                .foregroundStyle(showsOwnedChrome ? AuroraColor.accentBright : AuroraColor.textPrimary)

            GeometryReader { geo in
                let h = geo.size.height
                let y = (1 - CGFloat(clamped)) * h
                ZStack {
                    Capsule()
                        .fill(AuroraColor.surfaceWell)
                        .frame(width: AuroraMetrics.faderTrackWidth + 4)
                        .overlay(Capsule().strokeBorder(AuroraColor.separatorStrong, lineWidth: 0.5))
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AuroraColor.accentBright, AuroraColor.accent],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: AuroraMetrics.faderTrackWidth, height: max(6, h - y))
                            .shadow(color: AuroraColor.accent.opacity(0.45), radius: 4, y: 0)
                    }
                    Capsule()
                        .fill(AuroraColor.textPrimary)
                        .frame(width: AuroraMetrics.faderThumbWidth, height: AuroraMetrics.faderThumbHeight)
                        .overlay(
                            Capsule().strokeBorder(isFocused ? AuroraColor.focusRing : Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .position(x: geo.size.width / 2, y: min(h - 4, max(4, y)))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(drag(size: geo.size, vertical: true))
            }
            .frame(width: AuroraMetrics.faderWidth, height: density == .performance ? 160 : AuroraMetrics.faderHeight)

            if showsOwnedChrome {
                Circle()
                    .fill(AuroraColor.stateOwned)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var horizontalBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                Spacer()
                Text("\(percent)%")
                    .font(AuroraTypography.primaryValue)
                    .foregroundStyle(AuroraColor.textPrimary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                let x = CGFloat(clamped) * w
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AuroraColor.surfaceWell)
                        .frame(height: AuroraMetrics.masterTrackHeight + 2)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AuroraColor.masterTrack, AuroraColor.accentBright],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, x), height: AuroraMetrics.masterTrackHeight)
                    Circle()
                        .fill(AuroraColor.textPrimary)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(isFocused ? AuroraColor.focusRing : Color.clear, lineWidth: 1))
                        .position(x: min(w - 6, max(6, x)), y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(drag(size: geo.size, vertical: false))
            }
            .frame(height: 18)
        }
    }

    private func drag(size: CGSize, vertical: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard isEnabled else { return }
                if vertical {
                    value = min(1, max(0, Double(1 - drag.location.y / max(size.height, 1))))
                } else {
                    value = min(1, max(0, Double(drag.location.x / max(size.width, 1))))
                }
            }
    }

    private var clamped: Double { min(1, max(0, value)) }
    private var percent: Int { Int((clamped * 100).rounded()) }
}
