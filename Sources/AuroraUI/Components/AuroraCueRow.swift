import AuroraDesignSystem
import SwiftUI

/// Playback rail/role — independent of selection overlay (CR-09).
public enum AuroraCuePlaybackRole: Sendable {
    case normal
    case current
    case next
    case warning
}

/// Back-compat single-axis role (maps selected → selection overlay).
public enum AuroraCueRowRole: Sendable {
    case normal
    case current
    case next
    case selected
    case warning
}

/// Columnar cue row: playback role × selection overlay (CR-09).
/// Single-click selects; optional double-click fires (callers map separately).
public struct AuroraCueRow: View {
    public var number: String
    public var name: String
    public var timing: String
    public var trigger: String
    public var playbackRole: AuroraCuePlaybackRole
    public var isSelected: Bool
    public var onSelect: () -> Void
    public var onDoubleClickFire: (() -> Void)?

    @Environment(\.auroraDensity) private var density
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(
        number: String,
        name: String,
        timing: String = "",
        trigger: String = "Manual",
        playbackRole: AuroraCuePlaybackRole = .normal,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {},
        onDoubleClickFire: (() -> Void)? = nil
    ) {
        self.number = number
        self.name = name
        self.timing = timing
        self.trigger = trigger
        self.playbackRole = playbackRole
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDoubleClickFire = onDoubleClickFire
    }

    /// Legacy single-role init — selection replaces playback when `.selected`.
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
        switch role {
        case .selected:
            self.playbackRole = .normal
            self.isSelected = true
        case .current:
            self.playbackRole = .current
            self.isSelected = false
        case .next:
            self.playbackRole = .next
            self.isSelected = false
        case .warning:
            self.playbackRole = .warning
            self.isSelected = false
        case .normal:
            self.playbackRole = .normal
            self.isSelected = false
        }
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
                .frame(width: showRail ? AuroraMetrics.railWidth : 0)

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
                .strokeBorder(selectionBorder, lineWidth: isSelected || isFocused ? 1.5 : 0)
        )
    }

    private var showRail: Bool {
        playbackRole != .normal || isSelected
    }

    private var selectionBorder: Color {
        if isFocused { return AuroraColor.focusRing }
        if isSelected { return AuroraColor.accentBright.opacity(0.85) }
        return .clear
    }

    private var railColor: Color {
        switch playbackRole {
        case .current: return AuroraColor.accent
        case .next: return AuroraColor.railNext
        case .warning: return AuroraColor.warning
        case .normal: return isSelected ? AuroraColor.accent.opacity(0.5) : .clear
        }
    }

    private var rowBackground: Color {
        if playbackRole == .current {
            return AuroraColor.surfaceSelected
        }
        if playbackRole == .warning {
            return AuroraColor.warningMuted
        }
        if isSelected {
            return AuroraColor.surfaceSelected.opacity(0.55)
        }
        if playbackRole == .next {
            return isHovered ? AuroraColor.hoverOverlay : Color.white.opacity(0.02)
        }
        return isHovered ? AuroraColor.hoverOverlay : .clear
    }

    private var numberColor: Color {
        switch playbackRole {
        case .current: return AuroraColor.accentBright
        case .warning: return AuroraColor.warning
        default: return isSelected ? AuroraColor.accentBright.opacity(0.9) : AuroraColor.textSecondary
        }
    }

    private var accessibilityText: String {
        var parts = ["Cue \(number)", name]
        switch playbackRole {
        case .current: parts.append("current")
        case .next: parts.append("next")
        case .warning: parts.append("warning")
        case .normal: break
        }
        if isSelected { parts.append("selected") }
        if !timing.isEmpty { parts.append(timing) }
        return parts.joined(separator: ", ")
    }
}
