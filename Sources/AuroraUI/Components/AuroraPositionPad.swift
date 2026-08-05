import SwiftUI

/// Dark crosshair position pad with pan/tilt readouts.
public struct AuroraPositionPad: View {
    @Binding public var pan: Double
    @Binding public var tilt: Double
    public var isEnabled: Bool

    public init(pan: Binding<Double>, tilt: Binding<Double>, isEnabled: Bool = true) {
        self._pan = pan
        self._tilt = tilt
        self.isEnabled = isEnabled
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                AuroraAssetIcon(.panTilt, size: 11)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text("POSITION")
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
                    // Crosshair
                    Path { path in
                        path.move(to: CGPoint(x: size / 2, y: 8))
                        path.addLine(to: CGPoint(x: size / 2, y: size - 8))
                        path.move(to: CGPoint(x: 8, y: size / 2))
                        path.addLine(to: CGPoint(x: size - 8, y: size / 2))
                    }
                    .stroke(AuroraColor.separatorStrong, lineWidth: 1)

                    Circle()
                        .fill(AuroraColor.accentBright)
                        .frame(width: 10, height: 10)
                        .shadow(color: AuroraColor.accent.opacity(0.6), radius: 4)
                        .position(
                            x: CGFloat(pan) * size,
                            y: (1 - CGFloat(tilt)) * size
                        )
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard isEnabled else { return }
                            pan = min(1, max(0, Double(drag.location.x / size)))
                            tilt = min(1, max(0, Double(1 - drag.location.y / size)))
                        }
                )
            }
            .frame(width: AuroraMetrics.positionPadSize, height: AuroraMetrics.positionPadSize)
            .opacity(isEnabled ? 1 : 0.4)

            HStack(spacing: 12) {
                Text("PAN \(Int(pan * 270 - 135))°")
                    .font(AuroraTypography.timingReadout)
                    .foregroundStyle(AuroraColor.textSecondary)
                Text("TILT \(Int(tilt * 90))°")
                    .font(AuroraTypography.timingReadout)
                    .foregroundStyle(AuroraColor.textSecondary)
            }
        }
    }
}
