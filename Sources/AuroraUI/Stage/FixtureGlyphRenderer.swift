import AuroraDesignSystem
import AuroraEngine
import AuroraModel
import SwiftUI

public struct FixtureGlyphRenderer: View {
    public var descriptor: FixtureVisualizationDescriptor
    public var geometry: FixtureGlyphGeometry
    public var liveEmitters: [FixtureElementPreviewState]
    public var selectedEmitterIDs: Set<String>
    public var affectedEmitterIDs: Set<String>
    public var wholeSelected: Bool
    public var atmosphericLevel: Double

    public init(
        descriptor: FixtureVisualizationDescriptor,
        geometry: FixtureGlyphGeometry,
        liveEmitters: [FixtureElementPreviewState] = [],
        selectedEmitterIDs: Set<String> = [],
        affectedEmitterIDs: Set<String> = [],
        wholeSelected: Bool = false,
        atmosphericLevel: Double = 0
    ) {
        self.descriptor = descriptor; self.geometry = geometry; self.liveEmitters = liveEmitters
        self.selectedEmitterIDs = selectedEmitterIDs; self.affectedEmitterIDs = affectedEmitterIDs; self.wholeSelected = wholeSelected
        self.atmosphericLevel = atmosphericLevel
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            chassis
            formDetails
            if geometry.apertures.isEmpty { topologyHint }
            ForEach(geometry.apertures) { aperture in
                emitter(aperture)
            }
            if descriptor.movement == .panTilt || descriptor.form == .movingHead || descriptor.form == .scanner {
                orientationMarker
            }
        }
        .frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var topologyHint: some View {
        let topology = descriptor.componentGroups.first?.topology ?? .unknown
        switch topology {
        case .linear:
            HStack(spacing: 3) { ForEach(0..<6, id: \.self) { _ in Circle().fill(Color.white.opacity(0.4)).frame(width: 4, height: 4) } }
                .frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
        case .grid, .variableRows, .array:
            VStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 2) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.35)).frame(width: 4, height: 4) } }
                }
            }.frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
        case .ring, .rings:
            Circle().stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 3, dash: [2, 2])).frame(width: geometry.bodyBounds.height * 0.55, height: geometry.bodyBounds.height * 0.55).position(x: geometry.bodyBounds.midX, y: geometry.bodyBounds.midY)
        case .multiHead:
            HStack(spacing: 5) { ForEach(0..<max(2, min(12, descriptor.emitters.count)), id: \.self) { _ in VStack(spacing: 0) { Circle().stroke(Color.white.opacity(0.6)).frame(width: 7, height: 7); Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 5) } } }
                .frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
        default: EmptyView()
        }
    }

    @ViewBuilder private var chassis: some View {
        let stroke = wholeSelected ? AuroraColor.accentBright : Color.white.opacity(0.5)
        switch descriptor.form {
        case .par, .fresnel, .profile:
            Circle().fill(Color.black.opacity(0.76)).overlay(Circle().stroke(stroke, lineWidth: wholeSelected ? 2 : 1))
        case .movingHead:
            RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.78)).overlay(RoundedRectangle(cornerRadius: 7).stroke(stroke, lineWidth: wholeSelected ? 2 : 1))
        case .scanner:
            RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.78)).overlay(RoundedRectangle(cornerRadius: 3).stroke(stroke, lineWidth: wholeSelected ? 2 : 1))
        case .linearBar, .strip, .multiHeadBar:
            Capsule().fill(Color.black.opacity(0.78)).overlay(Capsule().stroke(stroke, lineWidth: wholeSelected ? 2 : 1))
        default:
            RoundedRectangle(cornerRadius: descriptor.form == .panel || descriptor.form == .blinder ? 3 : 6).fill(Color.black.opacity(0.76)).overlay(RoundedRectangle(cornerRadius: descriptor.form == .panel || descriptor.form == .blinder ? 3 : 6).stroke(stroke, lineWidth: wholeSelected ? 2 : 1))
        }
    }

    @ViewBuilder private var formDetails: some View {
        switch descriptor.form {
        case .movingHead:
            VStack(spacing: 1) {
                Circle().stroke(Color.white.opacity(0.65), lineWidth: 1).frame(width: geometry.bodyBounds.height * 0.46, height: geometry.bodyBounds.height * 0.46)
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.15)).frame(width: geometry.bodyBounds.width * 0.65, height: geometry.bodyBounds.height * 0.18)
            }.frame(width: geometry.bodyBounds.width, height: geometry.bodyBounds.height)
        case .scanner:
            Rectangle().fill(Color.white.opacity(0.2)).overlay(Rectangle().stroke(Color.white.opacity(0.7))).frame(width: geometry.bodyBounds.width * 0.42, height: geometry.bodyBounds.height * 0.24).rotationEffect(.degrees(-18)).position(x: geometry.bodyBounds.midX, y: geometry.bodyBounds.midY)
        case .multiHeadBar:
            ForEach(Array((geometry.headCenters.isEmpty ? geometry.apertures.map(\.center) : geometry.headCenters).enumerated()), id: \.offset) { _, center in
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: geometry.bodyBounds.maxY * 0.72))
                    path.addLine(to: center)
                }.stroke(Color.white.opacity(0.48), lineWidth: 1)
            }
        case .atmospheric:
            if atmosphericLevel > 0.001 {
                Image(systemName: "cloud.fill").resizable().scaledToFit().foregroundStyle(Color.white.opacity(StageAtmosphereVisualStyle.cloudOpacity(atmosphericLevel))).scaleEffect(StageAtmosphereVisualStyle.cloudScale(atmosphericLevel)).padding(4)
            }
        case .laser:
            Circle().fill(Color.red.opacity(0.75)).frame(width: 7, height: 7).position(x: geometry.bodyBounds.midX, y: geometry.bodyBounds.midY)
        case .strobe:
            Rectangle().fill(Color.white.opacity(0.38)).frame(height: max(3, geometry.bodyBounds.height * 0.16)).position(x: geometry.bodyBounds.midX, y: geometry.bodyBounds.midY)
        default: EmptyView()
        }
    }

    private func emitter(_ aperture: FixtureGlyphApertureGeometry) -> some View {
        let state = liveEmitters.first { $0.elementID == aperture.id }
        let color = state?.color.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .white
        let intensity = state?.intensity ?? 0
        let selected = selectedEmitterIDs.contains(aperture.id)
        let affected = affectedEmitterIDs.contains(aperture.id)
        let optics = descriptor.emitters.first { $0.id == aperture.id }?.opticalBehaviors ?? descriptor.opticalBehaviors
        let narrowOptic = !optics.isDisjoint(with: [.spot, .beam, .profile])
        let radius: CGFloat = aperture.shape == .circle ? 999 : (aperture.shape == .roundedRectangle ? 3 : 0)
        return RoundedRectangle(cornerRadius: radius)
            .fill(color.opacity(0.15 + intensity * 0.85))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(selected ? AuroraColor.accentBright : (affected ? Color.orange.opacity(0.9) : Color.white.opacity(0.72)), lineWidth: selected ? 2.5 : (affected ? 2 : 1)))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(narrowOptic ? 0.65 : 0), lineWidth: 1).padding(2))
            .frame(width: aperture.bounds.width, height: aperture.bounds.height)
            .position(aperture.center)
            .accessibilityHidden(true)
    }

    private var orientationMarker: some View {
        Path { path in
            let p = geometry.orientationReference
            path.move(to: CGPoint(x: p.x, y: p.y + 2))
            path.addLine(to: CGPoint(x: p.x - 3, y: p.y + 7))
            path.addLine(to: CGPoint(x: p.x + 3, y: p.y + 7))
            path.closeSubpath()
        }
        .fill(AuroraColor.accentBright.opacity(0.9))
    }
}
