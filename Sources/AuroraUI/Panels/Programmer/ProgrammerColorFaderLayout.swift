import CoreGraphics
import Foundation

/// Prism-specific layout helpers for the programmer's color fader region.
public enum ProgrammerColorFaderLayout {
    public static let defaultSpacing: CGFloat = 10
    public static let defaultWheelMinWidth: CGFloat = 180

    public static func responsiveChannelHeight(
        availableHeight: CGFloat,
        baseChannelHeight: CGFloat,
        basePanelHeight: CGFloat,
        maximumGrowth: CGFloat = 72,
        growthRate: CGFloat = 0.38
    ) -> CGFloat {
        let extraHeight = max(0, availableHeight - basePanelHeight)
        return baseChannelHeight + min(maximumGrowth, extraHeight * growthRate)
    }

    public static func emittersContentWidth(
        emitterCount: Int,
        faderWidth: CGFloat,
        spacing: CGFloat = defaultSpacing
    ) -> CGFloat {
        guard emitterCount > 0 else { return 0 }
        return CGFloat(emitterCount) * faderWidth + CGFloat(max(0, emitterCount - 1)) * spacing
    }

    public static func emitterRegionNeedsScroll(
        availableWidth: CGFloat,
        emitterCount: Int,
        faderWidth: CGFloat,
        spacing: CGFloat = defaultSpacing
    ) -> Bool {
        emittersContentWidth(emitterCount: emitterCount, faderWidth: faderWidth, spacing: spacing)
            > availableWidth + 0.5
    }

    public static func minimumProgrammerWidth(
        dimmerWidth: CGFloat,
        wheelMinWidth: CGFloat = defaultWheelMinWidth,
        faderWidth: CGFloat,
        spacing: CGFloat = 16
    ) -> CGFloat {
        dimmerWidth + wheelMinWidth + faderWidth + spacing * 2
    }

    public static func displayLabel(_ full: String, maxChars: Int = 10) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            let first = String(parts[0])
            let rest = parts.dropFirst().map { String($0.prefix(1)) + "." }.joined(separator: " ")
            let candidate = "\(first) \(rest)"
            if candidate.count <= maxChars + 2 { return candidate }
        }
        return String(trimmed.prefix(max(0, maxChars - 1))) + "…"
    }
}
