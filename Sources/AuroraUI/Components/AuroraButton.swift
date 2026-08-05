import SwiftUI

public enum AuroraButtonStyleKind: Sendable {
    case primary
    case secondary
    case destructive
    case quiet
}

public struct AuroraButton: View {
    public var title: String
    public var kind: AuroraButtonStyleKind
    public var isEnabled: Bool
    public var isSelected: Bool
    public var action: () -> Void

    @Environment(\.auroraDensity) private var density
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

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
        Button(action: action) {
            Text(title)
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(foreground)
                .padding(.horizontal, density.space(AuroraSpacing.md))
                .frame(minHeight: density.controlHeight)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous)
                        .strokeBorder(border, lineWidth: isFocused ? AuroraMetrics.focusRingWidth : 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return AuroraColor.textOnAccent
        case .destructive: return AuroraColor.textOnAccent
        case .secondary, .quiet:
            return isEnabled ? AuroraColor.textPrimary : AuroraColor.disabled
        }
    }

    private var background: Color {
        let hover = isHovered && isEnabled
        switch kind {
        case .primary: return hover ? AuroraColor.accentBright : AuroraColor.accent
        case .destructive: return hover ? AuroraColor.critical.opacity(0.9) : AuroraColor.critical.opacity(0.8)
        case .secondary:
            if isSelected { return AuroraColor.surfaceSelected }
            return hover ? AuroraColor.surfaceRaised : AuroraColor.surfaceRaised.opacity(0.85)
        case .quiet:
            if isSelected { return AuroraColor.accentMuted }
            return hover ? AuroraColor.hoverOverlay : Color.clear
        }
    }

    private var border: Color {
        if isFocused { return AuroraColor.focusRing }
        switch kind {
        case .primary, .destructive, .quiet: return Color.clear
        case .secondary: return isSelected ? AuroraColor.accent.opacity(0.4) : AuroraColor.separator
        }
    }
}
