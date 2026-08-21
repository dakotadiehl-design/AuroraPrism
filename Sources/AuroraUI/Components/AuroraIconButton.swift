import AuroraDesignSystem
import SwiftUI

public struct AuroraIconButton: View {
    public var systemName: String
    public var label: String
    public var isEnabled: Bool
    public var isSelected: Bool
    public var action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(
        systemName: String,
        label: String,
        isEnabled: Bool = true,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.label = label
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AuroraMetrics.iconPointSize, weight: .medium))
                .foregroundStyle(isEnabled ? (isSelected ? AuroraColor.accentBright : AuroraColor.textSecondary) : AuroraColor.disabled)
                .frame(width: AuroraMetrics.iconButtonSize, height: AuroraMetrics.iconButtonSize)
                .background(isSelected ? AuroraColor.accentMuted : (isHovered && isEnabled ? AuroraColor.hoverOverlay : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous)
                        .strokeBorder(isFocused ? AuroraColor.focusRing : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
