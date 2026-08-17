import Foundation

public struct RGBColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }
}

public struct HSVColor: Equatable, Sendable {
    public var h: Double // 0...360
    public var s: Double // 0...1
    public var v: Double // 0...1

    public init(h: Double, s: Double, v: Double) {
        self.h = h.truncatingRemainder(dividingBy: 360)
        if self.h < 0 { self.h += 360 }
        self.s = min(1, max(0, s))
        self.v = min(1, max(0, v))
    }
}

public struct RGBWColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var w: Double

    public init(r: Double, g: Double, b: Double, w: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
        self.w = min(1, max(0, w))
    }
}

/// First-class Color Engine authoring state (retained in Programmer; not DMX channels).
public struct ColorAuthoringState: Equatable, Sendable {
    public var hue: Double // 0...360
    public var saturation: Double // 0...1
    public var brightness: Double // 0...1 (HSV value / RGB scale)
    public var whiteBalance: Double // -1...1, 0 = neutral

    public init(hue: Double = 0, saturation: Double = 1, brightness: Double = 1, whiteBalance: Double = 0) {
        self.hue = hue.truncatingRemainder(dividingBy: 360)
        if self.hue < 0 { self.hue += 360 }
        self.saturation = min(1, max(0, saturation))
        self.brightness = min(1, max(0, brightness))
        self.whiteBalance = min(1, max(-1, whiteBalance))
    }

    public static let neutral = ColorAuthoringState()
}

/// Color Engine authoring attribute keys (Programmer soft state).
public enum ColorAuthoringAttribute {
    public static let hue = "colorHue"
    public static let saturation = "colorSat"
    public static let brightness = "colorVal"
    public static let whiteBalance = "colorWB"

    public static let all: [String] = [hue, saturation, brightness, whiteBalance]

    public static func isAuthoring(_ attribute: String) -> Bool {
        all.contains(attribute)
    }
}

public enum ColorMath {
    /// Deliberate mouse detents for the inner character-ring controls.
    public static let whiteBalanceNeutralSnapDegrees = 8.0
    public static let brightnessOffSnapDegrees = 8.0

    public static func rgb(from hsv: HSVColor) -> RGBColor {
        let h = hsv.h / 60
        let c = hsv.v * hsv.s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = hsv.v - c
        let (rp, gp, bp): (Double, Double, Double)
        switch Int(h) {
        case 0: (rp, gp, bp) = (c, x, 0)
        case 1: (rp, gp, bp) = (x, c, 0)
        case 2: (rp, gp, bp) = (0, c, x)
        case 3: (rp, gp, bp) = (0, x, c)
        case 4: (rp, gp, bp) = (x, 0, c)
        default: (rp, gp, bp) = (c, 0, x)
        }
        return RGBColor(r: rp + m, g: gp + m, b: bp + m)
    }

