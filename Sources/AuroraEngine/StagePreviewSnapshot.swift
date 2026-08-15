import AuroraModel
import Foundation

/// Read-only semantic presentation for 2D Stage Live Preview (P0-A).
/// Derived from the same resolved path as physical output — never a second engine.
public struct PreviewColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }

    public static let black = PreviewColor(r: 0, g: 0, b: 0)
}

public struct FixturePreviewState: Equatable, Sendable, Identifiable {
    public var id: UUID { fixtureID }
    public var fixtureID: UUID
    public var intensity: Double
    public var color: PreviewColor?
    public var pan: Double?
    public var tilt: Double?
    public var isHighlight: Bool

    public init(
        fixtureID: UUID,
        intensity: Double = 0,
        color: PreviewColor? = nil,
        pan: Double? = nil,
        tilt: Double? = nil,
        isHighlight: Bool = false
    ) {
        self.fixtureID = fixtureID
        self.intensity = min(1, max(0, intensity))
        self.color = color
        self.pan = pan
        self.tilt = tilt
        self.isHighlight = isHighlight
    }
}

public struct StagePreviewSnapshot: Equatable, Sendable {
    public var frameIndex: UInt64
    public var timestamp: TimeInterval
    public var fixtures: [FixturePreviewState]
    public var dominantColor: PreviewColor
    public var blackout: Bool
    public var freeze: Bool
    public var masterIntensity: Double

    public init(
        frameIndex: UInt64 = 0,
        timestamp: TimeInterval = 0,
        fixtures: [FixturePreviewState] = [],
        dominantColor: PreviewColor = .black,
        blackout: Bool = false,
        freeze: Bool = false,
        masterIntensity: Double = 1
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.fixtures = fixtures
        self.dominantColor = dominantColor
        self.blackout = blackout
        self.freeze = freeze
        self.masterIntensity = masterIntensity
    }

    public static let empty = StagePreviewSnapshot()
}

/// Builds stage preview from a resolved ActiveLook (same authority as DMX merge).
public enum StagePreviewBuilder {
    public static func build(
        project: ShowProject,
        look: ActiveLook,
        frameIndex: UInt64,
        time: TimeInterval,
        global: GlobalShowControlState
    ) -> StagePreviewSnapshot {
        var fixtures: [FixturePreviewState] = []
        var weightedR = 0.0, weightedG = 0.0, weightedB = 0.0, weight = 0.0

        for fx in project.fixtures {
            let attrs = look.fixtureAttributes[fx.id] ?? [:]
            let intensity = attrs["intensity"] ?? attrs["dimmer"] ?? max(
                attrs["colorR"] ?? 0,
                attrs["colorG"] ?? 0,
                attrs["colorB"] ?? 0
            )
            let r = attrs["colorR"]
            let g = attrs["colorG"]
            let b = attrs["colorB"]
            let color: PreviewColor?
            if r != nil || g != nil || b != nil {
                color = PreviewColor(r: r ?? 0, g: g ?? 0, b: b ?? 0)
            } else {
                color = nil
            }
            fixtures.append(FixturePreviewState(
                fixtureID: fx.id,
                intensity: intensity,
                color: color,
                pan: attrs["pan"],
                tilt: attrs["tilt"]
            ))
            let w = intensity
            if w > 0.001 {
                if let color {
                    weightedR += color.r * w
                    weightedG += color.g * w
                    weightedB += color.b * w
                } else {
                    weightedR += w
                    weightedG += w
                    weightedB += w
                }
                weight += w
            }
        }

        let dominant: PreviewColor
        if weight > 0.001 {
            dominant = PreviewColor(
                r: weightedR / weight,
                g: weightedG / weight,
                b: weightedB / weight
            )
        } else {
            dominant = .black
        }

        return StagePreviewSnapshot(
            frameIndex: frameIndex,
            timestamp: time,
            fixtures: fixtures,
            dominantColor: dominant,
            blackout: global.blackout,
            freeze: global.freeze,
            masterIntensity: global.masterIntensity
        )
    }
}
