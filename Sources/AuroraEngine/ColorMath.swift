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

public enum ColorMath {
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

    public static func programmerAttributes(from rgb: RGBColor, includeWhite: Bool) -> [String: Double] {
        if includeWhite {
            let rgbw = rgbw(from: rgb)
            return [
                "colorR": rgbw.r, "colorG": rgbw.g, "colorB": rgbw.b, "colorW": rgbw.w,
            ]
        }
        return ["colorR": rgb.r, "colorG": rgb.g, "colorB": rgb.b]
    }
}
