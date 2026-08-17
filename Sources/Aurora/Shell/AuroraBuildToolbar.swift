import AuroraOutput
import AuroraUI
import SwiftUI

/// Mode-aware shell toolbar (UI-02 A3). Perform hides structural Build actions.
struct AuroraBuildToolbar: View {
    @EnvironmentObject private var appModel: AppModel

    private var isPerform: Bool { appModel.workspace.mode == .perform }

    var body: some View {
        HStack(spacing: AuroraSpacing.md) {
            PrismToolbarBrand(markSize: 16)

            if !isPerform {
                HStack(spacing: 2) {
                    toolbarIconButton("doc.badge.plus", "New Show") { appModel.newShow() }
                    toolbarIconButton("folder", "Open") { appModel.openShow() }
                    toolbarIconButton("square.and.arrow.down", "Save") { appModel.saveShow() }
                }
            } else {
                // Optional save only — no New/Open in Perform
                toolbarIconButton("square.and.arrow.down", "Save") { appModel.saveShow() }
            }

            Spacer(minLength: 8)

            Text(appModel.windowTitle)
                .font(AuroraTypography.workspaceTitle)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: AuroraSpacing.sm) {
                healthCluster
                modeToggle
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

    private var modeToggle: some View {
        AuroraModeToggle(
            mode: Binding(
                get: {
                    appModel.workspace.mode == .perform ? .perform : .build
                },
                set: { chrome in
                    appModel.workspace.setMode(chrome == .perform ? .perform : .build)
                    appModel.notifyUI()
                }
            )
        )
    }

    private var healthCluster: some View {
        let health = AuroraShellHealthSnapshot.build(
            engineRunning: appModel.performance.engineRunning,
            output: appModel.output.presentationSnapshot(),
            midi: appModel.midiHealth
        )
        return HStack(spacing: AuroraSpacing.sm) {
            AuroraStatusIndicator(label: "Engine", level: health.engine)
            AuroraStatusIndicator(label: "Output", level: health.output)
            AuroraStatusIndicator(label: "MIDI", level: health.midi)
            if appModel.performance.validationIssueCount > 0 {
                AuroraStatusIndicator(label: "Issues", level: .warning)
            }
        }
    }

    private func toolbarIconButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: AuroraMetrics.iconPointSize, weight: .medium))
                .foregroundStyle(AuroraColor.textSecondary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
