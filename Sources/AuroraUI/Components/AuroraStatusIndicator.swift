import AuroraDesignSystem
import SwiftUI

public enum AuroraHealthLevel: String, Sendable, CaseIterable {
    case healthy
    case warning
    case failed
    case disabled
    case unknown

    public var color: Color {
        switch self {
        case .healthy: return AuroraColor.success
        case .warning: return AuroraColor.warning
        case .failed: return AuroraColor.critical
        case .disabled, .unknown: return AuroraColor.disabled
        }
    }

    public var accessibilityAdjective: String {
        switch self {
        case .healthy: return "healthy"
        case .warning: return "warning"
        case .failed: return "failed"
        case .disabled: return "disabled"
        case .unknown: return "unknown"
        }
    }
}

public struct AuroraStatusIndicator: View {
    public var label: String
    public var level: AuroraHealthLevel
    public var compact: Bool

    public init(label: String, level: AuroraHealthLevel, compact: Bool = false) {
        self.label = label
        self.level = level
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotFill)
                .frame(width: dotSize, height: dotSize)
            if !compact {
                Text(label)
                    .font(AuroraTypography.status)
                    .foregroundStyle(labelColor)
            }
        }
        .padding(.horizontal, level == .warning || level == .failed ? 6 : 0)
        .padding(.vertical, level == .warning || level == .failed ? 2 : 0)
        .background(badgeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityLabel("\(label) \(level.accessibilityAdjective)")
    }

    private var dotSize: CGFloat {
        (level == .warning || level == .failed) ? AuroraMetrics.statusDotEmphasis : AuroraMetrics.statusDotSize
    }

    private var dotFill: Color {
        switch level {
        case .healthy: return AuroraColor.successMuted
        case .warning: return AuroraColor.warning
        case .failed: return AuroraColor.critical
        case .disabled, .unknown: return AuroraColor.disabled
        }
    }

    private var labelColor: Color {
        switch level {
        case .healthy: return AuroraColor.textTertiary
        case .warning: return AuroraColor.warning
        case .failed: return AuroraColor.critical
        case .disabled, .unknown: return AuroraColor.disabled
        }
    }

    private var badgeBackground: Color {
        switch level {
        case .warning: return AuroraColor.warningMuted
        case .failed: return AuroraColor.criticalMuted
        default: return .clear
        }
    }
}
