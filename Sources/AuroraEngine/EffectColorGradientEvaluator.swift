import AuroraModel
import Foundation

public enum EffectColorGradientEvaluator {
    public static func color(at rawPosition: Double, gradient: CompiledEffectColorGradient) -> RGBColor {
        let shifted = rawPosition + gradient.positionOffset
        var position = (0...1).contains(shifted) ? shifted : fract(shifted)
        if gradient.reversed { position = 1 - position }
        if gradient.mirrored { position = abs(position * 2 - 1) }
        guard let first = gradient.stops.first else { return RGBColor(r: 0, g: 0, b: 0) }
        if position <= first.position { return rgb(first.color) }
        guard let last = gradient.stops.last, position < last.position else { return rgb(gradient.stops.last?.color ?? first.color) }
        guard let upperIndex = gradient.stops.firstIndex(where: { $0.position > position }), upperIndex > 0 else { return rgb(last.color) }
        let lower = gradient.stops[upperIndex - 1]
        let upper = gradient.stops[upperIndex]
        let span = upper.position - lower.position
        let amount = span > 0 ? (position - lower.position) / span : 1
        return interpolate(from: rgb(lower.color), to: rgb(upper.color), amount: amount, mode: gradient.interpolation)
    }

    private static func interpolate(from: RGBColor, to: RGBColor, amount: Double, mode: EffectColorInterpolation) -> RGBColor {
        let t = min(1, max(0, amount))
        if mode == .rgb {
            return RGBColor(r: from.r + (to.r - from.r) * t, g: from.g + (to.g - from.g) * t, b: from.b + (to.b - from.b) * t)
        }
        let a = ColorMath.hsv(from: from)
        let b = ColorMath.hsv(from: to)
        var delta = b.h - a.h
        switch mode {
        case .hsvShortest:
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
        case .hsvClockwise:
            if delta < 0 { delta += 360 }
        case .hsvCounterClockwise:
            if delta > 0 { delta -= 360 }
        case .rgb: break
        }
        return ColorMath.rgb(from: HSVColor(h: a.h + delta * t, s: a.s + (b.s - a.s) * t, v: a.v + (b.v - a.v) * t))
    }

    private static func rgb(_ color: EffectColor) -> RGBColor { RGBColor(r: color.red, g: color.green, b: color.blue) }
    private static func fract(_ value: Double) -> Double {
        let result = value - floor(value)
        return result < 0 ? result + 1 : result
    }
}
