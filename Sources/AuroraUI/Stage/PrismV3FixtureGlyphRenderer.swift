import AuroraDesignSystem
import AuroraEngine
import AuroraModel
import SwiftUI

enum PrismV3GlyphStyle {
    static let chassis = Color(red: 0.055, green: 0.065, blue: 0.072)
    static let chassisRaised = Color(red: 0.095, green: 0.105, blue: 0.11)
    static let hardware = Color.white.opacity(0.62)
    static let hardwareMuted = Color.white.opacity(0.25)
    static let idleLens = Color(red: 0.035, green: 0.04, blue: 0.045)
    static let selection = AuroraColor.accentBright

    static func hardwareLine(detailLevel: Int) -> CGFloat {
        detailLevel >= 2 ? 1.0 : 0.8
    }

    static func bloomRadius(intensity: Double, detailLevel: Int) -> CGFloat {
        guard detailLevel > 0 else { return 0 }
        return CGFloat(max(0, intensity - 0.08)) * (detailLevel >= 2 ? 7 : 4)
    }

    static func bloomOpacity(intensity: Double) -> Double {
        max(0, intensity - 0.12) * 0.52
    }
}

/// Flat, plan-view V3 artwork. All semantic aperture locations and identities
/// come directly from `FixtureGlyphGeometry`.
public struct PrismV3FixtureGlyphRenderer: View {
    public var descriptor: FixtureVisualizationDescriptor
    public var geometry: FixtureGlyphGeometry
    public var liveEmitters: [FixtureElementPreviewState]
    public var selectedEmitterIDs: Set<String>
    public var affectedEmitterIDs: Set<String>
    public var wholeSelected: Bool
    public var atmosphericLevel: Double
    public var detailLevel: Int

    public init(
        descriptor: FixtureVisualizationDescriptor,
        geometry: FixtureGlyphGeometry,
        liveEmitters: [FixtureElementPreviewState] = [],
        selectedEmitterIDs: Set<String> = [],
        affectedEmitterIDs: Set<String> = [],
        wholeSelected: Bool = false,
        atmosphericLevel: Double = 0,
        detailLevel: Int = 1
    ) {
        self.descriptor = descriptor
        self.geometry = geometry
        self.liveEmitters = liveEmitters
        self.selectedEmitterIDs = selectedEmitterIDs
        self.affectedEmitterIDs = affectedEmitterIDs
        self.wholeSelected = wholeSelected
        self.atmosphericLevel = atmosphericLevel
        self.detailLevel = detailLevel
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            chassis
            familyHardware
            ForEach(geometry.apertures) { aperture in
                lens(aperture)
            }
            if detailLevel > 0 { orientationMarker }
            if wholeSelected { parentSelection }
        }
        .frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private var lineWidth: CGFloat { PrismV3GlyphStyle.hardwareLine(detailLevel: detailLevel) }

