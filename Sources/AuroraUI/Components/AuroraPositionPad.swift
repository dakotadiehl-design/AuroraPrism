import AuroraDesignSystem
import SwiftUI

/// Position pad with independent pan/tilt capability and mixed display (UI-03 Pass 2).
public struct AuroraPositionPad: View {
    @Binding public var pan: Double
    @Binding public var tilt: Double
    public var supportsPan: Bool
    public var supportsTilt: Bool
    public var panDisplay: AuroraControlDisplayValue
    public var tiltDisplay: AuroraControlDisplayValue
    public var isEnabled: Bool

    public init(
        pan: Binding<Double>,
        tilt: Binding<Double>,
        supportsPan: Bool = true,
        supportsTilt: Bool = true,
        panDisplay: AuroraControlDisplayValue = .value(0.5),
        tiltDisplay: AuroraControlDisplayValue = .value(0.5),
        isEnabled: Bool = true
    ) {
        self._pan = pan
        self._tilt = tilt
        self.supportsPan = supportsPan
        self.supportsTilt = supportsTilt
        self.panDisplay = panDisplay
        self.tiltDisplay = tiltDisplay
        self.isEnabled = isEnabled
    }

    private var panMixed: Bool {
        if case .mixed = panDisplay { return true }
        return false
    }

    private var tiltMixed: Bool {
        if case .mixed = tiltDisplay { return true }
        return false
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                AuroraAssetIcon(.panTilt, size: 11)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text(titleText)
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(0.5)
            }

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous)
                        .fill(AuroraColor.surfaceWell)
                        .overlay(
                            RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous)
                                .strokeBorder(AuroraColor.separatorStrong, lineWidth: 0.5)
                        )

                    // Axis guides: only emphasize supported axes
                    if supportsPan {
                        Path { path in
                            path.move(to: CGPoint(x: 8, y: size / 2))
                            path.addLine(to: CGPoint(x: size - 8, y: size / 2))
                        }
                        .stroke(
                            panMixed ? AuroraColor.stateMixed.opacity(0.6) : AuroraColor.separatorStrong,
                            style: StrokeStyle(lineWidth: supportsTilt ? 1 : 2, dash: panMixed ? [4, 3] : [])
                        )
                    }
                    if supportsTilt {
                        Path { path in
                            path.move(to: CGPoint(x: size / 2, y: 8))
                            path.addLine(to: CGPoint(x: size / 2, y: size - 8))
                        }
                        .stroke(
                            tiltMixed ? AuroraColor.stateMixed.opacity(0.6) : AuroraColor.separatorStrong,
                            style: StrokeStyle(lineWidth: supportsPan ? 1 : 2, dash: tiltMixed ? [4, 3] : [])
                        )
                    }

                    // Unsupported axis wash (visually one-axis)
                    if supportsPan, !supportsTilt {
                        // Dim top/bottom bands to de-emphasize vertical
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.black.opacity(0.25))
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.black.opacity(0.25))
                        }
                        .frame(width: size, height: size)
                        .allowsHitTesting(false)
                    }
                    if supportsTilt, !supportsPan {
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.black.opacity(0.25))
                            Spacer(minLength: 0)
                            Rectangle().fill(Color.black.opacity(0.25))
                        }
                        .frame(width: size, height: size)
                        .allowsHitTesting(false)
                    }

                    targetView(size: size)
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard isEnabled else { return }
                            if supportsPan, panDisplay.isInteractive {
                                pan = min(1, max(0, Double(drag.location.x / size)))
                            }
                            if supportsTilt, tiltDisplay.isInteractive {
                                tilt = min(1, max(0, Double(1 - drag.location.y / size)))
                            }
                        }
                )
            }
            .frame(width: AuroraMetrics.positionPadSize, height: AuroraMetrics.positionPadSize)
            .opacity(isEnabled ? 1 : 0.4)

            HStack(spacing: 12) {
                Text(panReadout)
                    .font(AuroraTypography.timingReadout)
                    .foregroundStyle(supportsPan ? (panMixed ? AuroraColor.stateMixed : AuroraColor.textSecondary) : AuroraColor.textTertiary.opacity(0.4))
                Text(tiltReadout)
                    .font(AuroraTypography.timingReadout)
                    .foregroundStyle(supportsTilt ? (tiltMixed ? AuroraColor.stateMixed : AuroraColor.textSecondary) : AuroraColor.textTertiary.opacity(0.4))
            }
        }
    }

    private var titleText: String {
        switch (supportsPan, supportsTilt) {
        case (true, true): return "POSITION"
        case (true, false): return "PAN"
        case (false, true): return "TILT"
        default: return "POSITION"
        }
    }

    @ViewBuilder
    private func targetView(size: CGFloat) -> some View {
        let px: CGFloat = {
            if !supportsPan { return size / 2 }
            if panMixed { return size / 2 }
            if case .value(let v) = panDisplay { return CGFloat(v) * size }
            return CGFloat(pan) * size
        }()
        let py: CGFloat = {
            if !supportsTilt { return size / 2 }
            if tiltMixed { return size / 2 }
            if case .value(let v) = tiltDisplay { return (1 - CGFloat(v)) * size }
            return (1 - CGFloat(tilt)) * size
        }()

        let anyMixed = (supportsPan && panMixed) || (supportsTilt && tiltMixed)
        if anyMixed {
            Circle()
                .strokeBorder(AuroraColor.stateMixed, lineWidth: 2)
                .frame(width: 14, height: 14)
                .position(x: px, y: py)
        } else if supportsPan || supportsTilt {
            Circle()
                .fill(AuroraColor.accentBright)
                .frame(width: 10, height: 10)
                .shadow(color: AuroraColor.accent.opacity(0.6), radius: 4)
                .position(x: px, y: py)
        }
    }

    private var panReadout: String {
        guard supportsPan else { return "PAN —" }
        if panMixed { return "PAN MIXED" }
        let v = panDisplay.concreteValue ?? pan
        return "PAN \(Int(v * 270 - 135))°"
    }

    private var tiltReadout: String {
        guard supportsTilt else { return "TILT —" }
        if tiltMixed { return "TILT MIXED" }
        let v = tiltDisplay.concreteValue ?? tilt
        return "TILT \(Int(v * 90))°"
    }
}
