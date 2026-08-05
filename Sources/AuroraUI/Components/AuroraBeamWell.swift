import SwiftUI

/// Circular beam preview well.
public struct AuroraBeamWell: View {
    public var label: String
    public var zoom: Double
    public var isSelected: Bool

    public init(label: String = "BEAM", zoom: Double = 0.4, isSelected: Bool = false) {
        self.label = label
        self.zoom = zoom
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                AuroraAssetIcon(.beam, size: 11)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text(label.uppercased())
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(0.5)
            }
            ZStack {
                Circle()
                    .fill(AuroraColor.surfaceWell)
                    .frame(width: AuroraMetrics.beamWellSize, height: AuroraMetrics.beamWellSize)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.05)],
                            center: .center,
                            startRadius: 1,
                            endRadius: AuroraMetrics.beamWellSize * (0.2 + zoom * 0.35)
                        )
                    )
                    .frame(width: AuroraMetrics.beamWellSize - 8, height: AuroraMetrics.beamWellSize - 8)
                Circle()
                    .strokeBorder(isSelected ? AuroraColor.accent : AuroraColor.separatorStrong, lineWidth: isSelected ? 1.5 : 0.5)
                    .frame(width: AuroraMetrics.beamWellSize, height: AuroraMetrics.beamWellSize)
            }
            Text("Zoom \(Int(zoom * 100))%")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textSecondary)
        }
    }
}

/// Simple gobo icon matrix for Programmer.
public struct AuroraGoboMatrix: View {
    public var selected: Int

    public init(selected: Int = 2) {
        self.selected = selected
    }

    private let symbols = [
        "circle", "circle.grid.cross", "asterisk", "diamond",
        "star", "hexagon", "seal", "aqi.medium",
    ]

    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                AuroraAssetIcon(.gobo, size: 11)
                    .foregroundStyle(AuroraColor.textTertiary)
                Text("GOBOS")
                    .font(AuroraTypography.controlLabel)
                    .foregroundStyle(AuroraColor.textTertiary)
                    .tracking(0.5)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(i == selected ? AuroraColor.accentMuted : AuroraColor.surfaceWell)
                        Group {
                            if i == 0 {
                                AuroraAssetIcon(.gobo, size: 10)
                            } else {
                                Image(systemName: symbols[i])
                                    .font(.system(size: 9, weight: .medium))
                            }
                        }
                        .foregroundStyle(i == selected ? AuroraColor.accentBright : AuroraColor.textSecondary)
                    }
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(i == selected ? AuroraColor.accent : AuroraColor.separator, lineWidth: 0.5)
                    )
                }
            }
            Text("Wheel 1")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
        }
    }
}
