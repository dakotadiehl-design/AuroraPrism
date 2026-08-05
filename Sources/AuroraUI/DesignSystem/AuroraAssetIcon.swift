import SwiftUI

/// Stable asset names for Aurora lighting icons (app catalog / Bundle.main).
public enum AuroraLightingIcon: String, Sendable, CaseIterable {
    case intensity = "IntensityIcon"
    case dimmer = "DimmerIcon"
    case position = "PositionIcon"
    case panTilt = "PanTiltIcon"
    case colorWheel = "ColorWheelIcon"
    case beam = "BeamIcon"
    case gobo = "GoboIcon"
    case prism = "PrismIcon"
    case iris = "IrisIcon"
    case strobe = "StrobeIcon"
    case smoke = "SmokeIcon"
    case laser = "LaserIcon"
    case grandMaster = "GrandMasterIcon"
    case pixelMap = "PixelMapIcon"
}

/// Lightweight asset icon: Bundle.main lookup, template rendering, fixed size.
/// Callers apply semantic foregroundStyle / opacity for state.
public struct AuroraAssetIcon: View {
    public var name: String
    public var size: CGFloat

    public init(name: String, size: CGFloat = AuroraMetrics.iconPointSize) {
        self.name = name
        self.size = size
    }

    public init(_ icon: AuroraLightingIcon, size: CGFloat = AuroraMetrics.iconPointSize) {
        self.name = icon.rawValue
        self.size = size
    }

    public var body: some View {
        Image(name, bundle: .main)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
