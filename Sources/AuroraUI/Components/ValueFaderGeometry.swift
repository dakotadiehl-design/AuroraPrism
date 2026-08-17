import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Density-resolved metrics (Option C value-thumb)

/// Geometry tokens for the custom vertical value-thumb fader.
///
/// **Travel** is thumb-center travel (distance the center can move), not channel height.
/// Channel height = travel + thumbHeight so the thumb stays fully visible at 0% and 100%.
public struct ValueFaderMetrics: Equatable, Sendable {
    public var controlWidth: CGFloat
    public var channelWidth: CGFloat
    public var trackWidth: CGFloat
    public var thumbWidth: CGFloat
    public var thumbHeight: CGFloat
    public var thumbRadius: CGFloat
    /// Distance the thumb **center** can travel; resolved from density and optional container sizing.
    public var thumbTravelHeight: CGFloat
    public var tickInset: CGFloat
    public var focusRingWidth: CGFloat

    public init(
        controlWidth: CGFloat,
        channelWidth: CGFloat,
        trackWidth: CGFloat,
        thumbWidth: CGFloat,
        thumbHeight: CGFloat,
        thumbRadius: CGFloat,
        thumbTravelHeight: CGFloat,
        tickInset: CGFloat,
        focusRingWidth: CGFloat
    ) {
        self.controlWidth = controlWidth
        self.channelWidth = channelWidth
        self.trackWidth = trackWidth
        self.thumbWidth = thumbWidth
        self.thumbHeight = thumbHeight
        self.thumbRadius = thumbRadius
        self.thumbTravelHeight = thumbTravelHeight
        self.tickInset = tickInset
        self.focusRingWidth = focusRingWidth
    }

    public var channelHeight: CGFloat { thumbTravelHeight + thumbHeight }
    public var thumbHalfHeight: CGFloat { thumbHeight / 2 }

    /// Returns the same width/thumb metrics with a caller-selected channel height.
    /// The thumb size remains fixed so resizing a window changes travel, not grabability.
    public func withChannelHeight(_ height: CGFloat) -> ValueFaderMetrics {
        var copy = self
        copy.thumbTravelHeight = max(1, height - thumbHeight)
        return copy
    }

    public static func forDensity(_ density: AuroraDensity) -> ValueFaderMetrics {
        switch density {
        case .compact:
            // Same grab target as standard; slightly shorter travel only.
            return ValueFaderMetrics(
                controlWidth: AuroraMetrics.valueFaderWidth,
                channelWidth: AuroraMetrics.valueFaderChannelWidth,
                trackWidth: AuroraMetrics.valueFaderTrackWidth,
                thumbWidth: AuroraMetrics.valueFaderThumbWidth,
                thumbHeight: AuroraMetrics.valueFaderThumbHeight,
                thumbRadius: AuroraMetrics.valueFaderThumbRadius,
                thumbTravelHeight: AuroraMetrics.valueFaderTravelCompact,
                tickInset: AuroraMetrics.valueFaderTickInset,
                focusRingWidth: AuroraMetrics.valueFaderFocusRingWidth
            )
        case .standard:
            return ValueFaderMetrics(
                controlWidth: AuroraMetrics.valueFaderWidth,
                channelWidth: AuroraMetrics.valueFaderChannelWidth,
                trackWidth: AuroraMetrics.valueFaderTrackWidth,
                thumbWidth: AuroraMetrics.valueFaderThumbWidth,
                thumbHeight: AuroraMetrics.valueFaderThumbHeight,
                thumbRadius: AuroraMetrics.valueFaderThumbRadius,
                thumbTravelHeight: AuroraMetrics.valueFaderTravel,
                tickInset: AuroraMetrics.valueFaderTickInset,
                focusRingWidth: AuroraMetrics.valueFaderFocusRingWidth
            )
        case .performance:
            return ValueFaderMetrics(
                controlWidth: AuroraMetrics.valueFaderWidthPerformance,
                channelWidth: AuroraMetrics.valueFaderChannelWidthPerformance,
                trackWidth: AuroraMetrics.valueFaderTrackWidthPerformance,
                thumbWidth: AuroraMetrics.valueFaderThumbWidthPerformance,
                thumbHeight: AuroraMetrics.valueFaderThumbHeightPerformance,
                thumbRadius: AuroraMetrics.valueFaderThumbRadiusPerformance,
                thumbTravelHeight: AuroraMetrics.valueFaderTravelPerformance,
                tickInset: AuroraMetrics.valueFaderTickInsetPerformance,
                focusRingWidth: AuroraMetrics.valueFaderFocusRingWidth
            )
        }
    }
}

// MARK: - Pure geometry

/// Endpoint-safe value ↔ position mapping and drag-offset model for Option C faders.
public enum ValueFaderGeometry {
    /// Effective travel when the container height may differ from the design channel height.
    public static func travel(channelHeight: CGFloat, thumbHeight: CGFloat) -> CGFloat {
        max(1, channelHeight - thumbHeight)
    }

    public static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Y coordinate of the thumb center (0 at top of channel).
    public static func thumbCenterY(
        value: Double,
        channelHeight: CGFloat,
        thumbHeight: CGFloat
    ) -> CGFloat {
        let v = clamp01(value)
        let half = thumbHeight / 2
        let t = travel(channelHeight: channelHeight, thumbHeight: thumbHeight)
        return half + CGFloat(1 - v) * t
    }

    public static func thumbCenterY(value: Double, metrics: ValueFaderMetrics) -> CGFloat {
        thumbCenterY(
            value: value,
            channelHeight: metrics.channelHeight,
            thumbHeight: metrics.thumbHeight
        )
    }

