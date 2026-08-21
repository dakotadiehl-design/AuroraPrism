import AuroraDesignSystem
import SwiftUI

public struct AuroraInspectorSection<Content: View>: View {
    public var title: String
    @ViewBuilder public var content: () -> Content

    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AuroraSectionHeader(title)
            content()
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuroraColor.surfaceWell.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous))
        }
    }
}
