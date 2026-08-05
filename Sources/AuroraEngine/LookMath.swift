import AuroraModel
import Foundation

/// Attribute-look blending helpers (normalized 0…1).
public enum LookMath {
    public static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        let t = min(1, max(0, t))
        return a + (b - a) * t
    }

    public static func lerp(_ from: ActiveLook, _ to: ActiveLook, t: Double) -> ActiveLook {
        let t = min(1, max(0, t))
        if t <= 0 { return from }
        if t >= 1 { return to }

        var fixtureIDs = Set(from.fixtureAttributes.keys)
        fixtureIDs.formUnion(to.fixtureAttributes.keys)

        var result: [UUID: [String: Double]] = [:]
        for id in fixtureIDs {
            let fa = from.fixtureAttributes[id] ?? [:]
            let ta = to.fixtureAttributes[id] ?? [:]
            var keys = Set(fa.keys)
            keys.formUnion(ta.keys)
            var attrs: [String: Double] = [:]
            for key in keys {
                let a = fa[key] ?? 0
                let b = ta[key] ?? 0
                // If only on one side, treat missing as 0 for fade (channel defaults apply at merge).
                attrs[key] = lerp(a, b, t: t)
            }
            if !attrs.isEmpty {
                result[id] = attrs
            }
        }
        return ActiveLook(fixtureAttributes: result)
    }

    public static func mergeLevels(into look: inout ActiveLook, levels: CueLevelData) {
        for fixture in levels.fixtures {
            var attrs = look.fixtureAttributes[fixture.fixtureId] ?? [:]
            for (key, value) in fixture.attributes {
                attrs[key] = min(1, max(0, value))
            }
            look.fixtureAttributes[fixture.fixtureId] = attrs
        }
    }

    public static func activeLook(from levels: CueLevelData) -> ActiveLook {
        var look = ActiveLook()
        mergeLevels(into: &look, levels: levels)
        return look
    }
}
