import AuroraModel
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Pure wedge math (C4.1)

/// Testable Stage beam wedge geometry — not a Capsule.
public enum StageBeamGeometry {
    /// Apex + far-left + far-right points of a tapered wedge.
    /// - Parameters:
    ///   - origin: Fixture glyph center (or beam origin) in Stage world.
    ///   - directionRadians: Beam centerline (0 = +X, increasing clockwise to match SwiftUI rotation).
    ///   - length: Reach along centerline.
    ///   - spreadRadians: Full fan angle at the far end.
    public static func wedgePoints(
        origin: CGPoint,
        directionRadians: Double,
        length: Double,
        spreadRadians: Double
    ) -> (apex: CGPoint, farLeft: CGPoint, farRight: CGPoint) {
        let len = max(0, length)
        let half = max(0.005, spreadRadians * 0.5)
        let leftAngle = directionRadians - half
        let rightAngle = directionRadians + half
        // SwiftUI: 0° = right, positive = clockwise. CG: same if y increases downward.
        func point(angle: Double, dist: Double) -> CGPoint {
            CGPoint(
                x: origin.x + CGFloat(cos(angle) * dist),
                y: origin.y + CGFloat(sin(angle) * dist)
            )
        }
        return (
            apex: origin,
            farLeft: point(angle: leftAngle, dist: len),
            farRight: point(angle: rightAngle, dist: len)
        )
    }

    /// Closed path for a beam wedge (triangle; far edge is the base).
    public static func wedgePath(
        origin: CGPoint,
        directionRadians: Double,
        length: Double,
        spreadRadians: Double
    ) -> Path {
        let w = wedgePoints(
            origin: origin,
            directionRadians: directionRadians,
            length: length,
            spreadRadians: spreadRadians
        )
        var p = Path()
        p.move(to: w.apex)
        p.addLine(to: w.farLeft)
        p.addLine(to: w.farRight)
        p.closeSubpath()
        return p
    }

    /// Soft outer + firmer inner wedge spreads (for layered fill).
    public static func layeredSpreads(fullSpread: Double) -> (outer: Double, inner: Double) {
        let s = max(0.02, fullSpread)
        return (outer: s * 1.15, inner: s * 0.55)
    }
}

/// SwiftUI shape for a Stage beam wedge.
public struct StageBeamWedgeShape: Shape {
    public var origin: CGPoint
    public var directionRadians: Double
    public var length: Double
    public var spreadRadians: Double

    public init(origin: CGPoint, directionRadians: Double, length: Double, spreadRadians: Double) {
        self.origin = origin
        self.directionRadians = directionRadians
        self.length = length
        self.spreadRadians = spreadRadians
    }

    public func path(in _: CGRect) -> Path {
        StageBeamGeometry.wedgePath(
            origin: origin,
            directionRadians: directionRadians,
            length: length,
            spreadRadians: spreadRadians
        )
    }
}

// MARK: - Atmospheric beam renderer

/// Layered, direction-aware 2D beam. Gradients are drawn from the fixture origin
/// to the beam tip, avoiding the flat stained-glass triangle produced by a
/// bounding-box gradient on a rotated wedge.
public struct StageBeamView: View {
    public var origin: CGPoint
    public var directionRadians: Double
    public var length: Double
    public var spreadRadians: Double
    public var color: Color
    public var intensity: Double
    public var detailLevel: Int

    public init(
        origin: CGPoint,
        directionRadians: Double,
        length: Double,
        spreadRadians: Double,
        color: Color,
        intensity: Double,
        detailLevel: Int
    ) {
        self.origin = origin
        self.directionRadians = directionRadians
        self.length = length
        self.spreadRadians = spreadRadians
        self.color = color
        self.intensity = intensity
        self.detailLevel = detailLevel
    }

