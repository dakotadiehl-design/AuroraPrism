import AuroraFixtureLib
import AuroraModel
import XCTest

final class FixtureImporterTests: XCTestCase {
    func testImportNativeSeedShape() throws {
        let json = """
        {
          "id": "20000000-0000-4000-8000-000000000099",
          "manufacturer": "TestCo",
          "model": "Widget",
          "modeName": "1ch",
          "channelCount": 1,
          "channels": [
            {
              "id": "21000000-0000-4000-8000-000000000099",
              "offset": 1,
              "name": "Dimmer",
              "attribute": "intensity",
              "resolution": "eightBit",
              "defaultValue": 0,
              "highlightValue": 255
            }
          ],
          "hasPanTilt": false,
          "panInvert": false,
          "tiltInvert": false,
          "wheels": []
        }
        """.data(using: .utf8)!
        let defs = try FixtureImporter.importDefinitions(from: json)
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(defs[0].manufacturer, "TestCo")
        XCTAssertEqual(defs[0].channels[0].attribute, "intensity")
    }

    func testImportOFLLiteRGB() throws {
        let json = """
        {
          "name": "RGB Par",
          "manufacturer": "Generic",
          "modes": [
            {
              "name": "3-channel",
              "channels": ["Red", "Green", "Blue"]
            }
          ]
        }
        """.data(using: .utf8)!
        let defs = try FixtureImporter.importDefinitions(from: json)
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(defs[0].channels.map(\.attribute), ["colorR", "colorG", "colorB"])
        XCTAssertEqual(defs[0].colorModel, .rgb)
        XCTAssertEqual(defs[0].channelCount, 3)
    }

    func testAttributeHeuristics() {
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Dimmer"), "intensity")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Pan Fine"), "pan")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Tilt"), "tilt")
    }

    func testRejectEmptyGarbage() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try FixtureImporter.importDefinitions(from: data))
    }
}
