import AuroraDesignSystem
import SwiftUI

public struct AuroraNumericField: View {
    public var label: String
    @Binding public var text: String
    public var unit: String
    public var isEnabled: Bool
    public var isMixed: Bool
    public var showsOwnedChrome: Bool

    @Environment(\.auroraDensity) private var density
    @FocusState private var isFocused: Bool

    public init(
        label: String,
        text: Binding<String>,
        unit: String = "",
        isEnabled: Bool = true,
        isMixed: Bool = false,
        showsOwnedChrome: Bool = false
    ) {
        self.label = label
        self._text = text
        self.unit = unit
        self.isEnabled = isEnabled
        self.isMixed = isMixed
        self.showsOwnedChrome = showsOwnedChrome
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !label.isEmpty {
                HStack(spacing: 3) {
                    Text(label.uppercased())
                        .font(AuroraTypography.controlLabel)
                        .foregroundStyle(AuroraColor.textTertiary)
                        .tracking(0.4)
                    if showsOwnedChrome {
                        AuroraAttributeStateChrome(state: .programmerOwned)
                    }
                    if isMixed {
                        AuroraAttributeStateChrome(state: .mixed)
                    }
                }
            }
            HStack(spacing: 3) {
                TextField(isMixed ? "MIXED" : "0", text: $text)
                    .textFieldStyle(.plain)
                    .font(AuroraTypography.primaryValue)
                    .foregroundStyle(isEnabled ? AuroraColor.textPrimary : AuroraColor.disabled)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .disabled(!isEnabled)
                if !unit.isEmpty {
                    Text(unit)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: density.controlHeight)
            .background(AuroraColor.surfaceWell)
            .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 0.5)
            )
        }
    }

    private var borderColor: Color {
        if isFocused { return AuroraColor.focusRing }
        if showsOwnedChrome { return AuroraColor.accent.opacity(0.45) }
        if isMixed { return AuroraColor.warning.opacity(0.5) }
        return AuroraColor.separatorStrong
    }
}
