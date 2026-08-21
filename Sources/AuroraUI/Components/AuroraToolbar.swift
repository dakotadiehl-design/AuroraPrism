import AuroraDesignSystem
import SwiftUI

public struct AuroraToolbar<Leading: View, Trailing: View>: View {
    @ViewBuilder public var leading: () -> Leading
    @ViewBuilder public var trailing: () -> Trailing

    public init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: AuroraSpacing.md) {
            leading()
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, AuroraSpacing.lg)
        .frame(height: AuroraMetrics.toolbarHeight)
        .background(AuroraColor.surfaceWorkspace)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AuroraColor.separator).frame(height: 0.5)
        }
    }
}
