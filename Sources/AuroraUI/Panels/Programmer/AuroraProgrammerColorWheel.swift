import AuroraEngine
import SwiftUI

/// LightKey-style Color Engine wheel: hue ring, saturation annulus, center preview,
/// split inner character ring (WB left / brightness right).
public struct AuroraProgrammerColorWheel: View {
    @Binding public var hue: Double // 0...360
    @Binding public var saturation: Double // 0...1
    @Binding public var brightness: Double // 0...1
    @Binding public var whiteBalance: Double // -1...1
    public var previewRGB: AuroraEngine.RGBColor
    public var size: CGFloat
    public var isMixed: Bool
    public var onLiveEdit: () -> Void

    @State private var activeDragTarget: ColorWheelDragTarget?
    @State private var hoveredSelector: ColorWheelDragTarget?

    public init(
        hue: Binding<Double>,
        saturation: Binding<Double>,
        brightness: Binding<Double>,
        whiteBalance: Binding<Double>,
        previewRGB: AuroraEngine.RGBColor,
        size: CGFloat = 240,
        isMixed: Bool = false,
        onLiveEdit: @escaping () -> Void = {}
    ) {
        self._hue = hue
        self._saturation = saturation
        self._brightness = brightness
        self._whiteBalance = whiteBalance
        self.previewRGB = previewRGB
        self.size = size
        self.isMixed = isMixed
        self.onLiveEdit = onLiveEdit
    }

    private var outerRingWidth: CGFloat { size * 0.12 }
    private var innerRingOuter: CGFloat { size * 0.62 }
    private var innerRingInner: CGFloat { size * 0.38 }
    private var previewSize: CGFloat { size * 0.30 }

