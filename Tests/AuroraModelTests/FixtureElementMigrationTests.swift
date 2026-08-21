import AuroraModel
import XCTest

final class FixtureElementMigrationTests: XCTestCase {
    func testDecodingLegacyFlatChannelsDoesNotMutateDMXOrInventPhysicalTopology() throws {
        let shared = [
            ChannelDef(offset: 1, name: "Mode", attribute: "mode"),
            ChannelDef(offset: 2, name: "Dimmer", attribute: "intensity"),
            ChannelDef(offset: 3, name: "Strobe", attribute: "strobe"),
        ]
        let attributes = ["colorR", "colorG", "colorB", "colorA", "colorCoolWhite", "colorUV"]
        let cells = (0..<4).flatMap { cell in
            attributes.enumerated().map { index, attribute in
                ChannelDef(
                    offset: UInt16(4 + cell * attributes.count + index),
                    name: attribute,
                    attribute: attribute
                )
            }
        }
        let legacy = FixtureDefinition(
            manufacturer: "Unseen Manufacturer",
            model: "Compound Wash",
            modeName: "27 Channel",
            channelCount: 27,
            channels: shared + cells,
            category: "wash"
        )

        let repaired = try JSONDecoder().decode(
            FixtureDefinition.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(repaired.channels.count, 27)
        XCTAssertNil(repaired.cellBlock)
        XCTAssertTrue(repaired.channels.allSatisfy { $0.elementID == nil })
        XCTAssertEqual(repaired.calculatedFootprint, 27)
        XCTAssertTrue(repaired.elements.isEmpty)
        XCTAssertTrue(repaired.resolvedVisualization().emitters.isEmpty)
    }

    func testRepeatedNonEmitterChannelsAreNotMisclassifiedAsElements() throws {
        let legacy = FixtureDefinition(
            manufacturer: "Generic",
            model: "Motion Controller",
            channels: [
                ChannelDef(offset: 1, name: "Pan 1", attribute: "pan"),
                ChannelDef(offset: 2, name: "Tilt 1", attribute: "tilt"),
                ChannelDef(offset: 3, name: "Pan 2", attribute: "pan"),
                ChannelDef(offset: 4, name: "Tilt 2", attribute: "tilt"),
            ]
        )
        let decoded = try JSONDecoder().decode(
            FixtureDefinition.self,
            from: JSONEncoder().encode(legacy)
        )
        XCTAssertNil(decoded.cellBlock)
        XCTAssertEqual(decoded.channels.count, 4)
    }

    func testRepeatedEmitterWindowRemainsPersonalityDataOnly() throws {
        let emitters = ["colorR", "colorG", "colorB", "colorA"]
        let pixels = (0..<3).flatMap { element in
            emitters.enumerated().map { index, attribute in
                ChannelDef(offset: UInt16(element * 4 + index + 1), name: attribute, attribute: attribute)
            }
        }
        let legacy = FixtureDefinition(
            manufacturer: "Any Manufacturer",
            model: "Any Linear Fixture",
            channelCount: 14,
            channels: pixels + [
                ChannelDef(offset: 13, name: "Program", attribute: "autoProgram"),
                ChannelDef(offset: 14, name: "Master", attribute: "intensity"),
            ]
        )

        let decoded = try JSONDecoder().decode(FixtureDefinition.self, from: JSONEncoder().encode(legacy))

        XCTAssertNil(decoded.cellBlock)
        XCTAssertTrue(decoded.elements.isEmpty)
        XCTAssertTrue(decoded.channels.prefix(12).allSatisfy { $0.elementID == nil })
        XCTAssertNil(decoded.channels[12].elementID)
        XCTAssertNil(decoded.channels[13].elementID)
        // DMX ownership is not physical topology. Without shared physical metadata,
        // repeated controllable elements must not manufacture physical emitters.
        XCTAssertEqual(decoded.resolvedVisualization().form, .generic)
        XCTAssertTrue(decoded.resolvedVisualization().emitters.isEmpty)
        XCTAssertTrue(decoded.resolvedVisualization().warnings.contains { $0.id == "missing-physical" })
    }

    func testManuallyAuthoredVisualMetadataRoundTripsWithoutImporter() throws {
        let visual = FixtureVisualDefinition(
            role: .atmospheric,
            bodyAspectRatio: 1.4,
            layout: .custom,
            indicators: [
                FixtureVisualIndicator(id: "haze", kind: .atmosphereCloud, attribute: "fogOutput")
            ],
            provenance: .manuallyAuthored,
            form: .atmospheric,
            topology: .compositional,
            opticalBehaviors: [.atmospheric],
            movement: .static,
            componentGroups: [
                .init(id: "outlet", role: .atmosphericOutlet, topology: .noBeam, x: 0.5, y: 0.35, width: 0.4, height: 0.2)
            ]
        )
        let definition = FixtureDefinition(
            manufacturer: "User",
            model: "New Fixture",
            channels: [ChannelDef(offset: 1, name: "Haze", attribute: "fogOutput")],
            visual: visual
        )

        let decoded = try JSONDecoder().decode(FixtureDefinition.self, from: JSONEncoder().encode(definition))
        XCTAssertEqual(decoded.visual, visual)
        XCTAssertEqual(decoded.resolvedVisual, visual)
    }
}
