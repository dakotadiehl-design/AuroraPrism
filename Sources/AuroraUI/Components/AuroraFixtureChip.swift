import AuroraDesignSystem
import SwiftUI

/// Selected fixture chip under Programmer attribute row.
public struct AuroraFixtureChip: View {
    public var name: String
    public var isSelected: Bool
    public var action: () -> Void

    public init(name: String, isSelected: Bool = false, action: @escaping () -> Void = {}) {
        self.name = name
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isSelected ? AuroraColor.accentMuted : AuroraColor.surfaceRaised)
                    .frame(width: 36, height: 20)
                    .overlay(
                        AuroraAssetIcon(.intensity, size: 10)
                            .foregroundStyle(isSelected ? AuroraColor.accentBright : AuroraColor.textTertiary)
                    )
                Text(name)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(isSelected ? AuroraColor.textPrimary : AuroraColor.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(isSelected ? AuroraColor.surfaceSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous)
                    .strokeBorder(isSelected ? AuroraColor.accent.opacity(0.7) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