    /// Normalize a thumb-center Y into 0...1 (1 at top of travel / high value at top of UI is inverted: high value = low Y).
    public static func value(
        fromThumbCenterY y: CGFloat,
        channelHeight: CGFloat,
        thumbHeight: CGFloat
    ) -> Double {
        let half = thumbHeight / 2
        let t = travel(channelHeight: channelHeight, thumbHeight: thumbHeight)
        let local = min(t, max(0, y - half))
        return clamp01(Double(1 - local / t))
    }

    public static func value(fromThumbCenterY y: CGFloat, metrics: ValueFaderMetrics) -> Double {
        value(fromThumbCenterY: y, channelHeight: metrics.channelHeight, thumbHeight: metrics.thumbHeight)
    }

    /// Pointer offset relative to thumb center at drag start. Seek outside thumb uses 0.
    public static func dragOffset(
        pointerY: CGFloat,
        thumbCenterY: CGFloat
    ) -> CGFloat {
        pointerY - thumbCenterY
    }

    /// Whether the pointer is inside the thumb bounds at the given center.
    public static func pointerHitsThumb(
        pointerY: CGFloat,
        thumbCenterY: CGFloat,
        thumbHeight: CGFloat
    ) -> Bool {
        let half = thumbHeight / 2
        return pointerY >= thumbCenterY - half && pointerY <= thumbCenterY + half
    }

    /// Value from current pointer, applying an offset captured at drag start (0 for seek).
    public static func value(
        fromPointerY pointerY: CGFloat,
        dragOffset: CGFloat,
        channelHeight: CGFloat,
        thumbHeight: CGFloat
    ) -> Double {
        let effectiveCenterY = pointerY - dragOffset
        return value(
            fromThumbCenterY: effectiveCenterY,
            channelHeight: channelHeight,
            thumbHeight: thumbHeight
        )
    }

    /// X coordinate of a horizontal thumb center, keeping the whole thumb in bounds.
    public static func thumbCenterX(
        value: Double,
        trackWidth: CGFloat,
        thumbWidth: CGFloat
    ) -> CGFloat {
        let half = thumbWidth / 2
        return half + CGFloat(clamp01(value)) * travel(channelHeight: trackWidth, thumbHeight: thumbWidth)
    }

    /// Normalize a horizontal thumb-center X into 0...1.
    public static func value(
        fromThumbCenterX x: CGFloat,
        trackWidth: CGFloat,
        thumbWidth: CGFloat
    ) -> Double {
        let half = thumbWidth / 2
        let t = travel(channelHeight: trackWidth, thumbHeight: thumbWidth)
        return clamp01(Double(min(t, max(0, x - half)) / t))
    }

    public static func pointerHitsThumb(
        pointerX: CGFloat,
        thumbCenterX: CGFloat,
        thumbWidth: CGFloat
    ) -> Bool {
        let half = thumbWidth / 2
        return pointerX >= thumbCenterX - half && pointerX <= thumbCenterX + half
    }

    public static func value(
        fromPointerX pointerX: CGFloat,
        dragOffset: CGFloat,
        trackWidth: CGFloat,
        thumbWidth: CGFloat
    ) -> Double {
        value(
            fromThumbCenterX: pointerX - dragOffset,
            trackWidth: trackWidth,
            thumbWidth: thumbWidth
        )
    }

    public static func value(
        fromPointerY pointerY: CGFloat,
        dragOffset: CGFloat,
        metrics: ValueFaderMetrics
    ) -> Double {
        value(
            fromPointerY: pointerY,
            dragOffset: dragOffset,
            channelHeight: metrics.channelHeight,
            thumbHeight: metrics.thumbHeight
        )
    }

    /// First keyboard step while display is mixed (display sits at mid; do not use stale binding).
    public static func mixedFirstKeyboardValue(increment: Bool) -> Double {
        increment ? 0.51 : 0.49
    }

    /// Keyboard step sizes (fraction 0...1).
    public static func keyboardStep(shift: Bool, option: Bool) -> Double {
        if option { return 0.05 }
        if shift { return 0.001 }
        return 0.01
    }

    public static let accessibilityStep: Double = 0.05

    /// Apply a delta from a base value (mixed first-edit uses mid-based start via caller).
    public static func applyStep(current: Double, delta: Double) -> Double {
        clamp01(current + delta)
    }
}

// MARK: - Programmer color layout (pure)

/// Layout helpers so emitter overflow scrolls without crushing the color wheel.
public enum ProgrammerColorFaderLayout {
    public static let defaultSpacing: CGFloat = 10
    public static let defaultWheelMinWidth: CGFloat = 180

    /// Grows the faders gently with their panel instead of consuming all vertical space.
    /// `basePanelHeight` includes the label/chrome allowance used by the color engine.
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

    /// Minimum width for dimmer + wheel + at least one fader column.
    public static func minimumProgrammerWidth(
        dimmerWidth: CGFloat,
        wheelMinWidth: CGFloat = defaultWheelMinWidth,
        faderWidth: CGFloat,
        spacing: CGFloat = 16
    ) -> CGFloat {
        dimmerWidth + wheelMinWidth + faderWidth + spacing * 2
    }

    /// Abbreviate long emitter labels for the fader header while a11y keeps the full name.
    public static func displayLabel(_ full: String, maxChars: Int = 10) -> String {
        let trimmed = full.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        // Prefer word-aware: "Cool White" → "Cool W."
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            let first = String(parts[0])
            let rest = parts.dropFirst().map { String($0.prefix(1)) + "." }.joined(separator: " ")
            let candidate = "\(first) \(rest)"
            if candidate.count <= maxChars + 2 { return candidate }
        }
        return String(trimmed.prefix(maxChars - 1)) + "…"
    }
}
