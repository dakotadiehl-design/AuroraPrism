import AuroraFixtureLib
import XCTest

final class LightKeyFixtureImporterTests: XCTestCase {
    func testImportsAttachedChauvetFixture() throws {
        let url = URL(fileURLWithPath: "/Users/dakota/code/LightKey Fixtures/Chauvet - 4Bar Hex ILS.lightkeyfxt")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Local LightKey fixture corpus is not installed")
        }

        let result = try LightKeyFixtureImporter.inspect(url: url)
        XCTAssertEqual(result.manufacturer, "Chauvet")
        XCTAssertEqual(result.model, "4Bar Hex ILS")
        XCTAssertEqual(result.numberOfBeams, 4)
        XCTAssertEqual(result.beamSpreadDegrees, 16)
        XCTAssertEqual(result.candidates.map(\.definition.channelCount), [6, 8, 27])
        XCTAssertEqual(result.candidates.last?.definition.modeName, "27 Channel")
        XCTAssertTrue(result.candidates.allSatisfy { !$0.definition.channels.isEmpty })

        let repeated = try LightKeyFixtureImporter.inspect(url: url)
        XCTAssertEqual(result.candidates.map(\.id), repeated.candidates.map(\.id), "source identities must be stable")
        let twentySeven = try XCTUnwrap(result.candidates.last)
        XCTAssertEqual(twentySeven.definition.channels.map(\.offset), Array(1...27).map(UInt16.init))
        XCTAssertTrue(twentySeven.definition.channels.contains { !$0.dmxFunctions.isEmpty })
    }

    func testImportsLocalFixtureCorpusWhenAvailable() throws {
        let folder = URL(fileURLWithPath: "/Users/dakota/code/LightKey Fixtures", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension.lowercased() == "lightkeyfxt" }), !urls.isEmpty else {
            throw XCTSkip("Local LightKey fixture corpus is not installed")
        }

        for url in urls {
            let result = try LightKeyFixtureImporter.inspect(url: url)
            XCTAssertFalse(result.candidates.isEmpty, url.lastPathComponent)
            XCTAssertTrue(result.candidates.allSatisfy { !$0.definition.channels.isEmpty }, url.lastPathComponent)
        }
    }

    func testRejectsOrdinaryData() {
        XCTAssertThrowsError(try LightKeyFixtureImporter.inspect(data: Data("not a plist".utf8)))
    }
}