    public static func hsv(from rgb: RGBColor) -> HSVColor {
        let maxC = max(rgb.r, rgb.g, rgb.b)
        let minC = min(rgb.r, rgb.g, rgb.b)
        let delta = maxC - minC
        var h: Double = 0
        if delta > 0 {
            if maxC == rgb.r {
                h = 60 * (((rgb.g - rgb.b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxC == rgb.g {
                h = 60 * (((rgb.b - rgb.r) / delta) + 2)
            } else {
                h = 60 * (((rgb.r - rgb.g) / delta) + 4)
            }
        }
        if h < 0 { h += 360 }
        let s = maxC == 0 ? 0 : delta / maxC
        return HSVColor(h: h, s: s, v: maxC)
    }

    /// Extract white as min channel; residual RGB.
    public static func rgbw(from rgb: RGBColor) -> RGBWColor {
        let w = min(rgb.r, rgb.g, rgb.b)
        return RGBWColor(r: rgb.r - w, g: rgb.g - w, b: rgb.b - w, w: w)
    }

    public static func rgb(cmyC c: Double, m: Double, y: Double) -> RGBColor {
        RGBColor(r: 1 - c, g: 1 - m, b: 1 - y)
    }

    /// Rough CCT (Kelvin) to RGB for UI preview (1000…15000).
    public static func rgb(fromCCT kelvin: Double) -> RGBColor {
        let temp = min(15000, max(1000, kelvin)) / 100
        var r, g, b: Double
        if temp <= 66 {
            r = 1
            g = max(0, min(1, (99.4708025861 * log(temp) - 161.1195681661) / 255))
        } else {
            r = max(0, min(1, (329.698727446 * pow(temp - 60, -0.1332047592)) / 255))
            g = max(0, min(1, (288.1221695283 * pow(temp - 60, -0.0755148492)) / 255))
        }
        if temp >= 66 {
            b = 1
        } else if temp <= 19 {
            b = 0
        } else {
            b = max(0, min(1, (138.5177312231 * log(temp - 10) - 305.0447927307) / 255))
        }
        return RGBColor(r: r, g: g, b: b)
    }

    // MARK: - Color Engine (isolated; evolvable)

    /// Warm / cool tint targets for white-balance blend (v1 model).
    private static let warmTint = RGBColor(r: 1.0, g: 0.72, b: 0.42)
    private static let coolTint = RGBColor(r: 0.65, g: 0.82, b: 1.0)

    /// Apply white-balance to RGB only. Does not touch dedicated White emitters.
    /// - Parameter whiteBalance: -1 cool … 0 neutral … +1 warm
    /// - Parameter saturationHint: 0…1 — greys shift less than saturated colors
    public static func applyWhiteBalance(
        rgb: RGBColor,
        whiteBalance: Double,
        saturationHint: Double = 1
    ) -> RGBColor {
        let w = min(1, max(-1, whiteBalance))
        if abs(w) < 1e-9 { return rgb }
        // White balance may tint emitted color, but it must never create light.
        // In particular, brightness/value zero is a hard-off invariant.
        let peakIn = max(rgb.r, max(rgb.g, rgb.b))
        if peakIn < 1e-9 { return rgb }
        let sat = min(1, max(0, saturationHint))
        let amount = abs(w) * (0.15 + 0.55 * sat)
        let tint = w > 0 ? warmTint : coolTint
        var r = rgb.r * (1 - amount) + tint.r * amount
        var g = rgb.g * (1 - amount) + tint.g * amount
        var b = rgb.b * (1 - amount) + tint.b * amount
        // Preserve approximate peak value.
        let peakOut = max(r, max(g, b))
        if peakOut > 1e-9, peakIn > 1e-9 {
            let scale = peakIn / peakOut
            r *= scale
            g *= scale
            b *= scale
        }
        return RGBColor(r: r, g: g, b: b)
    }

    /// Full Color Engine resolve: HSV authoring → RGB emitters (post white-balance).
    public static func resolvedRGB(
        hue: Double,
        saturation: Double,
        brightness: Double,
        whiteBalance: Double
    ) -> RGBColor {
        let hsv = HSVColor(h: hue, s: saturation, v: brightness)
        let base = rgb(from: hsv)
        return applyWhiteBalance(rgb: base, whiteBalance: whiteBalance, saturationHint: saturation)
    }

    public static func resolvedRGB(from authoring: ColorAuthoringState) -> RGBColor {
        resolvedRGB(
            hue: authoring.hue,
            saturation: authoring.saturation,
            brightness: authoring.brightness,
            whiteBalance: authoring.whiteBalance
        )
    }

    /// Legacy inverse: RGB only → H/S/V with neutral WB (cannot recover prior WB).
    public static func authoringFromRGB(_ rgb: RGBColor) -> ColorAuthoringState {
        let hsv = hsv(from: rgb)
        return ColorAuthoringState(
            hue: hsv.h,
            saturation: hsv.s,
            brightness: hsv.v,
            whiteBalance: 0
        )
    }

    /// Programmer attribute bag for resolved RGB (+ optional white extract path for legacy).
    public static func programmerAttributes(from rgb: RGBColor, includeWhite: Bool) -> [String: Double] {
        if includeWhite {
            let rgbw = rgbw(from: rgb)
            return [
                "colorR": rgbw.r, "colorG": rgbw.g, "colorB": rgbw.b, "colorW": rgbw.w,
            ]
        }
        return ["colorR": rgb.r, "colorG": rgb.g, "colorB": rgb.b]
    }

    /// Batch attributes: first-class authoring + derived RGB (never folds dedicated emitters).
    public static func programmerColorBatch(from authoring: ColorAuthoringState) -> [String: Double] {
        let rgb = resolvedRGB(from: authoring)
        return [
            ColorAuthoringAttribute.hue: authoring.hue,
            ColorAuthoringAttribute.saturation: authoring.saturation,
            ColorAuthoringAttribute.brightness: authoring.brightness,
            ColorAuthoringAttribute.whiteBalance: authoring.whiteBalance,
            "colorR": rgb.r,
            "colorG": rgb.g,
            "colorB": rgb.b,
        ]
    }

    /// Pointer in unit circle (origin center, +x right, +y down) → hue 0…360 (red at top).
    public static func hue(
        dx: Double,
        dy: Double
    ) -> Double {
        // atan2(dy, dx): 0 = east; we want red at top (-π/2)
        var hue = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
        if hue < 0 { hue += 1 }
        return hue * 360
    }

    /// Saturation mapped to the **visible annulus** between character ring and hue ring (C.E. 1.1).
    /// - Parameters:
    ///   - pointerRadius: distance from wheel center
    ///   - innerSatRadius: outside of character ring (sat ≈ 0)
    ///   - outerSatRadius: inside of hue ring (sat ≈ 1)
    public static func saturationInAnnulus(
        pointerRadius: Double,
        innerSatRadius: Double,
        outerSatRadius: Double
    ) -> Double {
        let span = outerSatRadius - innerSatRadius
        guard span > 1e-9 else { return 0 }
        return min(1, max(0, (pointerRadius - innerSatRadius) / span))
    }

    /// Inverse: thumb radius for a given saturation in the annulus.
    public static func saturationThumbRadius(
        saturation: Double,
        innerSatRadius: Double,
        outerSatRadius: Double
    ) -> Double {
        let sat = min(1, max(0, saturation))
        return innerSatRadius + sat * (outerSatRadius - innerSatRadius)
    }

    /// Legacy helper: hue + sat treating maxRadius as outer sat edge from center.
    public static func hueSaturation(
        dx: Double,
        dy: Double,
        maxRadius: Double
    ) -> (hue: Double, saturation: Double) {
        let h = hue(dx: dx, dy: dy)
        let r = sqrt(dx * dx + dy * dy)
        let s = maxRadius > 1e-9 ? min(1, r / maxRadius) : 0
        return (h, s)
    }

    // MARK: White-balance arc (single convention for gesture + marker)

    /// Screen angle in degrees: 0 = east, 90 = south, ±180 = west, -90 = north.
    /// Left half-ring: cool (WB=-1) at north (−90°), neutral at west (180°), warm (WB=+1) at south (90°).
    public static func whiteBalanceAngleDegrees(_ whiteBalance: Double) -> Double {
        let w = min(1, max(-1, whiteBalance))
        // w=-1 → -90, w=0 → 180, w=+1 → 90
        // Use: angle = 180 - w * 90  → -1 → 270 (-90), 0 → 180, +1 → 90
        // Prefer cool at top: w=-1 → -90, w=+1 → 90: angle = -w * 90 when on left…
        // Spec: cool top, warm bottom on left. sin-based gesture: WB = sin(angle) with S=+1 warm, N=-1 cool.
        // Inverse: angle = asin(w) but only left side: for w=0 use 180°.
        if abs(w) < 1e-9 { return 180 }
        // Place on left semicircle: angle from asin in range where cos is negative.
        let a = asin(min(1, max(-1, w))) * 180 / .pi // -90…90
        // Mirror to left: use 180 - a → w=-1 → 270, w=1 → 90, w=0 → 180
        return 180 - a
    }

    /// Inverse of `whiteBalanceAngleDegrees` for left-half pointer angles.
    public static func whiteBalance(fromAngleDegrees angle: Double) -> Double {
        // West (±180°) is the true-color position. Give it a useful physical
        // detent instead of requiring pixel-perfect pointer placement.
        if angularDistanceDegrees(angle, 180) <= whiteBalanceNeutralSnapDegrees {
            return 0
        }
        // Canonical: WB = sin(angle) with angle in degrees (S = +1 warm, N = -1 cool, W = 0).
        return min(1, max(-1, sin(angle * .pi / 180)))
    }

    /// Brightness marker on right half: bri=1 → north (−90°), bri=0 → south (90°).
    public static func brightnessAngleDegrees(_ brightness: Double) -> Double {
        let b = min(1, max(0, brightness))
        return -90 + (1 - b) * 180
    }

    public static func brightness(fromAngleDegrees angle: Double) -> Double {
        // angle -90…90 → bri 1…0
        // The bottom detent must resolve to literal zero so derived RGB output
        // is black and the fixture is off, even if the pointer is a few pixels
        // away from the exact vertical axis.
        if angularDistanceDegrees(angle, 90) <= brightnessOffSnapDegrees {
            return 0
        }
        let t = (angle + 90) / 180
        return min(1, max(0, 1 - t))
    }

    private static func angularDistanceDegrees(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    public static func clampProgrammerAttribute(_ attribute: String, value: Double) -> Double {
        if attribute == ColorAuthoringAttribute.hue {
            var h = value.truncatingRemainder(dividingBy: 360)
            if h < 0 { h += 360 }
            return h
        }
        if attribute == ColorAuthoringAttribute.whiteBalance {
            return min(1, max(-1, value))
        }
        return min(1, max(0, value))
    }
}