    @ViewBuilder private var chassis: some View {
        switch descriptor.form {
        case .par, .fresnel:
            Circle()
                .fill(PrismV3GlyphStyle.chassis)
                .overlay(Circle().stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
                .padding(1)
        case .profile:
            planProfileBody
        case .linearBar, .strip, .multiHeadBar:
            RoundedRectangle(cornerRadius: min(5, geometry.bodyBounds.height * 0.13))
                .fill(PrismV3GlyphStyle.chassis)
                .overlay(RoundedRectangle(cornerRadius: min(5, geometry.bodyBounds.height * 0.13)).stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
        case .movingHead:
            planMovingHeadBody
        case .scanner:
            RoundedRectangle(cornerRadius: 4)
                .fill(PrismV3GlyphStyle.chassis)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
        case .atmospheric, .laser, .projector, .practical, .effect, .generic:
            RoundedRectangle(cornerRadius: 5)
                .fill(PrismV3GlyphStyle.chassis)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
        case .panel, .blinder, .strobe:
            RoundedRectangle(cornerRadius: 3)
                .fill(PrismV3GlyphStyle.chassis)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
        }
    }

    private var planProfileBody: some View {
        Path { path in
            let b = geometry.bodyBounds.insetBy(dx: 1, dy: 2)
            path.move(to: CGPoint(x: b.minX, y: b.midY - b.height * 0.28))
            path.addLine(to: CGPoint(x: b.midX + b.width * 0.18, y: b.minY))
            path.addLine(to: CGPoint(x: b.maxX, y: b.minY + b.height * 0.23))
            path.addLine(to: CGPoint(x: b.maxX, y: b.maxY - b.height * 0.23))
            path.addLine(to: CGPoint(x: b.midX + b.width * 0.18, y: b.maxY))
            path.addLine(to: CGPoint(x: b.minX, y: b.midY + b.height * 0.28))
            path.closeSubpath()
        }
        .fill(PrismV3GlyphStyle.chassis)
        .overlay(
            Path { path in
                let b = geometry.bodyBounds.insetBy(dx: 1, dy: 2)
                path.move(to: CGPoint(x: b.minX, y: b.midY - b.height * 0.28))
                path.addLine(to: CGPoint(x: b.midX + b.width * 0.18, y: b.minY))
                path.addLine(to: CGPoint(x: b.maxX, y: b.minY + b.height * 0.23))
                path.addLine(to: CGPoint(x: b.maxX, y: b.maxY - b.height * 0.23))
                path.addLine(to: CGPoint(x: b.midX + b.width * 0.18, y: b.maxY))
                path.addLine(to: CGPoint(x: b.minX, y: b.midY + b.height * 0.28))
                path.closeSubpath()
            }.stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth)
        )
    }

    private var planMovingHeadBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(PrismV3GlyphStyle.chassis)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
                .frame(width: geometry.bodyBounds.width * 0.8, height: geometry.bodyBounds.height * 0.26)
                .offset(y: geometry.bodyBounds.height * 0.31)
            RoundedRectangle(cornerRadius: 4)
                .stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
                .frame(width: geometry.bodyBounds.width * 0.72, height: geometry.bodyBounds.height * 0.7)
            Circle()
                .fill(PrismV3GlyphStyle.chassisRaised)
                .overlay(Circle().stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
                .frame(width: geometry.bodyBounds.height * 0.62, height: geometry.bodyBounds.height * 0.62)
                .offset(y: -geometry.bodyBounds.height * 0.08)
        }
    }

    @ViewBuilder private var familyHardware: some View {
        switch descriptor.form {
        case .par, .fresnel:
            if detailLevel >= 2 {
                Circle().stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
                    .frame(width: geometry.bodyBounds.width * 0.78, height: geometry.bodyBounds.height * 0.78)
                    .position(x: geometry.bodyBounds.midX, y: geometry.bodyBounds.midY)
            }
        case .linearBar, .strip:
            if detailLevel >= 2 { barMounts }
        case .multiHeadBar:
            multiHeadHardware
        case .movingHead:
            EmptyView()
        case .scanner:
            scannerMirror
        case .strobe, .blinder, .panel:
            panelHardware
        case .laser:
            laserAperture
        case .atmospheric:
            atmosphericHardware
        case .projector, .practical, .effect, .generic, .profile:
            genericHardware
        }
    }

    private var barMounts: some View {
        HStack {
            mountTab
            Spacer()
            mountTab
        }
        .padding(.horizontal, 5)
        .frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
    }

    private var mountTab: some View {
        RoundedRectangle(cornerRadius: 1)
            .stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
            .frame(width: 5, height: max(4, geometry.bodyBounds.height * 0.25))
    }

    private var multiHeadHardware: some View {
        ForEach(Array((geometry.headCenters.isEmpty ? geometry.apertures.map(\.center) : geometry.headCenters).enumerated()), id: \.offset) { _, center in
            Path { path in
                path.move(to: CGPoint(x: center.x, y: geometry.bodyBounds.maxY * 0.72))
                path.addLine(to: CGPoint(x: center.x, y: center.y + 3))
            }
            .stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
        }
    }

