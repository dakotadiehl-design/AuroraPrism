import SwiftUI

public enum AuroraCueRowRole: Sendable {
    case normal
    case current
    case next
    case selected
    case warning
}

/// Columnar cue row: state | number | name | trigger | timing
/// Single-click selects; optional double-click fires (callers map separately).
public struct AuroraCueRow: View {
    public var number: String
    public var name: String
    public var timing: String
    public var trigger: String
    public var role: AuroraCueRowRole
    /// Select / inspect only — must not fire.
    public var onSelect: () -> Void
    /// Intentional fire (double-click). Nil disables double-click fire.
    public var onDoubleClickFire: (() -> Void)?

    @Environment(\.auroraDensity) private var density
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(
        number: String,
        name: String,
        timing: String = "",
        trigger: String = "Manual",
        role: AuroraCueRowRole = .normal,
        onSelect: @escaping () -> Void = {},
        onDoubleClickFire: (() -> Void)? = nil
    ) {
        self.number = number
        self.name = name
        self.timing = timing
        self.trigger = trigger
        self.role = role
        self.onSelect = onSelect
        self.onDoubleClickFire = onDoubleClickFire
    }

    public var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                onDoubleClickFire?()
            }
            .onTapGesture(count: 1) {
                onSelect()
            }
            .focused($isFocused)
            .onHover { isHovered = $0 }
            .accessibilityLabel(accessibilityText)
            .accessibilityAction(named: "Select") { onSelect() }
            .accessibilityAction(named: "Fire") { onDoubleClickFire?() }
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(railColor)
                .frame(width: role == .normal ? 0 : AuroraMetrics.railWidth)

            HStack(spacing: 0) {
                Text(number)
                    .font(AuroraTypography.cueNumber)
                    .foregroundStyle(numberColor)
                    .frame(width: 40, alignment: .leading)
                Text(name)
                    .font(AuroraTypography.tableCell)
                    .foregroundStyle(AuroraColor.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(trigger)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .frame(width: 64, alignment: .leading)
                Text(timing)
                    .font(AuroraTypography.timingReadout)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: density.rowHeight)
        }
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: 0.5)
        }
        .overlay(
            Rectangle()
                .strokeBorder(isFocused ? AuroraColor.focusRing : Color.clear, lineWidth: 1)
        )
    }

    private var railColor: Color {
        switch role {
        case .current, .selected: return AuroraColor.accent
        case .next: return AuroraColor.railNext
        case .warning: return AuroraColor.warning
        case .normal: return .clear
        }
    }

    private var rowBackground: Color {
        switch role {
        case .current, .selected: return AuroraColor.surfaceSelected
        case .warning: return AuroraColor.warningMuted
        case .next: return isHovered ? AuroraColor.hoverOverlay : .clear
        case .normal: return isHovered ? AuroraColor.hoverOverlay : .clear
        }
    }

    private var numberColor: Color {
        switch role {
        case .current, .selected: return AuroraColor.accentBright
        case .warning: return AuroraColor.warning
        default: return AuroraColor.textSecondary
        }
    }

    private var accessibilityText: String {
        var parts = ["Cue \(number)", name]
        switch role {
        case .current: parts.append("current")
        case .next: parts.append("next")
        case .selected: parts.append("selected")
        case .warning: parts.append("warning")
        case .normal: break
        }
        if !timing.isEmpty { parts.append(timing) }
        return parts.joined(separator: ", ")
    }
}
