import AuroraModel
import AuroraUI
import XCTest

final class StageBeamC41Tests: XCTestCase {
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
}