    /// Outside of character ring (sat ≈ 0).
    private var innerSatRadius: CGFloat { innerRingOuter / 2 + 2 }
    /// Inside of hue ring (sat ≈ 1).
    private var outerSatRadius: CGFloat { size / 2 - outerRingWidth }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: hueGradientColors,
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    lineWidth: outerRingWidth
                )
                .frame(width: size, height: size)

            // Visible saturation annulus fill (low sat at inner edge)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color(hue: hue / 360, saturation: 1, brightness: 1),
                        ],
                        center: .center,
                        startRadius: innerSatRadius,
                        endRadius: outerSatRadius
                    )
                )
                .frame(width: outerSatRadius * 2, height: outerSatRadius * 2)
                .mask(
                    Circle()
                        .stroke(lineWidth: max(1, outerSatRadius - innerSatRadius))
                        .frame(width: (innerSatRadius + outerSatRadius), height: (innerSatRadius + outerSatRadius))
                )

            characterRing
                .frame(width: innerRingOuter, height: innerRingOuter)

            // Center preview
            Group {
                if isMixed {
                    mixedPreview
                } else {
                    Circle()
                        .fill(Color(red: previewRGB.r, green: previewRGB.g, blue: previewRGB.b))
                        .frame(width: previewSize, height: previewSize)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                }
            }
            .accessibilityLabel("Color preview")
            .accessibilityValue(isMixed ? "mixed" : String(
                format: "R %.0f%% G %.0f%% B %.0f%%",
                previewRGB.r * 100, previewRGB.g * 100, previewRGB.b * 100
            ))

            if let hoveredSelector {
                Text(hoveredSelector.displayName.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.45)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if !isMixed {
                hueMarker
                satThumb
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(wheelDragGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color wheel")
    }

    private var mixedPreview: some View {
        ZStack {
            Circle()
                .fill(AuroraColor.surfaceRaised)
                .frame(width: previewSize, height: previewSize)
            // Quartered mixed indication
            Canvas { ctx, sz in
                let r = min(sz.width, sz.height) / 2
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let colors: [Color] = [.red, .green, .blue, .yellow]
                for i in 0..<4 {
                    var path = Path()
                    path.move(to: c)
                    path.addArc(
                        center: c,
                        radius: r,
                        startAngle: .degrees(Double(i) * 90 - 90),
                        endAngle: .degrees(Double(i + 1) * 90 - 90),
                        clockwise: false
                    )
                    path.closeSubpath()
                    ctx.fill(path, with: .color(colors[i].opacity(0.75)))
                }
            }
            .frame(width: previewSize, height: previewSize)
            .clipShape(Circle())
            Text("MIXED")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(radius: 1)
            Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: previewSize, height: previewSize)
        }
    }

    private var hueGradientColors: [Color] {
        (0...12).map { i in
            Color(hue: Double(i) / 12.0, saturation: 1, brightness: 1)
        }
    }

    private var characterRing: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.5)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: previewRGB.r, green: previewRGB.g, blue: previewRGB.b),
                            Color.black,
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(90)
                    ),
                    style: StrokeStyle(lineWidth: (innerRingOuter - innerRingInner) * 0.55, lineCap: .butt)
                )
                .rotationEffect(.degrees(90))

            Circle()
                .trim(from: 0.0, to: 0.5)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.75, green: 0.88, blue: 1.0),
                            Color.white,
                            Color(red: 1.0, green: 0.78, blue: 0.45),
                        ],
                        center: .center,
                        startAngle: .degrees(90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: (innerRingOuter - innerRingInner) * 0.55, lineCap: .butt)
                )
                .rotationEffect(.degrees(90))

            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) / 24.0 * 360.0
                Capsule()
                    .fill(Color.white.opacity(i % 6 == 0 ? 0.45 : 0.18))
                    .frame(width: 1.5, height: i % 6 == 0 ? 8 : 4)
                    .offset(y: -(innerRingOuter + innerRingInner) / 4 - 2)
                    .rotationEffect(.degrees(angle))
            }

            characterMarker(
                angleDegrees: ColorMath.brightnessAngleDegrees(brightness),
                color: .white,
                target: .brightness
            )
            characterMarker(
                angleDegrees: ColorMath.whiteBalanceAngleDegrees(whiteBalance),
                color: Color(red: 1, green: 0.85, blue: 0.55),
                target: .whiteBalance
            )
        }
    }

    private func characterMarker(
        angleDegrees: Double,
        color: Color,
        target: ColorWheelDragTarget
    ) -> some View {
        let rad = angleDegrees * .pi / 180
        let radius = (innerRingOuter + innerRingInner) / 4
        let x = cos(rad) * radius
        let y = sin(rad) * radius
        return Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.72), lineWidth: 1.5))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 0.75).padding(2))
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .contentShape(Circle())
            .offset(x: x, y: y)
            .onHover { hovering in
                if hovering {
                    hoveredSelector = target
                } else if hoveredSelector == target {
                    hoveredSelector = nil
                }
            }
            .help(target.displayName)
            .accessibilityLabel(target.displayName)
    }

    private var hueMarker: some View {
        let angle = (hue - 90) * .pi / 180
        let r = size / 2 - outerRingWidth / 2
        return Image(systemName: "triangle.fill")
            .font(.system(size: 9))
            .foregroundStyle(Color(hue: hue / 360, saturation: 1, brightness: 1))
            .rotationEffect(.degrees(hue))
            .offset(x: cos(angle) * r, y: sin(angle) * r)
    }

    private var satThumb: some View {
        let angle = (hue - 90) * .pi / 180
        let r = ColorMath.saturationThumbRadius(
            saturation: saturation,
            innerSatRadius: Double(innerSatRadius),
            outerSatRadius: Double(outerSatRadius)
        )
        return Circle()
            .fill(Color(red: previewRGB.r, green: previewRGB.g, blue: previewRGB.b))
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.36), lineWidth: 0.75).padding(3))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .contentShape(Circle())
            .offset(x: cos(angle) * r, y: sin(angle) * r)
            .onHover { hovering in
                if hovering {
                    hoveredSelector = .hueSaturation
                } else if hoveredSelector == .hueSaturation {
                    hoveredSelector = nil
                }
            }
            .help(ColorWheelDragTarget.hueSaturation.displayName)
            .accessibilityLabel(ColorWheelDragTarget.hueSaturation.displayName)
    }

    private var wheelDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let target = ColorWheelInteraction.lockedTarget(
                    active: activeDragTarget,
                    startTarget: dragTarget(at: drag.startLocation)
                )
                if activeDragTarget == nil {
                    activeDragTarget = target
                }
                let mid = size / 2
                let dx = Double(drag.location.x - mid)
                let dy = Double(drag.location.y - mid)
                let dist = sqrt(dx * dx + dy * dy)
                let innerSat = Double(innerSatRadius)
                let outerSat = Double(outerSatRadius)

                switch target {
                case .brightness:
                    let angle = atan2(dy, dx) * 180 / .pi
                    brightness = ColorMath.brightness(fromAngleDegrees: angle)
                    onLiveEdit()
                case .whiteBalance:
                    let angle = atan2(dy, dx) * 180 / .pi
                    whiteBalance = ColorMath.whiteBalance(fromAngleDegrees: angle)
                    onLiveEdit()
                case .hueSaturation:
                    hue = ColorMath.hue(dx: dx, dy: dy)
                    saturation = ColorMath.saturationInAnnulus(
                        pointerRadius: dist,
                        innerSatRadius: innerSat,
                        outerSatRadius: outerSat
                    )
                    onLiveEdit()
                case .none:
                    break
                }
            }
            .onEnded { _ in
                activeDragTarget = nil
            }
    }

    private func dragTarget(at location: CGPoint) -> ColorWheelDragTarget? {
        ColorWheelInteraction.dragTarget(
            at: location,
            size: size,
            brightnessAngle: ColorMath.brightnessAngleDegrees(brightness),
            whiteBalanceAngle: ColorMath.whiteBalanceAngleDegrees(whiteBalance),
            characterRadius: (innerRingOuter + innerRingInner) / 4,
            characterInnerRadius: innerRingInner / 2,
            characterOuterRadius: innerRingOuter / 2,
            innerSaturationRadius: innerSatRadius,
            outerRadius: size / 2
        )
    }
}

