import AuroraUI
import SwiftUI

// MARK: - Background

struct SplashBackgroundView: View {
    var body: some View {
        ZStack {
            AuroraColor.surfaceBase

            // Soft radial glow behind logo area
            RadialGradient(
                colors: [
                    AuroraColor.accent.opacity(0.14),
                    AuroraColor.accent.opacity(0.04),
                    Color.clear,
                ],
                center: .center,
                startRadius: 20,
                endRadius: 280
            )
            .blendMode(.plusLighter)

            // Corner vignette
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.55),
                ],
                center: .center,
                startRadius: 200,
                endRadius: 520
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Aurora ribbon

/// Soft violet/indigo/blue ribbon — cheap transforms, no heavy geometry rebuild.
struct AuroraRibbonView: View {
    var phase: SplashAnimationPhase
    var reduceMotion: Bool
    var readyPulse: Bool

    private var revealed: Bool {
        switch phase {
        case .initial, .logoIgnition: return false
        default: return true
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0, paused: reduceMotion || !revealed)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let drift = reduceMotion ? 0 : sin(t * 0.35) * 18
            let drift2 = reduceMotion ? 0 : cos(t * 0.28) * 12
            ZStack {
                ribbonLayer(
                    colors: [
                        Color.clear,
                        AuroraColor.accent.opacity(0.0),
                        Color(red: 0.45, green: 0.25, blue: 0.95).opacity(0.40),
                        Color(red: 0.25, green: 0.35, blue: 0.95).opacity(0.28),
                        Color(red: 0.2, green: 0.75, blue: 0.95).opacity(0.12),
                        Color.clear,
                    ],
                    blur: 36,
                    yOffset: drift,
                    xOffset: drift2 * 0.5
                )
                ribbonLayer(
                    colors: [
                        Color.clear,
                        Color(red: 0.55, green: 0.3, blue: 1.0).opacity(0.22),
                        Color(red: 0.35, green: 0.2, blue: 0.85).opacity(0.18),
                        Color.clear,
                    ],
                    blur: 56,
                    yOffset: -drift * 0.6,
                    xOffset: -drift2
                )
                .opacity(0.55)
            }
            .opacity(revealed ? (readyPulse ? 0.95 : 0.75) : 0)
            .scaleEffect(y: revealed ? 1 : 0.4, anchor: .center)
            .animation(.easeOut(duration: 0.7), value: revealed)
            .animation(.easeInOut(duration: 0.2), value: readyPulse)
        }
        .allowsHitTesting(false)
        .frame(maxWidth: 520, maxHeight: 180)
    }

    private func ribbonLayer(
        colors: [Color],
        blur: CGFloat,
        yOffset: CGFloat,
        xOffset: CGFloat
    ) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 420, height: 70)
            .rotationEffect(.degrees(-8))
            .offset(x: xOffset, y: yOffset)
            .blur(radius: blur)
            .blendMode(.plusLighter)
    }
}

// MARK: - Logo ignition

struct SplashLogoView: View {
    var phase: SplashAnimationPhase
    var readyPulse: Bool
    var reduceMotion: Bool

    private var ignited: Bool {
        phase != .initial
    }

    var body: some View {
        let scale: CGFloat = {
            if reduceMotion { return ignited ? 1 : 0.92 }
            if !ignited { return 0.1 }
            if readyPulse { return 1.04 }
            return 1.0
        }()
        let opacity: Double = ignited ? 1 : 0
        let blur: CGFloat = {
            if reduceMotion { return 0 }
            if !ignited { return 8 }
            if readyPulse { return 0.5 }
            return 0
        }()

        ZStack {
            // Glow halo
            Circle()
                .fill(AuroraColor.accent.opacity(readyPulse ? 0.45 : 0.22))
                .frame(width: 110, height: 110)
                .blur(radius: readyPulse ? 28 : 18)
                .opacity(ignited ? 1 : 0)
                .scaleEffect(readyPulse ? 1.15 : 1.0)

            Image("AuroraMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .shadow(color: AuroraColor.accent.opacity(0.55), radius: readyPulse ? 22 : 12)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .blur(radius: blur)
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.5), value: ignited)
        .animation(.easeInOut(duration: 0.18), value: readyPulse)
        .accessibilityLabel("Aurora")
    }
}

// MARK: - Wordmark

struct SplashWordmarkView: View {
    var phase: SplashAnimationPhase
    var reduceMotion: Bool

    private var shown: Bool {
        switch phase {
        case .brandingReveal, .engineActivity, .ambient, .ready, .exiting:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Image("AuroraWordmark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: 28)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : (reduceMotion ? 0 : 6))
            .blur(radius: (shown || reduceMotion) ? 0 : 2)
            .animation(.easeOut(duration: 0.4), value: shown)
            .accessibilityLabel("Aurora")
    }
}

// MARK: - DMX activity

struct SplashDMXActivityView: View {
    var phase: SplashAnimationPhase
    var reduceMotion: Bool

    /// Deterministic bar heights (quiet console energy).
    private static let targetLevels: [CGFloat] = [
        6, 10, 16, 22, 14, 8, 18, 12,
        24, 16, 10, 20, 14, 8, 18, 10,
    ]

    private var active: Bool {
        switch phase {
        case .engineActivity, .ambient, .ready, .exiting:
            return true
        default:
            return false
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 2.0 : 1.0 / 20.0, paused: reduceMotion || !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<Self.targetLevels.count, id: \.self) { index in
                    let base = Self.targetLevels[index]
                    let wave: CGFloat = {
                        guard active, !reduceMotion else { return active ? base : 3 }
                        let w = sin(t * 1.4 + Double(index) * 0.55)
                        return max(3, base * (0.55 + 0.45 * CGFloat((w + 1) * 0.5)))
                    }()
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AuroraColor.accent.opacity(0.85),
                                    AuroraColor.accent.opacity(0.25),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: wave)
                        .opacity(active ? 0.9 : 0)
                        .animation(
                            .easeOut(duration: 0.35).delay(Double(index) * 0.025),
                            value: active
                        )
                }
            }
            .frame(height: 28)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Status

struct SplashStartupStatusView: View {
    var bootstrap: LaunchBootstrapPhase
    var phase: SplashAnimationPhase

    var body: some View {
        VStack(spacing: 6) {
            Text(bootstrap.statusText)
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(1.6)
                .foregroundStyle(AuroraColor.textSecondary)
                .multilineTextAlignment(.center)

            if let detail = bootstrap.failureDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraColor.critical)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if phase != .ready && phase != .exiting {
                // Indeterminate sweep (not a percentage).
                IndeterminateSweepBar()
                    .frame(width: 120, height: 2)
                    .padding(.top, 4)
            }
        }
        .opacity(phase == .initial ? 0.35 : 1)
        .animation(.easeIn(duration: 0.3), value: bootstrap.statusText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(bootstrap.statusText)
    }
}

private struct IndeterminateSweepBar: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let x = CGFloat((sin(t * 2.2) + 1) * 0.5)
            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(AuroraColor.accent.opacity(0.7))
                    .frame(width: geo.size.width * 0.28)
                    .offset(x: (geo.size.width - geo.size.width * 0.28) * x)
            }
        }
        .clipShape(Capsule())
    }
}

// MARK: - Version

struct SplashVersionLabel: View {
    var body: some View {
        Text(versionString)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(AuroraColor.textTertiary.opacity(0.7))
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(v)"
    }
}
