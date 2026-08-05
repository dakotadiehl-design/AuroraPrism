import SwiftUI

/// Columnar table chrome for cue lists and MIDI mappings.
public struct AuroraTableColumn: Identifiable, Sendable {
    public let id: String
    public var title: String
    public var width: CGFloat?

    public init(id: String, title: String, width: CGFloat? = nil) {
        self.id = id
        self.title = title
        self.width = width
    }
}

public struct AuroraTableHeader: View {
    public var columns: [AuroraTableColumn]

    public init(columns: [AuroraTableColumn]) {
        self.columns = columns
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(columns) { col in
                Text(col.title.uppercased())
                    .font(AuroraTypography.tableHeader)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(0.4)
                    .frame(width: col.width, alignment: .leading)
                    .frame(maxWidth: col.width == nil ? .infinity : nil, alignment: .leading)
                    .padding(.horizontal, 6)
            }
        }
        .frame(height: AuroraMetrics.tableHeaderHeight)
        .background(AuroraColor.surfaceHeader)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: 0.5)
        }
    }
}

public enum AuroraTableRowRole: Sendable {
    case normal
    case selected
    case current
    case warning
}

public struct AuroraTableRow<Content: View>: View {
    public var role: AuroraTableRowRole
    @ViewBuilder public var content: () -> Content

    @State private var isHovered = false

    public init(role: AuroraTableRowRole = .normal, @ViewBuilder content: @escaping () -> Content) {
        self.role = role
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(rail)
                .frame(width: role == .normal ? 0 : AuroraMetrics.railWidth)
            content()
                .font(AuroraTypography.tableCell)
                .foregroundStyle(AuroraColor.textPrimary)
        }
        .frame(minHeight: AuroraMetrics.tableRowHeight)
        .background(background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: 0.5)
        }
        .onHover { isHovered = $0 }
    }

    private var rail: Color {
        switch role {
        case .current, .selected: return AuroraColor.accent
        case .warning: return AuroraColor.warning
        case .normal: return .clear
        }
    }

    private var background: Color {
        switch role {
        case .selected, .current: return AuroraColor.surfaceSelected
        case .warning: return AuroraColor.warningMuted
        case .normal: return isHovered ? AuroraColor.hoverOverlay : .clear
        }
    }
}