enum ColorWheelDragTarget: Equatable {
    case hueSaturation
    case brightness
    case whiteBalance

    var displayName: String {
        switch self {
        case .hueSaturation: return "Hue / Saturation"
        case .brightness: return "Brightness"
        case .whiteBalance: return "White Balance"
        }
    }
}

enum ColorWheelInteraction {
    static let selectorHitRadius: CGFloat = 16

    /// Once mouse-down chooses a selector, pointer movement cannot transfer
    /// ownership to another selector. The view clears `active` only on mouse-up.
    static func lockedTarget(
        active: ColorWheelDragTarget?,
        startTarget: ColorWheelDragTarget?
    ) -> ColorWheelDragTarget? {
        active ?? startTarget
    }

    static func dragTarget(
        at location: CGPoint,
        size: CGFloat,
        brightnessAngle: Double,
        whiteBalanceAngle: Double,
        characterRadius: CGFloat,
        characterInnerRadius: CGFloat,
        characterOuterRadius: CGFloat,
        innerSaturationRadius: CGFloat,
        outerRadius: CGFloat
    ) -> ColorWheelDragTarget? {
        let center = CGPoint(x: size / 2, y: size / 2)
        let brightnessCenter = selectorCenter(center: center, radius: characterRadius, angle: brightnessAngle)
        let whiteBalanceCenter = selectorCenter(center: center, radius: characterRadius, angle: whiteBalanceAngle)
        let brightnessDistance = distance(location, brightnessCenter)
        let whiteBalanceDistance = distance(location, whiteBalanceCenter)

        if min(brightnessDistance, whiteBalanceDistance) <= selectorHitRadius {
            return brightnessDistance <= whiteBalanceDistance ? .brightness : .whiteBalance
        }

        let pointerRadius = distance(location, center)
        if pointerRadius >= characterInnerRadius * 0.85,
           pointerRadius <= characterOuterRadius * 1.08 {
            let dx = Double(location.x - center.x)
            let dy = Double(location.y - center.y)
            let angle = atan2(dy, dx) * 180 / .pi
            return abs(angle) <= 95 ? .brightness : .whiteBalance
        }
        if pointerRadius >= innerSaturationRadius * 0.92, pointerRadius <= outerRadius {
            return .hueSaturation
        }
        return nil
    }

    private static func selectorCenter(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
