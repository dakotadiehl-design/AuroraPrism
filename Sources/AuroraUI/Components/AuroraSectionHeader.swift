import AuroraDesignSystem
import SwiftUI

public struct AuroraSectionHeader: View {
    public var title: String
    public var trailing: String?

    public init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack {
            Text(title.uppercased())
                .font(AuroraTypography.sectionHeading)
                .foregroundStyle(AuroraColor.textTertiary)
                .tracking(0.6)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textSecondary)
            }
        }
    }
}
