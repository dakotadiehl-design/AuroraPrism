import SwiftUI

public struct AuroraSearchField: View {
    @Binding public var text: String
    public var placeholder: String

    @Environment(\.auroraDensity) private var density
    @FocusState private var isFocused: Bool

    public init(text: Binding<String>, placeholder: String = "Search") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AuroraColor.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AuroraTypography.secondary)
                .foregroundStyle(AuroraColor.textPrimary)
                .focused($isFocused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AuroraColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: density.controlHeight)
        .background(AuroraColor.surfaceWell)
        .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraMetrics.radiusTight, style: .continuous)
                .strokeBorder(isFocused ? AuroraColor.focusRing : AuroraColor.separator, lineWidth: 0.5)
        )
    }
}
