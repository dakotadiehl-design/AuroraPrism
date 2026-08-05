import SwiftUI

public enum AuroraDensity: String, CaseIterable, Sendable, Equatable {
    case compact
    case standard
    case performance

    public var controlHeight: CGFloat {
        switch self {
        case .compact: return AuroraMetrics.controlHeightCompact
        case .standard: return AuroraMetrics.controlHeightStandard
        case .performance: return AuroraMetrics.controlHeightPerformance
        }
    }

    public var rowHeight: CGFloat {
        switch self {
        case .compact: return AuroraMetrics.rowHeightCompact
        case .standard: return AuroraMetrics.rowHeightStandard
        case .performance: return AuroraMetrics.rowHeightPerformance
        }
    }

    public var spacingScale: CGFloat {
        switch self {
        case .compact: return 0.7
        case .standard: return 0.9
        case .performance: return 1.4
        }
    }

    public func space(_ base: CGFloat) -> CGFloat {
        (base * spacingScale).rounded()
    }

    public var panelPadding: CGFloat {
        switch self {
        case .compact: return AuroraSpacing.sm
        case .standard: return AuroraSpacing.md
        case .performance: return AuroraSpacing.lg
        }
    }

    public var sectionSpacing: CGFloat {
        switch self {
        case .compact: return AuroraSpacing.xs
        case .standard: return AuroraSpacing.sm
        case .performance: return AuroraSpacing.md
        }
    }
}

private struct AuroraDensityKey: EnvironmentKey {
    static let defaultValue: AuroraDensity = .standard
}

extension EnvironmentValues {
    public var auroraDensity: AuroraDensity {
        get { self[AuroraDensityKey.self] }
        set { self[AuroraDensityKey.self] = newValue }
    }
}

extension View {
    public func auroraDensity(_ density: AuroraDensity) -> some View {
        environment(\.auroraDensity, density)
    }
}
