import SwiftUI

/// Dense workspace tab strip (Patch / Groups / Palettes / …).
public struct AuroraWorkspaceTabs: View {
    public var tabs: [String]
    @Binding public var selection: String

    public init(tabs: [String], selection: Binding<String>) {
        self.tabs = tabs
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab)
                        .font(AuroraTypography.tab)
                        .foregroundStyle(selection == tab ? AuroraColor.textPrimary : AuroraColor.textTertiary)
                        .padding(.horizontal, 10)
                        .frame(height: AuroraMetrics.tabHeight)
                        .background(selection == tab ? AuroraColor.accentMuted : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selection == tab {
                                Rectangle()
                                    .fill(AuroraColor.accent)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .background(AuroraColor.surfaceHeader)
    }
}
