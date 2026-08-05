import AuroraUI
import SwiftUI

/// Perform mode cockpit — thin presentation over PerformanceSnapshot (UI-07).
///
/// **A5:** GO is the dominant live action; song entry nav is secondary.
/// **A6:** Transport stays enabled for nonfatal health/output/MIDI degradation.
struct PerformWorkspaceShell: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            performHeader
            Spacer(minLength: 12)
            currentNextRow
            if let phaseLine = phaseStatusLine {
                Text(phaseLine)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .padding(.top, AuroraSpacing.sm)
            }
            Spacer(minLength: 20)
            transportRow
            songEntryNav
            Spacer(minLength: 16)
            if appModel.performance.validationIssueCount > 0 {
                Text("\(appModel.performance.validationIssueCount) validation issue(s)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.warning)
                    .padding(.bottom, AuroraSpacing.sm)
            }
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
                VStack(alignment: .trailing, spacing: 2) {
                    Text(appModel.performance.song.songTitle)
                        .font(AuroraTypography.sectionHeading)
                        .foregroundStyle(AuroraColor.textSecondary)
                    if !appModel.performance.song.currentEntryLabel.isEmpty {
                        Text(appModel.performance.song.currentEntryLabel)
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                }
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

    private var phaseStatusLine: String? {
        let phase = appModel.performance.playbackPhase
        guard phase != "idle", !phase.isEmpty else { return nil }
        return "Phase: \(phase)"
    }

    /// GO dominant; BACK/STOP supporting. Never gated by health color (A6). CR-15: no no-op modifiers.
    private var transportRow: some View {
        HStack(spacing: AuroraSpacing.lg) {
            AuroraTransportButton(kind: .back) { appModel.back() }
            AuroraTransportButton(kind: .go) { appModel.go() }
            AuroraTransportButton(kind: .stop) { appModel.stopPlayback() }
        }
    }

    /// Secondary song/section navigation — not GO-styled (A5 / CR-14).
    @ViewBuilder
    private var songEntryNav: some View {
        if appModel.performance.song.songID != nil {
            HStack(spacing: AuroraSpacing.md) {
                Button {
                    appModel.showControl.songPrevious(project: appModel.session.project)
                    appModel.notifyUI()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text(songEntryCaption)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textSecondary)
                    .frame(minWidth: 100)

                Button {
                    appModel.showControl.songNext(project: appModel.session.project)
                    appModel.notifyUI()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, AuroraSpacing.lg)
            .accessibilityLabel("Song entry navigation")
        }
    }

    private var songEntryCaption: String {
        let song = appModel.performance.song
        if song.entryIndex >= 0, song.entryCount > 0 {
            let label = song.currentEntryLabel.isEmpty ? "Entry" : song.currentEntryLabel
            return "\(label)  \(song.entryIndex + 1)/\(song.entryCount)"
        }
        return "—"
    }

    /// Health is informational only — never the sole gate for GO (A6).
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
            if appModel.performance.activeChannelCount > 0 {
                Text("\(appModel.performance.activeChannelCount) ch")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            Spacer()
        }
    }
}
