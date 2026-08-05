import SwiftUI

public struct AuroraEmptyState: View {
    public var title: String
    public var detail: String
    public var systemImage: String

    public init(title: String, detail: String = "", systemImage: String = "circle.dashed") {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: AuroraSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(AuroraColor.textTertiary)
            Text(title)
                .font(AuroraTypography.sectionHeading)
                .foregroundStyle(AuroraColor.textSecondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AuroraSpacing.lg)
    }
}
