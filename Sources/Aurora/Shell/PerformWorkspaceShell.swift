import AuroraUI
import SwiftUI

/// Perform mode shell — structural seed for UI-07 (UI-02F). Truthful Current/Next.
struct PerformWorkspaceShell: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            performHeader
            Spacer(minLength: 12)
            currentNextRow
            Spacer(minLength: 20)
            transportRow
            Spacer(minLength: 16)
            healthRow
            Spacer(minLength: 8)
        }
        .padding(AuroraSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraColor.surfaceBase)
        .auroraDensity(.performance)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Perform mode")
    }

    private var performHeader: some View {
        HStack {
            Text("PERFORM")
                .font(AuroraTypography.status)
                .foregroundStyle(AuroraColor.accentBright)
                .tracking(1.5)
            Text(appModel.performance.showName)
                .font(AuroraTypography.workspaceTitle)
                .foregroundStyle(AuroraColor.textPrimary)
                .lineLimit(1)
            Spacer()
            if !appModel.performance.song.songTitle.isEmpty {
                Text(appModel.performance.song.songTitle)
                    .font(AuroraTypography.sectionHeading)
                    .foregroundStyle(AuroraColor.textSecondary)
            }
        }
    }

    private var currentNextRow: some View {
        let current = appModel.performance.currentCue
        let next = appModel.performance.nextCue
        return HStack(alignment: .top, spacing: AuroraSpacing.xxxl) {
            VStack(alignment: .leading, spacing: AuroraSpacing.sm) {
                Text("CURRENT")
                    .font(AuroraTypography.status)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(1)
                if let section = current.sectionLabel, !section.isEmpty {
                    Text(section)
                        .font(AuroraTypography.performanceSecondary)
                        .foregroundStyle(AuroraColor.textSecondary)
                }
                if !current.numberDisplay.isEmpty {
                    Text(current.numberDisplay)
                        .font(AuroraTypography.performCueNumber)
                        .foregroundStyle(AuroraColor.accentBright)
                        .monospacedDigit()
                }
                Text(current.name.isEmpty ? "—" : current.name)
                    .font(AuroraTypography.performancePrimary)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: AuroraSpacing.sm) {
                Text("NEXT")
                    .font(AuroraTypography.status)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(1)
                if let section = next.sectionLabel, !section.isEmpty {
                    Text(section)
                        .font(AuroraTypography.performanceSecondary)
                        .foregroundStyle(AuroraColor.textSecondary)
                }
                if !next.numberDisplay.isEmpty {
                    Text(next.numberDisplay)
                        .font(AuroraTypography.cueNumber)
                        .foregroundStyle(AuroraColor.textSecondary)
                        .font(.system(size: 28, weight: .semibold, design: .default))
                }
                Text(nextDisplayName(next))
                    .font(AuroraTypography.performancePrimary)
                    .foregroundStyle(AuroraColor.textPrimary.opacity(0.85))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nextDisplayName(_ next: PerformanceCueSummary) -> String {
        if !next.name.isEmpty { return next.name }
        if let section = next.sectionLabel, !section.isEmpty { return section }
        return "—"
    }

    private var transportRow: some View {
        HStack(spacing: AuroraSpacing.lg) {
            AuroraTransportButton(kind: .back) { appModel.back() }
            AuroraTransportButton(kind: .go) { appModel.go() }
            AuroraTransportButton(kind: .stop) { appModel.stopPlayback() }
        }
    }

    private var healthRow: some View {
        let health = AuroraShellHealthSnapshot.build(
            engineRunning: appModel.performance.engineRunning,
            output: appModel.output.presentationSnapshot(),
            midiStatus: appModel.midiStatus
        )
        return HStack(spacing: AuroraSpacing.xl) {
            AuroraStatusIndicator(label: "Engine", level: health.engine)
            AuroraStatusIndicator(label: "Output", level: health.output)
            AuroraStatusIndicator(label: "MIDI", level: health.midi)
            Spacer()
        }
    }
}
