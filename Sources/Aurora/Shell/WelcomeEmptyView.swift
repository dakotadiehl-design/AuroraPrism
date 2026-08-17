import AuroraUI
import SwiftUI

/// Restrained empty / no-show surface (UI-02G / C6D brand fidelity).
struct WelcomeEmptyView: View {
    var onNew: () -> Void
    var onOpen: () -> Void
    var onDemo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            // Brand stack: mark + full wordmark image (welcome is a brand surface).
            VStack(spacing: 18) {
                PrismMarkView(size: 56, showsGlow: true)
                PrismWordmarkView(height: 32)
                Text(PrismBrandCopy.productLine)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(3.2)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text(PrismBrandCopy.welcomeDetail)
                    .font(AuroraTypography.secondary)
                    .foregroundStyle(AuroraColor.textSecondary)
                    .padding(.top, 2)
            }

            HStack(spacing: AuroraSpacing.md) {
                AuroraButton("New Show", kind: .secondary, action: onNew)
                AuroraButton("Open…", kind: .secondary, action: onOpen)
                AuroraButton("Open Demo Show", kind: .primary, action: onDemo)
            }
            .padding(.top, 36)

            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                AuroraColor.surfaceBase
                RadialGradient(
                    colors: [
                        AuroraColor.accent.opacity(0.06),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 20,
                    endRadius: 320
                )
                .blendMode(.plusLighter)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome")
    }
}
