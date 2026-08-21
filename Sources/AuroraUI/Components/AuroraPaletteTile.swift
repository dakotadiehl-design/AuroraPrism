import AuroraDesignSystem
import SwiftUI

public enum AuroraPaletteKind: Sendable {
    case color
    case position
    case beam
    case gobo
}

/// Creative palette object — color chips or beam/position icons.
public struct AuroraPaletteTile: View {
    public var name: String
    public var swatch: Color
    public var kind: AuroraPaletteKind
    public var isSelected: Bool
    public var isEnabled: Bool
    public var positionSymbol: String?
    public var action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(
        name: String,
        swatch: Color = Color.gray,
        kind: AuroraPaletteKind = .color,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        positionSymbol: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.name = name
        self.swatch = swatch
        self.kind = kind
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.positionSymbol = positionSymbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                swatchView
                    .frame(width: AuroraMetrics.paletteTileWidth, height: AuroraMetrics.paletteSwatchHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraMetrics.radiusControl, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: isSelected || isFocused ? 1.5 : 0.5)
                    )
                Text(name)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(isEnabled ? AuroraColor.textSecondary : AuroraColor.disabled)
                    .lineLimit(1)
                    .frame(width: AuroraMetrics.paletteTileWidth)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Palette \(name)")
    }

    @ViewBuilder
    private var swatchView: some View {
        switch kind {
        case .color:
            swatch
        case .position:
            ZStack {
                AuroraColor.surfaceWell
                AuroraAssetIcon(.position, size: 16)
                    .foregroundStyle(AuroraColor.textPrimary.opacity(0.85))
            }
        case .beam:
            ZStack {
                AuroraColor.surfaceWell
                AuroraAssetIcon(.beam, size: 16)
                    .foregroundStyle(AuroraColor.textSecondary)
            }
        case .gobo:
            ZStack {
                AuroraColor.surfaceWell
                AuroraAssetIcon(.gobo, size: 16)
                    .foregroundStyle(AuroraColor.textSecondary)
            }
        }
    }

    private var borderColor: Color {
        if isFocused { return AuroraColor.focusRing }
        if isSelected { return AuroraColor.accent }
        return Color.white.opacity(0.1)
    }
}

/// Compact square color chip for palette strips.
public struct AuroraPaletteSwatch: View {
    public var color: Color
    public var isSelected: Bool
    public var action: () -> Void

    public init(color: Color, isSelected: Bool = false, action: @escaping () -> Void = {}) {
        self.color = color
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: AuroraMetrics.colorChipSize, height: AuroraMetrics.colorChipSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Beam shape icon for palette shelf.
public struct AuroraBeamPaletteIcon: View {
    public var name: String
    public var systemImage: String
    public var isSelected: Bool

    public init(name: String, systemImage: String, isSelected: Bool = false) {
        self.name = name
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(AuroraColor.surfaceWell)
                    .frame(width: AuroraMetrics.beamIconSize, height: AuroraMetrics.beamIconSize)
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? AuroraColor.accentBright : AuroraColor.textSecondary)
            }
            .overlay(
                Circle()
                    .strokeBorder(isSelected ? AuroraColor.accent : AuroraColor.separator, lineWidth: 0.5)
            )
            Text(name)
                .font(.system(size: 8))
                .foregroundStyle(AuroraColor.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 36)
    }
}
