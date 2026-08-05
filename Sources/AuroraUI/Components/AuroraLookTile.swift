import SwiftUI

/// Rich look / preset tile — creative object, not a settings button.
public struct AuroraLookTile: View {
    public var name: String
    public var colors: [Color]
    public var isSelected: Bool
    public var action: () -> Void

    public init(
        name: String,
        colors: [Color] = [
            Color(red: 1, green: 0.55, blue: 0.2),
            Color(red: 0.2, green: 0.35, blue: 0.9),
            Color.white.opacity(0.8),
        ],
        isSelected: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.name = name
        self.colors = colors
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: AuroraMetrics.lookTileWidth, height: AuroraMetrics.lookTileHeight)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous))
                        )
                    if isSelected {
                        RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            .frame(width: AuroraMetrics.lookTileWidth, height: AuroraMetrics.lookTileHeight)
                    }
                }
                Text(name)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textSecondary)
                    .lineLimit(1)
                    .frame(width: AuroraMetrics.lookTileWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Look \(name)")
    }
}

/// Back-compat preset tile used by older gallery sections.
public struct AuroraPresetTile: View {
    public var name: String
    public var subtitle: String?
    public var isSelected: Bool
    public var isEnabled: Bool
    public var action: () -> Void

    public init(
        name: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void = {}
    ) {
        self.name = name
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        AuroraLookTile(
            name: name,
            colors: [
                Color(red: 1, green: 0.55, blue: 0.2),
                Color(red: 0.2, green: 0.35, blue: 0.9),
                Color.white.opacity(0.75),
            ],
            isSelected: isSelected,
            action: action
        )
        .opacity(isEnabled ? 1 : 0.45)
    }
}
