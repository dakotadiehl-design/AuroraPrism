import SwiftUI

public struct AuroraSidebarItem: View {
    public var title: String
    public var systemImage: String
    public var isSelected: Bool
    public var action: () -> Void

    public init(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? AuroraColor.accentBright : AuroraColor.textTertiary)
                    .frame(width: 16)
                Text(title)
                    .font(AuroraTypography.secondary)
                    .foregroundStyle(isSelected ? AuroraColor.textPrimary : AuroraColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isSelected ? AuroraColor.surfaceSelected : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(AuroraColor.accent)
                        .frame(width: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
