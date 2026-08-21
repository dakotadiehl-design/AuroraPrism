import AuroraDesignSystem
import SwiftUI

/// Application toolbar matching render pack: wordmark, actions, title, health, mode.
public struct AuroraAppToolbar: View {
    public var projectTitle: String
    public var healthSummary: String
    @Binding public var mode: AuroraWorkspaceChromeMode
    public var showModeToggle: Bool

    public init(
        projectTitle: String = "Untitled.prism",
        healthSummary: String = "Output OK",
        mode: Binding<AuroraWorkspaceChromeMode> = .constant(.build),
        showModeToggle: Bool = true
    ) {
        self.projectTitle = projectTitle
        self.healthSummary = healthSummary
        self._mode = mode
        self.showModeToggle = showModeToggle
    }

    public var body: some View {
        HStack(spacing: AuroraSpacing.md) {
            // Wordmark
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AuroraColor.accentBright)
                    .rotationEffect(.degrees(45))
                Text("PRISM")
                    .font(AuroraTypography.wordmark)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .tracking(1)
            }

            // Document actions
            HStack(spacing: 2) {
                toolbarIcon("doc.badge.plus", "New")
                toolbarIcon("folder", "Open")
                toolbarIcon("square.and.arrow.down", "Save")
                Rectangle().fill(AuroraColor.separatorStrong).frame(width: 1, height: 14).padding(.horizontal, 4)
                toolbarIcon("arrow.uturn.backward", "Undo")
                toolbarIcon("arrow.uturn.forward", "Redo")
            }

            Spacer(minLength: 8)

            Text(projectTitle)
                .font(AuroraTypography.workspaceTitle)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: AuroraSpacing.sm) {
                Text("120.0 BPM")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(AuroraColor.success)
                        .frame(width: 6, height: 6)
                    Text(healthSummary)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textSecondary)
                }
                if showModeToggle {
                    AuroraModeToggle(mode: $mode)
                }
            }
        }
        .padding(.horizontal, AuroraSpacing.lg)
        .frame(height: AuroraMetrics.toolbarHeight)
        .background(AuroraColor.surfaceWorkspace)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AuroraColor.separator)
                .frame(height: AuroraMetrics.hairline)
        }
    }

    private func toolbarIcon(_ name: String, _ label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: AuroraMetrics.iconPointSize, weight: .medium))
            .foregroundStyle(AuroraColor.textSecondary)
            .frame(width: 22, height: 22)
            .help(label)
            .accessibilityLabel(label)
    }
}
