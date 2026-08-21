import AuroraDesignSystem
import AuroraUI
import SwiftUI

/// About Prism — high-visibility product brand surface.
struct AuroraAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            PrismMarkView(size: 72, showsGlow: true)
                .padding(.bottom, 16)

            PrismWordmarkView(height: 30)
                .padding(.bottom, 8)

            Text(PrismBrandCopy.productLine)
                .font(.system(size: 10, weight: .medium))
                .tracking(3.0)
                .foregroundStyle(AuroraColor.textTertiary)
                .padding(.bottom, 16)

            Text(PrismBrandCopy.aboutDetail)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(spacing: 4) {
                Text(versionLine)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AuroraColor.textSecondary)
                Text(copyrightLine)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            .padding(.top, 22)

            Spacer(minLength: 16)

            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AuroraButtonStyle(kind: .primary))
                .tint(AuroraColor.accent)
                .controlSize(.regular)
                .padding(.bottom, 22)
        }
        .frame(width: 360, height: 420)
        .background(AuroraColor.surfaceBase)
        .preferredColorScheme(.dark)
    }

    private var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(v) (\(b))"
    }

    private var copyrightLine: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) Aurora Prism"
    }
}

/// Menu command that opens the About window (C6D).
/// Posts to main ContentView which owns `openWindow` environment.
struct AboutAuroraMenuButton: View {
    var body: some View {
        Button("About Prism") {
            NotificationCenter.default.post(name: .auroraOpenAbout, object: nil)
        }
    }
}

#if DEBUG
#Preview("About Prism") {
    AuroraAboutView()
}
#endif
