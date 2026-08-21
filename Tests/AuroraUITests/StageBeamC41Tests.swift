import AuroraModel
import AuroraUI
import XCTest

final class StageBeamC41Tests: XCTestCase {
    func testPixelCuePreviewAveragesQualifiedRGBValues() {
        let color = CueBlockColorPreview.rgb(from: [
            "colorR@element-0": 1, "colorG@element-0": 0, "colorB@element-0": 0,
            "colorR@element-1": 1, "colorG@element-1": 0, "colorB@element-1": 0,
        ])
        XCTAssertEqual(color?.r ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(color?.g ?? 1, 0, accuracy: 0.001)
        XCTAssertEqual(color?.b ?? 1, 0, accuracy: 0.001)
    }

    func testAtmosphereGlyphGrowsWithSemanticOutput() {
        XCTAssertEqual(StageAtmosphereVisualStyle.normalizedLevel(0), 0)
        XCTAssertEqual(StageAtmosphereVisualStyle.normalizedLevel(127.5, minimum: 0, maximum: 255), 0.5, accuracy: 0.001)
        XCTAssertEqual(StageAtmosphereVisualStyle.normalizedLevel(255, minimum: 0, maximum: 255), 1)
        XCTAssertLessThan(StageAtmosphereVisualStyle.cloudScale(0), StageAtmosphereVisualStyle.cloudScale(1))
        XCTAssertLessThan(StageAtmosphereVisualStyle.cloudOpacity(0), StageAtmosphereVisualStyle.cloudOpacity(1))
    }

    func testDenseGlyphEmitterLODIsDeterministic() {
        XCTAssertEqual(FixtureGlyphLevelOfDetail.detailLevel(screenExtent: 10), 0)
        XCTAssertEqual(FixtureGlyphLevelOfDetail.detailLevel(screenExtent: 30), 1)
        XCTAssertEqual(FixtureGlyphLevelOfDetail.detailLevel(screenExtent: 80), 2)
        XCTAssertEqual(FixtureGlyphLevelOfDetail.visibleEmitterIndices(count: 100, detailLevel: 0).count, 8)
        XCTAssertEqual(FixtureGlyphLevelOfDetail.visibleEmitterIndices(count: 100, detailLevel: 1).count, 24)
        XCTAssertEqual(FixtureGlyphLevelOfDetail.visibleEmitterIndices(count: 100, detailLevel: 2).count, 100)
        XCTAssertEqual(
            FixtureGlyphLevelOfDetail.visibleEmitterIndices(count: 100, detailLevel: 0),
            FixtureGlyphLevelOfDetail.visibleEmitterIndices(count: 100, detailLevel: 0)
        )
    }
    func testWedgePointsNarrowVsBroad() {
        let origin = CGPoint(x: 100, y: 100)
        let dir = -Double.pi / 2 // up
        let narrow = StageBeamGeometry.wedgePoints(
            origin: origin, directionRadians: dir, length: 100, spreadRadians: .pi / 18
        )
        let broad = StageBeamGeometry.wedgePoints(
            origin: origin, directionRadians: dir, length: 100, spreadRadians: .pi / 2
        )
        // Far edge span: broad wider than narrow
        let narrowSpan = hypot(narrow.farLeft.x - narrow.farRight.x, narrow.farLeft.y - narrow.farRight.y)
        let broadSpan = hypot(broad.farLeft.x - broad.farRight.x, broad.farLeft.y - broad.farRight.y)
        XCTAssertGreaterThan(broadSpan, narrowSpan * 2)
        // Apex at origin
        XCTAssertEqual(narrow.apex.x, 100, accuracy: 0.001)
        XCTAssertEqual(narrow.apex.y, 100, accuracy: 0.001)
    }

    func testZeroLengthWedgeCollapses() {
        let w = StageBeamGeometry.wedgePoints(
            origin: CGPoint(x: 0, y: 0),
            directionRadians: 0,
            length: 0,
            spreadRadians: .pi / 4
        )
        XCTAssertEqual(w.farLeft.x, 0, accuracy: 0.001)
        XCTAssertEqual(w.farRight.x, 0, accuracy: 0.001)
    }

    func testDirectionResolverStaticIgnoresPan() {
        let place = StageFixturePlacement(
            fixtureID: UUID(),
            x: 0, y: 0,
            aimDirection: -.pi / 2,
            beamSpread: .pi / 6,
            beamLength: 160
        )
        let aim = StageBeamDirectionResolver.renderedAimRadians(
            placement: place,
            livePan: 1.0,
            hasPanTilt: false
        )
        XCTAssertEqual(aim, -.pi / 2, accuracy: 0.0001)
    }

    func testDirectionResolverMoverComposesPan() {
        let place = StageFixturePlacement(
            fixtureID: UUID(),
            x: 0, y: 0,
            aimDirection: 0,
            beamSpread: .pi / 8,
            beamLength: 200
        )
        let home = StageBeamDirectionResolver.renderedAimRadians(
            placement: place,
            livePan: 0.5,
            panRangeRadians: .pi,
            hasPanTilt: true
        )
        XCTAssertEqual(home, 0, accuracy: 0.0001)

        let left = StageBeamDirectionResolver.renderedAimRadians(
            placement: place,
            livePan: 0.0,
            panRangeRadians: .pi,
            hasPanTilt: true
        )
        XCTAssertEqual(left, -.pi / 2, accuracy: 0.0001)

        let right = StageBeamDirectionResolver.renderedAimRadians(
            placement: place,
            livePan: 1.0,
            panRangeRadians: .pi,
            hasPanTilt: true
        )
        XCTAssertEqual(right, .pi / 2, accuracy: 0.0001)
    }

    func testPlacementBeamFieldsRoundTripAndLegacyDefaults() throws {
        let place = StageFixturePlacement.placed(
            fixtureID: UUID(), x: 10, y: 20, category: "wash"
        )
        XCTAssertTrue(place.beamVisible)
        XCTAssertGreaterThan(place.beamSpread, StageFixturePlacement.beamDefaults(forCategory: "beam").spread)

        var layout = StageLayout.empty
        layout.fixtures = [place]
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(StageLayout.self, from: data)
        XCTAssertEqual(decoded.fixtures[0].beamLength, place.beamLength, accuracy: 0.001)
        XCTAssertEqual(decoded.fixtures[0].aimDirection, place.aimDirection, accuracy: 0.001)
        XCTAssertEqual(decoded.fixtures[0].beamRenderMode, .directional)

        // Legacy JSON without aim fields
        let fid = UUID()
        let legacy = """
        {
          "schemaVersion": 2,
          "canvasWidth": 1200,
          "canvasHeight": 800,
          "gridSize": 20,
          "snapToGrid": true,
          "fixtures": [{
            "id": "\(UUID().uuidString)",
            "fixtureID": "\(fid.uuidString)",
            "x": 1, "y": 2, "rotation": 0, "scale": 1,
            "labelVisible": true, "zIndex": 0, "locked": false, "hidden": false
          }],
          "objects": [],
          "scenic": []
        }
        """.data(using: .utf8)!
        let migrated = try JSONDecoder().decode(StageLayout.self, from: legacy)
        XCTAssertEqual(migrated.fixtures.count, 1)
        XCTAssertTrue(migrated.fixtures[0].beamVisible)
        XCTAssertGreaterThan(migrated.fixtures[0].beamLength, 0)
    }

    func testBeamDefaultsByCategory() {
        let beam = StageFixturePlacement.beamDefaults(forCategory: "beam")
        let flood = StageFixturePlacement.beamDefaults(forCategory: "flood")
        XCTAssertLessThan(beam.spread, flood.spread)
        XCTAssertGreaterThan(beam.length, flood.length)
    }

    func testBeamOpacityTracksIntensityAndIsZeroWhenOff() {
        XCTAssertEqual(StageBeamRenderStyle.atmosphereOpacity(0), 0, accuracy: 0.0001)
        XCTAssertEqual(StageBeamRenderStyle.bodyOpacity(0), 0, accuracy: 0.0001)
        XCTAssertEqual(StageBeamRenderStyle.coreOpacity(0), 0, accuracy: 0.0001)

        XCTAssertLessThan(
            StageBeamRenderStyle.bodyOpacity(0.2),
            StageBeamRenderStyle.bodyOpacity(0.6)
        )
        XCTAssertLessThan(
            StageBeamRenderStyle.bodyOpacity(0.6),
            StageBeamRenderStyle.bodyOpacity(1)
        )
    }

    func testBeamOpacityClampsOutOfRangeInput() {
        XCTAssertEqual(
            StageBeamRenderStyle.bodyOpacity(-1),
            StageBeamRenderStyle.bodyOpacity(0),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            StageBeamRenderStyle.bodyOpacity(2),
            StageBeamRenderStyle.bodyOpacity(1),
            accuracy: 0.0001
        )
    }

    func testFourVerticalElementBeamOriginsMatchPodCenters() {
        let origins = (0..<4).map {
            StageMultiElementGeometry.elementOrigin(
                fixtureOrigin: CGPoint(x: 100, y: 100),
                fixtureRotation: 0,
                index: $0,
                count: 4,
                podDiameter: 14,
                spacing: 3,
                horizontal: false
            )
        }
        XCTAssertEqual(origins.map(\.x), [100, 100, 100, 100])
        XCTAssertEqual(origins.map(\.y), [74.5, 91.5, 108.5, 125.5])
    }

    func testElementBeamOriginsRotateWithFixtureBody() {
        let first = StageMultiElementGeometry.elementOrigin(
            fixtureOrigin: CGPoint(x: 100, y: 100),
            fixtureRotation: .pi / 2,
            index: 0,
            count: 4,
            podDiameter: 14,
            spacing: 3,
            horizontal: false
        )
        XCTAssertEqual(first.x, 125.5, accuracy: 0.001)
        XCTAssertEqual(first.y, 100, accuracy: 0.001)
    }

    func testRotationStepNormalizationWrapsAtOneEightyDegrees() {
        let from135 = 135.0 * Double.pi / 180
        let rotated = StageRotateMath.normalizedRadians(from135 + .pi / 2)
        XCTAssertEqual(rotated * 180 / .pi, -135, accuracy: 0.001)
        XCTAssertEqual(StageRotateMath.normalizedRadians(4 * .pi), 0, accuracy: 0.001)
    }
}
