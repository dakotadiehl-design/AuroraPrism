import SwiftUI

/// HSV color disc for Programmer gallery (pure UI, no engine).
public struct AuroraColorWheel: View {
    @Binding public var hue: Double
    @Binding public var saturation: Double
    public var brightness: Double
    public var size: CGFloat
    /// When true, do not show a concrete owned thumb position (UI-03 Pass 2).
    public var isMixed: Bool

    public init(
        hue: Binding<Double>,
        saturation: Binding<Double>,
        brightness: Double = 1,
        size: CGFloat = AuroraMetrics.colorWheelSize,
        isMixed: Bool = false
    ) {
        self._hue = hue
        self._saturation = saturation
        self.brightness = brightness
        self.size = size
        self.isMixed = isMixed
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                AuroraAssetIcon(.colorWheel, size: 11)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text("COLOR")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(0.5)
            }

            ZStack {
                // Spectrum ring via angular gradient
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hue: 0, saturation: 1, brightness: 1),
                                Color(hue: 0.1, saturation: 1, brightness: 1),
                                Color(hue: 0.2, saturation: 1, brightness: 1),
                                Color(hue: 0.35, saturation: 1, brightness: 1),
                                Color(hue: 0.5, saturation: 1, brightness: 1),
                                Color(hue: 0.65, saturation: 1, brightness: 1),
                                Color(hue: 0.75, saturation: 1, brightness: 1),
                                Color(hue: 0.85, saturation: 1, brightness: 1),
                                Color(hue: 1, saturation: 1, brightness: 1),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)

                // Saturation falloff to center
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.45
                        )
                    )
                    .frame(width: size * 0.92, height: size * 0.92)

                // Selection thumb — indeterminate when mixed
                if isMixed {
                    Circle()
                        .strokeBorder(AuroraColor.stateMixed, lineWidth: 2)
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(thumbOffset)
                }

                Circle()
                    .strokeBorder(AuroraColor.separatorStrong, lineWidth: 1)
                    .frame(width: size, height: size)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let mid = size / 2
                        let dx = drag.location.x - mid
                        let dy = drag.location.y - mid
                        let angle = atan2(dy, dx) // -π...π
                        var h = (angle / (2 * .pi)) + 0.5
                        if h < 0 { h += 1 }
                        if h > 1 { h -= 1 }
                        hue = h
                        let r = sqrt(dx * dx + dy * dy) / (size * 0.45)
                        saturation = min(1, max(0, r))
                    }
            )

            // Active chip + RGB
            HStack(spacing: 8) {
                if isMixed {
                    Text("MIXED")
                        .font(AuroraTypography.timingReadout)
                        .foregroundStyle(AuroraColor.stateMixed)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 28, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                    let rgb = rgbComponents
                    Text("R \(rgb.0)")
                        .font(AuroraTypography.timingReadout)
                        .foregroundStyle(AuroraColor.textSecondary)
                    Text("G \(rgb.1)")
                        .font(AuroraTypography.timingReadout)
                        .foregroundStyle(AuroraColor.textSecondary)
                    Text("B \(rgb.2)")
                        .font(AuroraTypography.timingReadout)
                        .foregroundStyle(AuroraColor.textSecondary)
                }
            }
        }
    }

    private var thumbOffset: CGSize {
        let angle = (hue - 0.5) * 2 * .pi
        let r = saturation * (size * 0.42)
        return CGSize(width: cos(angle) * r, height: sin(angle) * r)
    }

    private var rgbComponents: (Int, Int, Int) {
        let h = hue
        let s = saturation
        let v = brightness
        let i = floor(h * 6)
        let f = h * 6 - i
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        let (r, g, b): (Double, Double, Double)
        switch Int(i) % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return (Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
