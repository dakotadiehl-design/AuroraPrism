import AuroraDesignSystem
import SwiftUI

public enum AuroraWorkspaceChromeMode: String, CaseIterable, Sendable {
    case build = "BUILD"
    case perform = "PERFORM"
}

/// BUILD | PERFORM segmented control — active segment filled with accent.
public struct AuroraModeToggle: View {
    @Binding public var mode: AuroraWorkspaceChromeMode

    public init(mode: Binding<AuroraWorkspaceChromeMode>) {
        self._mode = mode
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(AuroraWorkspaceChromeMode.allCases, id: \.self) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.rawValue)
                        .font(AuroraTypography.status)
                        .tracking(0.6)
                        .foregroundStyle(mode == item ? AuroraColor.textOnAccent : AuroraColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(mode == item ? AuroraColor.accent : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(AuroraColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous)
                .strokeBorder(AuroraColor.separatorStrong, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace mode")
    }
}
