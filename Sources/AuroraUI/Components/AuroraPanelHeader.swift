import SwiftUI

public struct AuroraPanelHeader<Trailing: View>: View {
    public var title: String
    @ViewBuilder public var trailing: () -> Trailing

    public init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: AuroraSpacing.sm) {
            Text(title)
                .font(AuroraTypography.panelTitle)
                .foregroundStyle(AuroraColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, AuroraSpacing.md)
        .frame(height: AuroraMetrics.panelHeaderHeight)
        .background(AuroraColor.surfaceHeader)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AuroraColor.separator)
                .frame(height: AuroraMetrics.hairline)
        }
    }
}
