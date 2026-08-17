import SwiftUI

/// Semantic hierarchy for the family-wide Aurora button treatment.
public enum AuroraButtonStyleKind: Sendable {
    case primary
    case secondary
    case destructive
    case quiet
}

/// Option 1 — the molded, luminous button face derived from Aurora's value-thumb fader.
///
/// Apply this style directly when a button needs a custom label. Use ``AuroraButton``
/// for the common text-only form. When `kind` is `nil`, destructive button roles are
/// detected automatically and every other button receives the secondary treatment.
public struct AuroraButtonStyle: ButtonStyle {
    public var kind: AuroraButtonStyleKind?
    public var isSelected: Bool

    public init(kind: AuroraButtonStyleKind? = nil, isSelected: Bool = false) {
        self.kind = kind
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        AuroraButtonStyleBody(
            configuration: configuration,
            kind: kind ?? (configuration.role == .destructive ? .destructive : .secondary),
            isSelected: isSelected
        )
    }
}

/// Standard text button for the Aurora family.
public struct AuroraButton: View {
    public var title: String
    public var kind: AuroraButtonStyleKind
    public var isEnabled: Bool
    public var isSelected: Bool
    public var action: () -> Void

    public init(
        _ title: String,
        kind: AuroraButtonStyleKind = .secondary,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(AuroraButtonStyle(kind: kind, isSelected: isSelected))
            .disabled(!isEnabled)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AuroraButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AuroraButtonStyleKind
    let isSelected: Bool

    @Environment(\.auroraDensity) private var density
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var isPressed: Bool { configuration.isPressed && isEnabled }
    private var isLit: Bool { isEnabled && (isHovered || isSelected) }
    private var radius: CGFloat { AuroraMetrics.auroraButtonRadius }
    private var shellInset: CGFloat { kind == .quiet ? 0 : AuroraMetrics.auroraButtonShellInset }

    var body: some View {
        configuration.label
            .font(AuroraTypography.controlLabel)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, density.space(AuroraSpacing.md))
            .frame(minWidth: density.controlHeight, minHeight: density.controlHeight)
            .background(buttonShell)
            .contentShape(AuroraButtonFaceShape(cornerRadius: radius))
            .scaleEffect(isPressed ? 0.975 : 1)
            .offset(y: isPressed ? 1 : 0)
            .brightness(isHovered && !isPressed && isEnabled ? 0.045 : 0)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.09), value: isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private var buttonShell: some View {
        AuroraButtonFaceShape(cornerRadius: radius)
            .fill(Color.black.opacity(kind == .quiet ? 0 : 0.72))
            .shadow(
                color: Color.black.opacity(kind == .quiet ? 0 : (isPressed ? 0.25 : 0.48)),
                radius: isPressed ? 1 : 3,
                y: isPressed ? 0 : 2
            )
            .overlay {
                AuroraButtonFaceShape(cornerRadius: radius)
                    .fill(faceGradient)
                    .padding(shellInset)
            }
            .overlay {
                AuroraButtonFaceShape(cornerRadius: radius)
                    .strokeBorder(border, lineWidth: isSelected ? 1.25 : 0.75)
                    .padding(shellInset)
            }
            .overlay(alignment: .top) {
                if kind != .quiet {
                    AuroraButtonFaceShape(cornerRadius: radius)
                        .stroke(Color.white.opacity(isPressed ? 0.10 : 0.28), lineWidth: 0.75)
                        .padding(shellInset + 1)
                        .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                }
            }
            .overlay(alignment: .bottom) {
                if kind != .quiet || isSelected {
                    Capsule()
                        .fill(indicatorColor)
                        .frame(width: AuroraMetrics.auroraButtonIndicatorWidth, height: AuroraMetrics.auroraButtonIndicatorHeight)
                        .shadow(color: indicatorColor.opacity(isLit ? 0.55 : 0), radius: 2)
                        .padding(.bottom, shellInset + 3)
                }
            }
            .overlay {
                if isPressed {
                    AuroraButtonFaceShape(cornerRadius: radius)
                        .fill(AuroraColor.pressedOverlay)
                        .padding(shellInset)
                }
            }
    }

    private var faceGradient: LinearGradient {
        LinearGradient(colors: faceColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var faceColors: [Color] {
        switch kind {
        case .primary:
            return [AuroraColor.accentBright, AuroraColor.accent, AuroraColor.accent.opacity(0.72)]
        case .destructive:
            return [AuroraColor.critical, AuroraColor.critical.opacity(0.80), AuroraColor.critical.opacity(0.62)]
        case .secondary:
            if isSelected {
                return [AuroraColor.accent.opacity(0.72), AuroraColor.accent.opacity(0.48), AuroraColor.surfaceRaised]
            }
            return [Color.white.opacity(0.15), AuroraColor.surfaceRaised, AuroraColor.surfacePanel]
        case .quiet:
            if isSelected { return [AuroraColor.accentMuted, AuroraColor.accentMuted] }
            if isHovered { return [AuroraColor.hoverOverlay, AuroraColor.hoverOverlay] }
            return [.clear, .clear]
        }
    }

    private var foreground: Color {
        guard isEnabled else { return AuroraColor.disabled }
        switch kind {
        case .primary, .destructive: return AuroraColor.textOnAccent
        case .secondary, .quiet: return isSelected ? AuroraColor.textPrimary : AuroraColor.textSecondary
        }
    }

    private var border: Color {
        if isSelected { return AuroraColor.accentBright.opacity(0.88) }
        switch kind {
        case .primary: return AuroraColor.accentBright.opacity(0.76)
        case .destructive: return Color.white.opacity(0.20)
        case .secondary: return isHovered ? AuroraColor.accent.opacity(0.64) : Color.white.opacity(0.14)
        case .quiet: return isHovered ? Color.white.opacity(0.10) : .clear
        }
    }

    private var indicatorColor: Color {
        switch kind {
        case .primary: return Color.white.opacity(0.70)
        case .destructive: return Color.white.opacity(0.52)
        case .secondary: return isLit ? AuroraColor.accentBright.opacity(0.88) : Color.white.opacity(0.24)
        case .quiet: return isSelected ? AuroraColor.accentBright.opacity(0.78) : .clear
        }
    }
}

/// Subtle stepped shoulders echo the fader thumb without reading as literal hardware.
private struct AuroraButtonFaceShape: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let shoulder = min(2.5, r.height * 0.10)
        return Path { path in
            path.move(to: CGPoint(x: r.minX + cornerRadius, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX - cornerRadius, y: r.minY))
            path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + cornerRadius), control: CGPoint(x: r.maxX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.midY - shoulder))
            path.addLine(to: CGPoint(x: r.maxX - shoulder, y: r.midY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.midY + shoulder))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: r.maxX - cornerRadius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX + cornerRadius, y: r.maxY))
            path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - cornerRadius), control: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.midY + shoulder))
            path.addLine(to: CGPoint(x: r.minX + shoulder, y: r.midY))
            path.addLine(to: CGPoint(x: r.minX, y: r.midY - shoulder))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: r.minX + cornerRadius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
            path.closeSubpath()
        }
    }

    func inset(by amount: CGFloat) -> AuroraButtonFaceShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
