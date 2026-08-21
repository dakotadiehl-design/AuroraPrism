import AuroraDesignSystem
import AuroraUI
import SwiftUI

/// Launch splash — professional lighting-control power-on (process launch only).
/// Hosted exclusively on the main `ContentView` overlay — never on float windows.
struct AuroraSplashView: View {
    @ObservedObject var model: LaunchSplashController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SplashBackgroundView()
                .opacity(1.0 - 0.35 * model.exitProgress)

            // Centered brand composition (cinematic, not a heavy dialog card).
            VStack(spacing: 0) {
                Spacer(minLength: 40)

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
                .frame(height: 168)

                SplashWordmarkView(
                    phase: model.animationPhase,
                    reduceMotion: reduceMotion
                )
                .padding(.top, 22)

                Text(PrismBrandCopy.productLine)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(3.4)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .opacity(wordmarkSubtitleOpacity)
                    .padding(.top, 10)

                Spacer(minLength: 32)

                SplashDMXActivityView(
                    phase: model.animationPhase,
                    reduceMotion: reduceMotion
                )
                .padding(.bottom, 18)

                SplashStartupStatusView(
                    bootstrap: model.bootstrap,
                    phase: model.animationPhase,
                    onContinueAfterFailure: {
                        model.dismissAfterFailure()
                    }
                )
                .padding(.bottom, 48)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 40)
            .scaleEffect(1.0 + 0.012 * model.exitProgress)
            .opacity(1.0 - model.exitProgress)

            VStack {
                Spacer()
                HStack {
                    SplashVersionLabel()
                        .padding(22)
                    Spacer()
                }
            }
            .opacity(1.0 - model.exitProgress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.15 * (1 - model.exitProgress)))
        .allowsHitTesting(model.isVisible)
        .onAppear {
            model.beginIfNeeded()
        }
    }

    private var wordmarkSubtitleOpacity: Double {
        switch model.animationPhase {
        case .brandingReveal, .engineActivity, .ambient, .ready, .exiting:
            return 0.88
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

#Preview("Splash — Prism reveal") {
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
