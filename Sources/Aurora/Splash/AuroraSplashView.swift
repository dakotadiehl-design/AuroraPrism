import AuroraUI
import SwiftUI

/// Launch splash — professional lighting-control power-on (process launch only).
struct AuroraSplashView: View {
    @ObservedObject var model: LaunchSplashController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SplashBackgroundView()

            // Centered brand card
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AuroraColor.surfaceBase.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        AuroraColor.accent.opacity(0.35),
                                        Color.white.opacity(0.06),
                                        AuroraColor.accent.opacity(0.15),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 28, y: 12)

                VStack(spacing: 0) {
                    Spacer(minLength: 36)

                    ZStack {
                        AuroraRibbonView(
                            phase: model.animationPhase,
                            reduceMotion: reduceMotion,
                            readyPulse: model.readyPulse
                        )
                        SplashLogoView(
                            phase: model.animationPhase,
                            readyPulse: model.readyPulse,
                            reduceMotion: reduceMotion
                        )
                    }
                    .frame(height: 140)

                    SplashWordmarkView(
                        phase: model.animationPhase,
                        reduceMotion: reduceMotion
                    )
                    .padding(.top, 18)

                    Text("LIGHTING CONTROL")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(3.2)
                        .foregroundStyle(AuroraColor.textTertiary)
                        .opacity(wordmarkSubtitleOpacity)
                        .padding(.top, 8)

                    Spacer(minLength: 28)

                    SplashDMXActivityView(
                        phase: model.animationPhase,
                        reduceMotion: reduceMotion
                    )
                    .padding(.bottom, 16)

                    SplashStartupStatusView(
                        bootstrap: model.bootstrap,
                        phase: model.animationPhase
                    )
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 36)
            }
            .frame(width: 720, height: 460)
            .scaleEffect(1.0 + 0.015 * model.exitProgress)
            .opacity(1.0 - 0.95 * model.exitProgress)

            VStack {
                Spacer()
                HStack {
                    SplashVersionLabel()
                        .padding(20)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55 + 0.35 * (1 - model.exitProgress)))
        .allowsHitTesting(model.isVisible)
        .onAppear {
            model.beginIfNeeded()
        }
    }

    private var wordmarkSubtitleOpacity: Double {
        switch model.animationPhase {
        case .brandingReveal, .engineActivity, .ambient, .ready, .exiting:
            return 0.85
        default:
            return 0
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Splash — Initial") {
    AuroraSplashView(model: .preview(phase: .initial, bootstrap: .launching))
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Splash — Ignition") {
    AuroraSplashView(model: .preview(phase: .logoIgnition, bootstrap: .loadingFixtureLibrary))
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Splash — Aurora reveal") {
    AuroraSplashView(model: .preview(phase: .auroraReveal, bootstrap: .startingEngine))
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Splash — Loading") {
    AuroraSplashView(model: .preview(phase: .engineActivity, bootstrap: .startingMIDI))
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Splash — Ambient") {
    AuroraSplashView(model: .preview(phase: .ambient, bootstrap: .preparingWorkspace))
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Splash — Ready") {
    AuroraSplashView(model: .preview(phase: .ready, bootstrap: .ready))
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("Splash — Error") {
    AuroraSplashView(
        model: .preview(
            phase: .ambient,
            bootstrap: .failed("Fixture library could not be loaded.")
        )
    )
    .frame(width: 900, height: 600)
    .preferredColorScheme(.dark)
}
#endif
