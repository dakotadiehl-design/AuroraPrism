import AuroraUI
import SwiftUI

// MARK: - Shared brand building blocks (C6D)

/// App-catalog brand mark for toolbar / splash / About.
struct AuroraMarkView: View {
    var size: CGFloat = 18
    var showsGlow: Bool = false

    var body: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(AuroraColor.accent.opacity(0.28))
                    .frame(width: size * 1.35, height: size * 1.35)
                    .blur(radius: size * 0.22)
            }
            Image("AuroraMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
        .accessibilityLabel("Aurora")
    }
}

/// Full wordmark image (mark + AURORA) for welcome / About — not stacked under a large mark.
struct AuroraWordmarkView: View {
    var height: CGFloat = 22

    var body: some View {
        Image("AuroraWordmark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityLabel("Aurora")
    }
}

/// Typographic wordmark used with a separate mark (toolbar + splash).
/// Avoids double-star when the wordmark imageset already includes the mark.
struct AuroraTypographicWordmark: View {
    var size: CGFloat = 13
    var tracking: CGFloat = 1.2
    var luminous: Bool = false

    var body: some View {
        Text("AURORA")
            .font(.system(size: size, weight: .bold, design: .default))
            .tracking(tracking)
            .foregroundStyle(luminous ? luminousStyle : AnyShapeStyle(AuroraColor.textPrimary))
            .accessibilityLabel("Aurora")
    }

    private var luminousStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.93, blue: 0.98),
                    Color(red: 0.72, green: 0.68, blue: 0.98),
                    Color(red: 0.55, green: 0.72, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

/// Compact permanent chrome: [Mark] AURORA (UI-02A / C6D).
struct AuroraToolbarBrand: View {
    var markSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            AuroraMarkView(size: markSize)
            AuroraTypographicWordmark(size: 13, tracking: 1.2, luminous: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aurora")
    }
}

/// Product tagline used on splash / welcome / About.
enum AuroraBrandCopy {
    static let productLine = "LIGHTING CONTROL"
    static let welcomeDetail = "Professional lighting control"
    static let aboutDetail = "Professional lighting control for macOS"
}

// MARK: - Prism product identity

struct PrismMarkView: View {
    var size: CGFloat = 18
    var showsGlow: Bool = false

    var body: some View {
        ZStack {
            if showsGlow {
                Circle()
                    .fill(AuroraColor.accent.opacity(0.28))
                    .frame(width: size * 1.35, height: size * 1.35)
                    .blur(radius: size * 0.22)
            }
            Image("PrismMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
        .accessibilityLabel("Prism")
    }
}

struct PrismWordmarkView: View {
    var height: CGFloat = 22

    var body: some View {
        Image("PrismWordmark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityLabel("Prism")
    }
}

struct PrismTypographicWordmark: View {
    var size: CGFloat = 13
    var tracking: CGFloat = 1.2
    var luminous: Bool = false

    var body: some View {
        Text("PRISM")
            .font(.system(size: size, weight: .bold))
            .tracking(tracking)
            .foregroundStyle(luminous ? luminousStyle : AnyShapeStyle(AuroraColor.textPrimary))
            .accessibilityLabel("Prism")
    }

    private var luminousStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.96, blue: 1.0),
                    Color(red: 0.72, green: 0.68, blue: 0.98),
                    Color(red: 0.40, green: 0.78, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct PrismToolbarBrand: View {
    var markSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 6) {
            PrismMarkView(size: markSize)
            PrismTypographicWordmark(size: 13, tracking: 1.2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prism")
    }
}

enum PrismBrandCopy {
    static let familyName = "AURORA"
    static let productLine = "LIGHTING CONTROL"
    static let welcomeDetail = "Professional lighting control"
    static let aboutDetail = "Professional lighting control for macOS"
}
