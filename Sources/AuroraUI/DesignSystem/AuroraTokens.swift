import AuroraDesignSystem
import SwiftUI

public enum AuroraTokens {
    public static let colors = AuroraColor.self
    public static let typography = AuroraTypography.self
    public static let spacing = AuroraSpacing.self
    public static let metrics = AuroraMetrics.self
    public static let animation = AuroraAnimation.self

    public static func shellBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            AuroraColor.surfaceBase.ignoresSafeArea()
            content()
        }
        .foregroundStyle(AuroraColor.textPrimary)
        .preferredColorScheme(.dark)
    }
}

/// Shared panel edge treatment for modular workstation adjacency.
public struct AuroraPanelChrome: ViewModifier {
    public var radius: CGFloat = AuroraMetrics.radiusPanel

    public func body(content: Content) -> some View {
        content
            .background(AuroraColor.surfacePanel)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AuroraColor.separatorStrong, lineWidth: AuroraMetrics.hairline)
            )
    }
}

extension View {
    public func auroraPanelChrome(radius: CGFloat = AuroraMetrics.radiusPanel) -> some View {
        modifier(AuroraPanelChrome(radius: radius))
    }
}
