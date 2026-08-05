import SwiftUI

public struct AuroraStatusBarItem: Identifiable, Sendable {
    public let id: String
    public var label: String
    public var level: AuroraHealthLevel

    public init(id: String = UUID().uuidString, label: String, level: AuroraHealthLevel) {
        self.id = id
        self.label = label
        self.level = level
    }
}

/// Bottom health strip (sACN / Art-Net / FPS mock).
public struct AuroraStatusBar: View {
    public var items: [AuroraStatusBarItem]
    public var trailing: String

    public init(items: [AuroraStatusBarItem], trailing: String = "") {
        self.items = items
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: AuroraSpacing.md) {
            ForEach(items) { item in
                AuroraStatusIndicator(label: item.label, level: item.level)
            }
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
        }
        .padding(.horizontal, AuroraSpacing.md)
        .frame(height: AuroraMetrics.statusBarHeight)
        .background(AuroraColor.surfaceBase)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AuroraColor.separator)
                .frame(height: AuroraMetrics.hairline)
        }
    }
}
