import AuroraUI
import SwiftUI

/// Restrained empty / no-show surface (UI-02G).
struct WelcomeEmptyView: View {
    var onNew: () -> Void
    var onOpen: () -> Void
    var onDemo: () -> Void

    var body: some View {
        VStack(spacing: AuroraSpacing.xl) {
            Spacer(minLength: 40)
            AuroraWordmarkView(height: 28)
            Text("Professional lighting control")
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textTertiary)
            HStack(spacing: AuroraSpacing.md) {
                AuroraButton("New Show", kind: .secondary, action: onNew)
                AuroraButton("Open…", kind: .secondary, action: onOpen)
                AuroraButton("Open Demo Show", kind: .primary, action: onDemo)
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraColor.surfaceBase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome")
    }
}
