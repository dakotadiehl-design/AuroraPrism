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
        XCTAssertEqual(twentySeven.definition.elements.count, 4)
        XCTAssertEqual(twentySeven.definition.elements.map(\.name), ["Element 1", "Element 2", "Element 3", "Element 4"])
        XCTAssertEqual(Set(twentySeven.definition.channels.compactMap(\.elementID)).count, 4)
        XCTAssertEqual(twentySeven.definition.resolvedVisualization().form, .linearBar)
        XCTAssertEqual(twentySeven.definition.portablePhysicalDefinition?.source, .imported)
        XCTAssertEqual(Set(result.candidates.compactMap(\.definition.physicalFixtureID)).count, 1)
        XCTAssertTrue(result.candidates.allSatisfy {
            $0.definition.resolvedVisualization().physicalTopologySignature
                == twentySeven.definition.resolvedVisualization().physicalTopologySignature
        })
        XCTAssertEqual(twentySeven.definition.calculatedFootprint, 27)
        XCTAssertTrue(twentySeven.definition.channels.contains { !$0.dmxFunctions.isEmpty })
    }

    func testCOLORbandImportsTwelvePhysicalEmittersAndThreeGroupsOfFour() throws {
        let url = URL(fileURLWithPath: "/Users/dakota/code/LightKey Fixtures/Chauvet - COLORband Q3BT ILS.lightkeyfxt")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Attached COLORband LightKey fixture is not installed")
        }

        let result = try LightKeyFixtureImporter.inspect(url: url)
        XCTAssertEqual(result.model, "COLORband Q3BT ILS")
        XCTAssertEqual(result.candidates.map(\.definition.channelCount), [4, 6, 16])
        XCTAssertTrue(result.candidates.allSatisfy {
            $0.definition.portablePhysicalDefinition?.emitters.count == 12
        })

        let extended = try XCTUnwrap(result.candidates.first { $0.definition.channelCount == 16 })
        XCTAssertEqual(extended.definition.controlElements.count, 3)
        XCTAssertEqual(extended.definition.emitterMappings.count, 3)
        XCTAssertEqual(extended.definition.emitterMappings.map(\.controlElementIDs), [
            ["element-0"], ["element-1"], ["element-2"],
        ])
        XCTAssertEqual(
            extended.definition.channels.prefix(12).compactMap(\.elementID),
            Array(repeating: "element-0", count: 4)
                + Array(repeating: "element-1", count: 4)
                + Array(repeating: "element-2", count: 4)
        )
        let mappedIndexes = extended.definition.emitterMappings.map { mapping in
            mapping.physicalEmitterIDs.compactMap { id in
                Int(id.replacingOccurrences(of: "physical-emitter-", with: ""))
            }.sorted()
        }
        XCTAssertEqual(mappedIndexes, [Array(0...3), Array(4...7), Array(8...11)])
        XCTAssertTrue(extended.channelSources.prefix(12).allSatisfy { $0.beamIndexes.count == 4 })

        for basic in result.candidates.filter({ $0.definition.channelCount != 16 }) {
            XCTAssertEqual(basic.definition.emitterMappings.count, 1)
            XCTAssertEqual(basic.definition.emitterMappings.first?.physicalEmitterIDs.count, 12)
        }
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

    func testBatchImportRecursesAndKeepsPartialFailures() throws {
        let corpus = URL(fileURLWithPath: "/Users/dakota/code/LightKey Fixtures", isDirectory: true)
        let sourceFiles = try FileManager.default.contentsOfDirectory(
            at: corpus,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "lightkeyfxt" }
        guard sourceFiles.count >= 2 else {
            throw XCTSkip("Local LightKey fixture corpus is not installed")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Prism-LightKey-Batch-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: sourceFiles[0], to: root.appendingPathComponent(sourceFiles[0].lastPathComponent))
        try FileManager.default.copyItem(at: sourceFiles[1], to: nested.appendingPathComponent(sourceFiles[1].lastPathComponent))
        try Data("invalid fixture".utf8).write(to: nested.appendingPathComponent("Broken.lightkeyfxt"))
        try Data("ignored".utf8).write(to: root.appendingPathComponent("Not-A-Fixture.txt"))

        let batch = try LightKeyFixtureImporter.inspectRecursively(sourceURL: root)
        XCTAssertEqual(batch.fixtures.count, 2)
        XCTAssertEqual(batch.failures.count, 1)
        XCTAssertEqual(batch.failures.first?.sourceURL.lastPathComponent, "Broken.lightkeyfxt")
        XCTAssertFalse(batch.fixtures.flatMap(\.candidates).isEmpty)
    }

    func testFixtureTestCorpusTranslatesSupportedSemanticsWithoutFalseWarnings() throws {
        let folder = URL(
            fileURLWithPath: "/Users/dakota/code/LightKey Fixtures/Fixture Tests",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw XCTSkip("Local LightKey fixture test corpus is not installed")
        }

        let batch = try LightKeyFixtureImporter.inspectRecursively(sourceURL: folder)
        XCTAssertFalse(batch.fixtures.isEmpty)
        XCTAssertTrue(batch.failures.isEmpty)
        let candidates = batch.fixtures.flatMap(\.candidates)
        let issues = candidates.flatMap(\.issues)

        let conditionIssues = issues.filter { $0.code == .conditionalCapability }
        XCTAssertLessThan(
            conditionIssues.count,
            100,
            "UID-zero $null conditions must not create corpus-wide false positives: \(conditionIssues.prefix(5).map(\.message))"
        )
        XCTAssertFalse(issues.contains { $0.code == .unknownColorEmitter }, "Fine color emitters should pair with coarse emitters")
        XCTAssertFalse(issues.contains { $0.code == .unsupportedBeamLayout }, "Known LightKey layouts should translate to Prism physical geometry")
        XCTAssertFalse(issues.contains { $0.code == .unsafeCommand }, "Imported command ranges should be protected structurally")
        XCTAssertFalse(issues.contains { $0.code == .unknownCapability }, "Corpus-standard capability classes should have native mappings")

        let channels = candidates.flatMap { $0.definition.channels }
        XCTAssertTrue(channels.contains { $0.resolution == .fine && $0.attribute == "colorR" })
        XCTAssertTrue(channels.contains { $0.resolution == .fine && $0.attribute == "colorG" })
        XCTAssertTrue(channels.contains { $0.resolution == .fine && $0.attribute == "colorB" })
        XCTAssertTrue(channels.flatMap(\.dmxFunctions).contains { $0.isProtected && $0.requiresConfirmation })
        XCTAssertTrue(candidates.contains { !($0.definition.portablePhysicalDefinition?.emitters.isEmpty ?? true) })
    }

    func testRejectsOrdinaryData() {
        XCTAssertThrowsError(try LightKeyFixtureImporter.inspect(data: Data("not a plist".utf8)))
    }
}
