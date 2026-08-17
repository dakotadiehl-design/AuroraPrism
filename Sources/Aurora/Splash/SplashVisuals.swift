import AuroraUI
import SwiftUI

// MARK: - Background (C6B — full-bleed charcoal + restrained aurora)

struct SplashBackgroundView: View {
    var body: some View {
        ZStack {
            // Deep charcoal base (matches surface hierarchy, slightly richer for launch).
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.035, blue: 0.045),
                    Color(red: 0.05, green: 0.045, blue: 0.07),
                    Color(red: 0.03, green: 0.03, blue: 0.04),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft radial glow behind logo area
            RadialGradient(
                colors: [
                    AuroraColor.accent.opacity(0.16),
                    Color(red: 0.25, green: 0.35, blue: 0.95).opacity(0.06),
                    Color.clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 16,
                endRadius: 340
            )
            .blendMode(.plusLighter)

            // Subtle secondary cool wash
            RadialGradient(
                colors: [
                    Color(red: 0.2, green: 0.75, blue: 0.95).opacity(0.05),
                    Color.clear,
                ],
                center: UnitPoint(x: 0.55, y: 0.48),
                startRadius: 10,
                endRadius: 260
            )
            .blendMode(.plusLighter)

            // Corner vignette
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.62),
                ],
                center: .center,
                startRadius: 220,
                endRadius: 640
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
            let drift = reduceMotion ? 0 : sin(t * 0.35) * 16
            let drift2 = reduceMotion ? 0 : cos(t * 0.28) * 11
            ZStack {
                ribbonLayer(
                    colors: [
                        Color.clear,
                        AuroraColor.accent.opacity(0.0),
                        Color(red: 0.45, green: 0.25, blue: 0.95).opacity(0.42),
                        Color(red: 0.25, green: 0.35, blue: 0.95).opacity(0.30),
                        Color(red: 0.2, green: 0.75, blue: 0.95).opacity(0.14),
                        Color.clear,
                    ],
                    blur: 38,
                    yOffset: drift,
                    xOffset: drift2 * 0.5
                )
                ribbonLayer(
                    colors: [
                        Color.clear,
                        Color(red: 0.55, green: 0.3, blue: 1.0).opacity(0.24),
                        Color(red: 0.35, green: 0.2, blue: 0.85).opacity(0.18),
                        Color.clear,
                    ],
                    blur: 58,
                    yOffset: -drift * 0.6,
                    xOffset: -drift2
                )
                .opacity(0.55)
            }
            .opacity(revealed ? (readyPulse ? 0.98 : 0.78) : 0)
            .scaleEffect(y: revealed ? 1 : 0.35, anchor: .center)
            .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.75), value: revealed)
            .animation(.easeInOut(duration: 0.18), value: readyPulse)
        }
        .allowsHitTesting(false)
        .frame(maxWidth: 560, maxHeight: 200)
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
            .frame(width: 440, height: 72)
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
            if reduceMotion { return ignited ? 1 : 0.94 }
            if !ignited { return 0.12 }
            if readyPulse { return 1.05 }
            return 1.0
        }()
        let opacity: Double = ignited ? 1 : 0
        let blur: CGFloat = {
            if reduceMotion { return 0 }
            if !ignited { return 10 }
            if readyPulse { return 0.4 }
            return 0
        }()

        ZStack {
            // Glow halo
            Circle()
                .fill(AuroraColor.accent.opacity(readyPulse ? 0.48 : 0.24))
                .frame(width: 128, height: 128)
                .blur(radius: readyPulse ? 32 : 20)
                .opacity(ignited ? 1 : 0)
                .scaleEffect(readyPulse ? 1.18 : 1.0)

            // Secondary cool rim
            Circle()
                .fill(Color(red: 0.25, green: 0.65, blue: 1.0).opacity(readyPulse ? 0.18 : 0.08))
                .frame(width: 100, height: 100)
                .blur(radius: 16)
                .opacity(ignited ? 1 : 0)

            Image("PrismMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 104, height: 104)
                .shadow(color: AuroraColor.accent.opacity(0.6), radius: readyPulse ? 26 : 14)
                .shadow(color: Color(red: 0.3, green: 0.7, blue: 1.0).opacity(0.25), radius: 8)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .blur(radius: blur)
        .animation(reduceMotion ? .easeOut(duration: 0.22) : .easeOut(duration: 0.55), value: ignited)
        .animation(.easeInOut(duration: 0.16), value: readyPulse)
        .accessibilityLabel("Prism")
    }
}

// MARK: - Wordmark (typographic — no double star)

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
        VStack(spacing: 5) {
            Text(PrismBrandCopy.familyName)
                .font(.system(size: 9, weight: .medium))
                .tracking(4.0)
                .foregroundStyle(AuroraColor.textTertiary)
            PrismTypographicWordmark(size: 34, tracking: 6.5, luminous: true)
        }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : (reduceMotion ? 0 : 8))
            .blur(radius: (shown || reduceMotion) ? 0 : 2.5)
            .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.45), value: shown)
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
                                    AuroraColor.accent.opacity(0.9),
                                    AuroraColor.accent.opacity(0.22),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: wave)
                        .opacity(active ? 0.92 : 0)
                        .animation(
                            .easeOut(duration: 0.32).delay(Double(index) * 0.022),
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
    var onContinueAfterFailure: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text(bootstrap.statusText)
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(1.8)
                .foregroundStyle(AuroraColor.textSecondary)
                .multilineTextAlignment(.center)

            if let detail = bootstrap.failureDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraColor.critical)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let onContinueAfterFailure {
                    Button("Continue", action: onContinueAfterFailure)
                        .buttonStyle(AuroraButtonStyle(kind: .primary))
                        .controlSize(.small)
                        .tint(AuroraColor.accent)
                        .padding(.top, 4)
                }
            } else if phase != .ready && phase != .exiting {
                IndeterminateSweepBar()
                    .frame(width: 128, height: 2)
                    .padding(.top, 2)
            }
        }
        .opacity(phase == .initial ? 0.4 : 1)
        .animation(.easeIn(duration: 0.28), value: bootstrap.statusText)
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
                    .fill(AuroraColor.accent.opacity(0.75))
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
            .foregroundStyle(AuroraColor.textTertiary.opacity(0.75))
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let b, b != v {
            return "v\(v) (\(b))"
        }
        return "v\(v)"
    }
}
