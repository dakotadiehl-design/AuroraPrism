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

    /// C.E. 1.1: most-specific emitter names before generic White.
    func testDedicatedEmitterNameSpecificity() {
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Warm White"), "colorWarmWhite")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Cool White"), "colorCoolWhite")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "WW"), "colorWarmWhite")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "CW"), "colorCoolWhite")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "White"), "colorW")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "UV"), "colorUV")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Ultraviolet"), "colorUV")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Amber"), "colorA")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Lime"), "colorLime")
        XCTAssertEqual(FixtureImporter.attribute(forChannelName: "Cyan"), "colorCyan")
        // Warm White must NOT collapse to generic White
        XCTAssertNotEqual(FixtureImporter.attribute(forChannelName: "Warm White"), "colorW")
    }

    func testRejectEmptyGarbage() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try FixtureImporter.importDefinitions(from: data)) { error in
            XCTAssertEqual(error as? FixtureImportError, .unsupportedFormat)
        }
    }

    func testImportPrismFixturePackage() throws {
        let json = """
        {
          "schema": "prism-fixture-converter/0.1",
          "fixture": {
            "manufacturer": "ABD",
            "model": "18x18W LED PAR Light"
          },
          "fixtureDefinitions": [
            {
              "id": "34bb9178-f7f9-5b95-9d18-acf228be86f9",
              "manufacturer": "ABD",
              "model": "18x18W LED PAR Light",
              "modeName": "6 Channel",
              "channelCount": 6,
              "channels": [
                { "offset": 0, "name": "Red", "attribute": "colorR", "defaultValue": 0, "highlightValue": 0 },
                { "offset": 1, "name": "Green", "attribute": "colorG", "defaultValue": 0, "highlightValue": 0 },
                { "offset": 2, "name": "Blue", "attribute": "colorB", "defaultValue": 0, "highlightValue": 0 },
                { "offset": 3, "name": "CoolWhite", "attribute": "colorCoolWhite", "defaultValue": 0, "highlightValue": 0 },
                { "offset": 4, "name": "Amber", "attribute": "colorA", "defaultValue": 0, "highlightValue": 0 },
                { "offset": 5, "name": "Ultraviolet", "attribute": "colorUV", "defaultValue": 0, "highlightValue": 0 }
              ],
              "hasPanTilt": false
            }
          ],
          "warnings": []
        }
        """.data(using: .utf8)!
        let defs = try FixtureImporter.importDefinitions(from: json)
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(defs[0].manufacturer, "ABD")
        XCTAssertEqual(defs[0].model, "18x18W LED PAR Light")
        XCTAssertEqual(defs[0].modeName, "6 Channel")
        XCTAssertEqual(defs[0].channelCount, 6)
        // Prism 0-based offsets become Aurora 1-based.
        XCTAssertEqual(defs[0].channels.map(\.offset), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(defs[0].channels.map(\.attribute), [
            "colorR", "colorG", "colorB", "colorCoolWhite", "colorA", "colorUV"
        ])
        XCTAssertEqual(defs[0].colorModel, .rgbw)
    }

    func testImportRealPrismSmokeFile() throws {
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/AuroraFixtureLibTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // repo root
                .appendingPathComponent("smoketest files/ABD_-_18x18W_LED_PAR_Light.prism-fixture.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("smoketest files/ABD_-_18x18W_LED_PAR_Light.prism-fixture.json"),
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("smoketest prism fixture not found relative to test host")
        }
        let defs = try FixtureImporter.importDefinitions(from: url)
        XCTAssertEqual(defs.count, 2, "file has 6ch and 10ch modes")
        XCTAssertTrue(defs.contains { $0.modeName.contains("6") && $0.channelCount == 6 })
        XCTAssertTrue(defs.contains { $0.modeName.contains("10") && $0.channelCount == 10 })
        let six = try XCTUnwrap(defs.first { $0.channelCount == 6 })
        XCTAssertEqual(six.channels.first?.offset, 1, "offsets normalized to 1-based")
        let ten = try XCTUnwrap(defs.first { $0.channelCount == 10 })
        XCTAssertEqual(ten.channels.first?.attribute, "intensity")
        // Function channel should carry DMX ranges from prism "functions".
        let functionCh = ten.channels.first { $0.name == "Function" }
        XCTAssertNotNil(functionCh)
        XCTAssertFalse(functionCh?.dmxFunctions.isEmpty ?? true)
    }

    /// Shehds Lightkey export embeds one `NSMutableString` bag for a function name; must not
    /// collapse the whole package to "unsupported format".
    func testImportPrismWithCocoaNSMutableStringName() throws {
        let json = """
        {
          "schema": "prism-fixture-converter/0.1",
          "fixture": { "manufacturer": "Shehds", "model": "LED PAR 18x18W" },
          "fixtureDefinitions": [
            {
              "id": "8453eabb-fe1a-529a-a89e-41504a32cc96",
              "manufacturer": "Shehds",
              "model": "LED PAR 18x18W",
              "modeName": "12 Channel",
              "channelCount": 2,
              "channels": [
                {
                  "offset": 0,
                  "name": "Intensity",
                  "attribute": "intensity",
                  "defaultValue": 0,
                  "highlightValue": 255,
                  "functions": [
                    { "dmxMin": 0, "dmxMax": 255, "params": {} }
                  ]
                },
                {
                  "offset": 1,
                  "name": "Auto Speed",
                  "attribute": "generic",
                  "defaultValue": 0,
                  "highlightValue": 0,
                  "functions": [
                    {
                      "dmxMin": 0,
                      "dmxMax": 255,
                      "params": {
                        "name": {
                          "_class": "NSMutableString",
                          "NS.string": "Slow > Fast"
                        },
                        "continuous": true
                      }
                    }
                  ]
                }
              ],
              "hasPanTilt": false
            }
          ],
          "warnings": []
        }
        """.data(using: .utf8)!
        let defs = try FixtureImporter.importDefinitions(from: json)
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(defs[0].manufacturer, "Shehds")
        XCTAssertEqual(defs[0].channelCount, 2)
        let speed = try XCTUnwrap(defs[0].channels.first { $0.name == "Auto Speed" })
        XCTAssertEqual(speed.dmxFunctions.first?.name, "Slow > Fast")
    }

    func testImportRealShehdsPrismSmokeFile() throws {
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "smoketest files/Shehds_-_LED_PAR_18x18W_RGBWA_UV.prism-fixture.json"
                ),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(
                    "smoketest files/Shehds_-_LED_PAR_18x18W_RGBWA_UV.prism-fixture.json"
                ),
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Shehds smoketest prism fixture not found")
        }
        let defs = try FixtureImporter.importDefinitions(from: url)
        XCTAssertEqual(defs.count, 3, "12ch / 120ch / 108ch modes")
        XCTAssertTrue(defs.contains { $0.modeName.contains("12") && $0.channelCount == 12 })
        XCTAssertTrue(defs.contains { $0.channelCount == 120 })
        XCTAssertTrue(defs.contains { $0.channelCount == 108 })
        XCTAssertEqual(defs.first?.manufacturer, "Shehds")
        let twelve = try XCTUnwrap(defs.first { $0.channelCount == 12 })
        XCTAssertEqual(twelve.channels.first?.offset, 1)
        XCTAssertEqual(twelve.channels.first?.attribute, "intensity")
    }

    func testUnsupportedFormatHasReadableMessage() {
        let err = FixtureImportError.unsupportedFormat
        XCTAssertTrue(err.localizedDescription.lowercased().contains("unsupported"))
        XCTAssertTrue(err.localizedDescription.lowercased().contains("prism"))
    }
}