    private var scannerMirror: some View {
        RoundedRectangle(cornerRadius: 1)
            .stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth)
            .frame(width: geometry.bodyBounds.width * 0.34, height: geometry.bodyBounds.height * 0.2)
            .rotationEffect(.degrees(-18))
            .position(x: geometry.bodyBounds.width * 0.72, y: geometry.bodyBounds.midY)
    }

    private var panelHardware: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
            .padding(4)
    }

    private var laserAperture: some View {
        Circle()
            .fill(Color.red.opacity(0.55))
            .overlay(Circle().stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth))
            .frame(width: 7, height: 7)
            .position(x: geometry.bodyBounds.width * 0.25, y: geometry.bodyBounds.midY)
    }

    private var atmosphericHardware: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
                .frame(width: geometry.bodyBounds.width * 0.45, height: geometry.bodyBounds.height * 0.18)
                .position(x: geometry.bodyBounds.width * 0.58, y: geometry.bodyBounds.height * 0.35)
            Circle()
                .stroke(PrismV3GlyphStyle.hardware, lineWidth: lineWidth)
                .frame(width: 7, height: 7)
                .position(x: geometry.bodyBounds.width * 0.18, y: geometry.bodyBounds.midY)
            if detailLevel >= 2 {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(PrismV3GlyphStyle.hardwareMuted).frame(width: geometry.bodyBounds.width * 0.28, height: 1)
                    }
                }
                .position(x: geometry.bodyBounds.width * 0.7, y: geometry.bodyBounds.height * 0.65)
            }
            if atmosphericLevel > 0.01 {
                Circle().fill(Color.white.opacity(min(0.35, atmosphericLevel * 0.35)))
                    .frame(width: 8, height: 8)
                    .blur(radius: 2)
                    .position(x: geometry.bodyBounds.width * 0.1, y: geometry.bodyBounds.midY)
            }
        }
    }

    private var genericHardware: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(PrismV3GlyphStyle.hardwareMuted, lineWidth: lineWidth)
            .padding(4)
    }

    private func lens(_ aperture: FixtureGlyphApertureGeometry) -> some View {
        let state = liveEmitters.first { $0.elementID == aperture.id }
        let color = state?.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .white
        let intensity = min(1, max(0, state?.intensity ?? 0))
        let selected = selectedEmitterIDs.contains(aperture.id)
        let affected = affectedEmitterIDs.contains(aperture.id)
        let cornerRadius: CGFloat = aperture.shape == .circle ? min(aperture.bounds.width, aperture.bounds.height) / 2 : (aperture.shape == .roundedRectangle ? 3 : 0)
        return ZStack {
            if intensity > 0.08, detailLevel > 0 {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color.opacity(PrismV3GlyphStyle.bloomOpacity(intensity: intensity)))
                    .blur(radius: PrismV3GlyphStyle.bloomRadius(intensity: intensity, detailLevel: detailLevel))
                    .padding(-CGFloat(intensity * 2.5))
            }
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    RadialGradient(
                        colors: lensColors(color: color, intensity: intensity),
                        center: .center,
                        startRadius: 0,
                        endRadius: max(2, min(aperture.bounds.width, aperture.bounds.height) / 2)
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(PrismV3GlyphStyle.hardware.opacity(0.9), lineWidth: lineWidth)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: max(0, cornerRadius - 2))
                        .stroke(Color.white.opacity(detailLevel >= 2 ? 0.24 : 0), lineWidth: 0.7)
                        .padding(2)
                )
            if selected || affected {
                RoundedRectangle(cornerRadius: cornerRadius + 1)
                    .stroke(selected ? PrismV3GlyphStyle.selection : Color.orange.opacity(0.9), lineWidth: selected ? 2.4 : 1.8)
                    .padding(-2)
            }
        }
        .frame(width: aperture.bounds.width, height: aperture.bounds.height)
        .position(aperture.center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lensColors(color: Color, intensity: Double) -> [Color] {
        guard intensity > 0.001 else {
            return [Color.white.opacity(0.08), PrismV3GlyphStyle.idleLens]
        }
        let coreOpacity = min(1, 0.48 + intensity * 0.52)
        return [Color.white.opacity(max(0, intensity - 0.78) * 0.7), color.opacity(coreOpacity), color.opacity(0.22 + intensity * 0.58)]
    }

    private var orientationMarker: some View {
        Path { path in
            let p = geometry.orientationReference
            path.move(to: CGPoint(x: p.x, y: p.y - 3))
            path.addLine(to: CGPoint(x: p.x - 3.5, y: p.y + 3))
            path.addLine(to: CGPoint(x: p.x + 3.5, y: p.y + 3))
            path.closeSubpath()
        }
        .fill(PrismV3GlyphStyle.selection.opacity(0.95))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var parentSelection: some View {
        switch descriptor.form {
        case .par, .fresnel:
            Circle().stroke(PrismV3GlyphStyle.selection, lineWidth: 2).padding(-2)
        default:
            RoundedRectangle(cornerRadius: 6).stroke(PrismV3GlyphStyle.selection, lineWidth: 2).padding(-2)
        }
    }
}