    public var body: some View {
        Canvas { context, _ in
            let level = StageBeamRenderStyle.clampedIntensity(intensity)
            guard level > 0.001, length > 1 else { return }
            let tip = CGPoint(
                x: origin.x + CGFloat(cos(directionRadians) * length),
                y: origin.y + CGFloat(sin(directionRadians) * length)
            )

            // Wide atmospheric spill. Blur supplies lateral edge feathering;
            // the directional gradient removes the hard far edge.
            let atmosphere = StageBeamGeometry.wedgePath(
                origin: origin,
                directionRadians: directionRadians,
                length: length,
                spreadRadians: spreadRadians * 1.16
            )
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: detailLevel >= 2 ? 7 : 4))
                layer.fill(
                    atmosphere,
                    with: directionalShading(
                        opacity: StageBeamRenderStyle.atmosphereOpacity(level),
                        start: origin,
                        end: tip,
                        terminal: 0
                    )
                )
            }

            // Main body: broad near the source, gently luminous through the
            // middle, then fully transparent before the geometric endpoint.
            let body = StageBeamGeometry.wedgePath(
                origin: origin,
                directionRadians: directionRadians,
                length: length * 0.98,
                spreadRadians: spreadRadians
            )
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: detailLevel >= 2 ? 2.2 : 1.2))
                layer.fill(
                    body,
                    with: directionalShading(
                        opacity: StageBeamRenderStyle.bodyOpacity(level),
                        start: origin,
                        end: tip,
                        terminal: 0
                    )
                )
            }

            // Narrow optical core appears progressively with output level.
            if detailLevel >= 2, level > 0.08 {
                let core = StageBeamGeometry.wedgePath(
                    origin: origin,
                    directionRadians: directionRadians,
                    length: length * 0.90,
                    spreadRadians: max(0.018, spreadRadians * 0.34)
                )
                context.blendMode = .plusLighter
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.4))
                    layer.fill(
                        core,
                        with: directionalShading(
                            opacity: StageBeamRenderStyle.coreOpacity(level),
                            start: origin,
                            end: tip,
                            terminal: 0
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func directionalShading(
        opacity: Double,
        start: CGPoint,
        end: CGPoint,
        terminal: Double
    ) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(stops: [
                .init(color: color.opacity(opacity * 0.98), location: 0.00),
                .init(color: color.opacity(opacity), location: 0.16),
                .init(color: color.opacity(opacity * 0.68), location: 0.55),
                .init(color: color.opacity(opacity * 0.22), location: 0.84),
                .init(color: color.opacity(terminal), location: 1.00),
            ]),
            startPoint: start,
            endPoint: end
        )
    }
}

public enum StageBeamRenderStyle {
    public static func clampedIntensity(_ intensity: Double) -> Double {
        min(1, max(0, intensity))
    }

    public static func atmosphereOpacity(_ intensity: Double) -> Double {
        0.28 * pow(clampedIntensity(intensity), 0.72)
    }

    public static func bodyOpacity(_ intensity: Double) -> Double {
        0.50 * pow(clampedIntensity(intensity), 0.82)
    }

    public static func coreOpacity(_ intensity: Double) -> Double {
        0.42 * pow(clampedIntensity(intensity), 1.18)
    }
}

// MARK: - Direction composition (C4.1 Step 7)

/// Maps physical Stage aim + optional live Pan/Tilt into a rendered beam direction.
///
/// **Do not** embed ad-hoc `(pan - 0.5) * 360` in the canvas view.
///
/// TODO(C4.x): Prefer personality-defined physical Pan/Tilt ranges (e.g. 540° pan, 270° tilt)
/// from fixture definitions when those fields exist. Today `FixtureDefinition` only exposes
/// `hasPanTilt` — approximate normalized visualization is isolated here until ranges ship.
public enum StageBeamDirectionResolver {
    /// Default visualization pan swing when personality range is unknown (±135°).
    public static let fallbackPanSwingRadians: Double = (270.0 * .pi / 180.0)

    /// - Parameters:
    ///   - placement: Stage geometry including physical `aimDirection`.
    ///   - livePan: Normalized 0…1 pan from engine, if available.
    ///   - liveTilt: Normalized 0…1 tilt (optional length/spread influence elsewhere).
    ///   - panRangeRadians: Full physical pan range from personality when known.
    ///   - hasPanTilt: Whether this fixture is a mover for live composition.
    public static func renderedAimRadians(
        placement: StageFixturePlacement,
        livePan: Double?,
        liveTilt: Double? = nil,
        panRangeRadians: Double? = nil,
        hasPanTilt: Bool = false
    ) -> Double {
        _ = liveTilt // reserved for future mild aim bias; length/spread modulated by caller
        guard hasPanTilt, let pan = livePan else {
            return placement.aimDirection
        }
        // TODO(C4.x): map using personality-defined physical ranges when available on FixtureDefinition.
        let range = panRangeRadians ?? fallbackPanSwingRadians
        // pan 0.5 = home (no offset); 0 / 1 = ± half range
        let offset = (pan - 0.5) * range
        return placement.aimDirection + offset
    }

    /// Mild length scale from tilt (look down → slightly longer visualization).
    public static func lengthScale(liveTilt: Double?) -> Double {
        guard let t = liveTilt else { return 1 }
        // tilt 0.5 = neutral; higher = tip toward floor in many desks → slightly longer
        return 0.85 + 0.3 * t
    }

    /// Mild spread scale from tilt.
    public static func spreadScale(liveTilt: Double?) -> Double {
        guard let t = liveTilt else { return 1 }
        return 0.9 + 0.2 * (1 - abs(t - 0.5) * 2)
    }
}
