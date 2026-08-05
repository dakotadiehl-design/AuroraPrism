import SwiftUI

public enum AuroraPanelEdgeStyle: Sendable {
    case workstation
    case soft
}

/// Inset modular workstation panel (render-pack adjacency, not floating cards).
public struct AuroraPanel<Content: View>: View {
    public var title: String?
    public var showsHeader: Bool
    public var edgeStyle: AuroraPanelEdgeStyle
    @ViewBuilder public var content: () -> Content

    public init(
        title: String? = nil,
        showsHeader: Bool = true,
        edgeStyle: AuroraPanelEdgeStyle = .workstation,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsHeader = showsHeader
        self.edgeStyle = edgeStyle
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsHeader, let title {
                AuroraPanelHeader(title: title)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AuroraColor.surfacePanel)
        }
        .background(AuroraColor.surfacePanel)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AuroraColor.separatorStrong, lineWidth: AuroraMetrics.hairline)
        )
    }

    private var cornerRadius: CGFloat {
        edgeStyle == .workstation ? AuroraMetrics.radiusPanel : AuroraMetrics.radiusSoft
    }
}
