import AuroraModel
import Foundation
import XCTest

final class CueBlockModelTests: XCTestCase {
    func testCueBlockGroupAndMembershipRoundTrip() throws {
        let source = UUID()
        let group = CueBlockGroup(
            name: "Dance Floor",
            sourceFixtureGroupID: source,
            sectionNames: [.intensity: "Brightness", .general: "Atmosphere"]
        )
        let block = CueBlock(name: "Blue", type: .color, cueBlockGroupID: group.id, sourceGroupID: source)
        var project = ShowProject.empty(name: "Grouped")
        project.cueBlockGroups = [group]
        project.cueBlocks = [block]

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ShowProject.self, from: encoded)
        XCTAssertEqual(decoded.cueBlockGroups, [group])
        XCTAssertEqual(decoded.cueBlocks.first?.cueBlockGroupID, group.id)
    }

    func testCueBlockGroupWithoutSectionNamesDecodesWithDefaults() throws {
        let json = """
        {
          "id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
          "name": "Legacy Group",
          "notes": ""
        }
        """
        let group = try JSONDecoder().decode(CueBlockGroup.self, from: Data(json.utf8))
        XCTAssertTrue(group.sectionNames.isEmpty)
    }

    func testValidatorReportsMissingCueBlockGroup() {
        var project = ShowProject.empty(name: "Missing Group")
        project.cueBlocks = [CueBlock(name: "Blue", type: .color, cueBlockGroupID: UUID())]
        let issues = ProjectValidator.validate(project).issues
        XCTAssertTrue(issues.contains { $0.message.contains("references missing Cue Block Group") })
    }

    func testAttributeFamilyClassification() {
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "intensity"), .intensity)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "dimmer"), .intensity)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "dim"), .intensity)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "colorHue"), .color)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "colorR"), .color)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "pan"), .position)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "zoom"), .beam)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "strobe"), .beam)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "gobo"), .gobo)
        XCTAssertEqual(CueBlockAttributeFamily.family(for: "goboRotate"), .gobo)
        XCTAssertNil(CueBlockAttributeFamily.family(for: "customUnknown"))
        XCTAssertTrue(CueBlockAttributeFamily.isAllowed("customUnknown", for: .general))
        XCTAssertFalse(CueBlockAttributeFamily.isAllowed("intensity", for: .color))
        XCTAssertTrue(CueBlockAttributeFamily.isAllowed("colorHue", for: .color))
    }

    func testCueBlockCodableRoundTrip() throws {
        let fxA = UUID()
        let fxB = UUID()
        let paletteID = UUID()
        let groupID = UUID()
        let block = CueBlock(
            id: UUID(),
            name: "Blue Fan",
            type: .color,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fxA, attributes: ["colorHue": 0.7], paletteRefs: ["color": paletteID]),
                FixtureCueLevels(fixtureId: fxB, attributes: ["colorHue": 0.6]),
            ]),
            sourceGroupID: groupID,
            notes: "dance floor"
        )
        let data = try ProjectPackage.makeEncoder().encode(block)
        let decoded = try ProjectPackage.makeDecoder().decode(CueBlock.self, from: data)
        XCTAssertEqual(decoded, block)
        XCTAssertEqual(decoded.levels.fixtures.map(\.fixtureId), [fxA, fxB])
    }

    func testCueWithoutCueBlockRefsDecodesEmpty() throws {
        // Golden schema-4-era cue JSON (no cueBlockRefs key).
        let json = """
        {
          "id": "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
          "number": 1.5,
          "name": "House",
          "fadeIn": 2.5,
          "fadeOut": 1,
          "delay": 0.25,
          "follow": "afterTime",
          "followTime": 3,
          "tracking": "cueOnly",
          "levels": {
            "fixtures": [
              {
                "fixtureId": "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
                "attributes": { "intensity": 0.5 },
                "paletteRefs": { "color": "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC" }
              }
            ]
          },
          "loop": { "count": 2, "infinite": false }
        }
        """
        let cue = try ProjectPackage.makeDecoder().decode(Cue.self, from: Data(json.utf8))
        XCTAssertTrue(cue.cueBlockRefs.isEmpty)
        XCTAssertEqual(cue.name, "House")
        XCTAssertEqual(cue.fadeIn, 2.5)
        XCTAssertEqual(cue.fadeOut, 1)
        XCTAssertEqual(cue.delay, 0.25)
        XCTAssertEqual(cue.follow, .afterTime)
        XCTAssertEqual(cue.followTime, 3)
        XCTAssertEqual(cue.tracking, .cueOnly)
        XCTAssertEqual(cue.loop?.count, 2)
        XCTAssertEqual(cue.levels.fixtures.count, 1)
        XCTAssertEqual(cue.levels.fixtures[0].attributes["intensity"], 0.5)
        XCTAssertEqual(
            cue.levels.fixtures[0].paletteRefs["color"],
            UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")
        )
    }

    func testCueFullRoundTripPreservesRefsOrderAndEnabled() throws {
        let ref1 = CueBlockReference(id: UUID(), cueBlockID: UUID(), enabled: true)
        let ref2 = CueBlockReference(id: UUID(), cueBlockID: UUID(), enabled: false)
        let cue = Cue(
            number: 2,
            name: "Compose",
            fadeIn: 1,
            tracking: .track,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: UUID(), attributes: ["intensity": 0.75])
            ]),
            loop: .infiniteLoop,
            cueBlockRefs: [ref1, ref2]
        )
        let data = try ProjectPackage.makeEncoder().encode(cue)
        let decoded = try ProjectPackage.makeDecoder().decode(Cue.self, from: data)
        XCTAssertEqual(decoded, cue)
        XCTAssertEqual(decoded.cueBlockRefs.map(\.id), [ref1.id, ref2.id])
        XCTAssertEqual(decoded.cueBlockRefs.map(\.enabled), [true, false])
    }

    func testRecorderNoSelectionIsError() {
        let result = CueBlockRecorder.record(CueBlockRecorder.Request(
            name: "X",
            type: .color,
            programmerValues: [:],
            selectedFixtureIDs: [],
            capabilityMap: [:]
        ))
        XCTAssertNil(result.cueBlock)
        XCTAssertTrue(result.issues.contains { $0.code == "no-selection" && $0.severity == .error })
    }

    func testRecorderColorExcludesIntensityAndPreservesFanOrder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let caps: [UUID: Set<String>] = [
            a: ["colorR", "colorG", "colorB", "intensity"],
            b: ["colorR", "colorG", "colorB", "intensity"],
            c: ["colorR", "colorG", "colorB", "intensity"],
            d: ["colorR", "colorG", "colorB", "intensity"],
        ]
        let values: [UUID: [String: Double]] = [
            a: ["colorHue": 0.78, "intensity": 1],
            b: ["colorHue": 0.72, "intensity": 1],
            c: ["colorHue": 0.66, "intensity": 1],
            d: ["colorHue": 0.60, "intensity": 1],
        ]
        let result = CueBlockRecorder.record(CueBlockRecorder.Request(
            name: "Blue Fan",
            type: .color,
            programmerValues: values,
            selectedFixtureIDs: [a, b, c, d],
            capabilityMap: caps
        ))
        XCTAssertNotNil(result.cueBlock)
        let fixtures = result.cueBlock!.levels.fixtures
        XCTAssertEqual(fixtures.map(\.fixtureId), [a, b, c, d])
        XCTAssertEqual(fixtures.map { $0.attributes["colorHue"] }, [0.78, 0.72, 0.66, 0.60])
        for fx in fixtures {
            XCTAssertNil(fx.attributes["intensity"])
        }
        XCTAssertTrue(result.issues.contains { $0.code == "attribute-family-skipped" && $0.severity == .warning })
    }

    func testRecorderIntensityExcludesColor() {
        let fx = UUID()
        let result = CueBlockRecorder.record(CueBlockRecorder.Request(
            name: "75%",
            type: .intensity,
            programmerValues: [fx: ["intensity": 0.75, "colorR": 1]],
            selectedFixtureIDs: [fx],
            capabilityMap: [fx: ["intensity", "colorR", "colorG", "colorB"]]
        ))
        XCTAssertEqual(result.cueBlock?.levels.fixtures.first?.attributes["intensity"], 0.75)
        XCTAssertNil(result.cueBlock?.levels.fixtures.first?.attributes["colorR"])
    }

    func testRecorderOnlySelectedFixtures() {
        let a = UUID()
        let b = UUID()
        let result = CueBlockRecorder.record(CueBlockRecorder.Request(
            name: "A only",
            type: .intensity,
            programmerValues: [
                a: ["intensity": 0.5],
                b: ["intensity": 1.0],
            ],
            selectedFixtureIDs: [a],
            capabilityMap: [a: ["intensity"], b: ["intensity"]]
        ))
        XCTAssertEqual(result.cueBlock?.levels.fixtures.count, 1)
        XCTAssertEqual(result.cueBlock?.levels.fixtures.first?.fixtureId, a)
    }

    func testRecorderUpdatePreservesID() {
        let id = UUID()
        let fx = UUID()
        let result = CueBlockRecorder.record(CueBlockRecorder.Request(
            name: "Updated",
            type: .intensity,
            programmerValues: [fx: ["intensity": 0.4]],
            selectedFixtureIDs: [fx],
            existingID: id,
            capabilityMap: [fx: ["intensity"]]
        ))
        XCTAssertEqual(result.cueBlock?.id, id)
        XCTAssertEqual(result.cueBlock?.name, "Updated")
    }

    func testRecorderAllEmptyIsError() {
        let fx = UUID()
        let result = CueBlockRecorder.record(CueBlockRecorder.Request(
            name: "Empty",
            type: .color,
            programmerValues: [fx: ["intensity": 1]],
            selectedFixtureIDs: [fx],
            capabilityMap: [fx: ["intensity"]]
        ))
        XCTAssertNil(result.cueBlock)
        XCTAssertTrue(result.issues.contains { $0.code == "no-matching-values" && $0.severity == .error })
    }

    func testPackageRoundTripIncludesCueBlocks() throws {
        var project = ShowProject.empty(name: "Blocks")
        let fx = UUID()
        let def = FixtureDefinition(
            id: UUID(),
            manufacturer: "G",
            model: "RGB",
            channelCount: 3,
            channels: [
                ChannelDef(offset: 1, name: "R", attribute: "colorR"),
                ChannelDef(offset: 2, name: "G", attribute: "colorG"),
                ChannelDef(offset: 3, name: "B", attribute: "colorB"),
            ]
        )
        project.fixtureDefinitions = [def]
        project.universes = [Universe(id: UUID(), number: 1, name: "U1")]
        project.fixtures = [
            PatchedFixture(
                id: fx,
                name: "F1",
                definitionId: def.id,
                universeId: project.universes[0].id,
                address: 1
            )
        ]
        let blockGroup = CueBlockGroup(name: "Dance Floor")
        let block = CueBlock(
            name: "Blue",
            type: .color,
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: fx, attributes: ["colorR": 0, "colorG": 0, "colorB": 1])
            ]),
            cueBlockGroupID: blockGroup.id
        )
        project.cueBlockGroups = [blockGroup]
        project.cueBlocks = [block]
        let listID = UUID()
        let cue = Cue(
            number: 1,
            name: "Dance Floor Blue",
            cueBlockRefs: [CueBlockReference(cueBlockID: block.id, enabled: true)]
        )
        project.cueLists = [CueList(id: listID, name: "Main", cues: [cue])]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cueblocks-\(UUID().uuidString).prism", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProjectPackage.save(project, to: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cue-blocks.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cue-block-groups.json").path))

        let loaded = try ProjectPackage.load(from: dir)
        XCTAssertEqual(loaded.schemaVersion, 5)
        XCTAssertEqual(loaded.cueBlocks.count, 1)
        XCTAssertEqual(loaded.cueBlockGroups, [blockGroup])
        XCTAssertEqual(loaded.cueBlocks[0].id, block.id)
        XCTAssertEqual(loaded.cueBlocks[0].cueBlockGroupID, blockGroup.id)
        XCTAssertEqual(loaded.cueLists[0].cues[0].cueBlockRefs.first?.cueBlockID, block.id)
    }

    func testMissingCueBlocksOnV5Fails() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-cb-\(UUID().uuidString).prism", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProjectPackage.save(ShowProject.empty(name: "X"), to: dir)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("cue-blocks.json"))
        XCTAssertThrowsError(try ProjectPackage.load(from: dir)) { error in
            guard case ProjectPackageError.missingFile(let name) = error else {
                return XCTFail("Expected missingFile, got \(error)")
            }
            XCTAssertEqual(name, "cue-blocks.json")
        }
    }

    func testOlderPackageWithoutCueBlocksLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-cb-\(UUID().uuidString).prism", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProjectPackage.save(ShowProject.empty(name: "Legacy"), to: dir)
        // Simulate schema 4 package: rewrite version and drop cue-blocks.json
        let projectJSON = dir.appendingPathComponent("project.json")
        var text = try String(contentsOf: projectJSON, encoding: .utf8)
        if let range = text.range(of: #"\"schemaVersion\"\s*:\s*\d+"#, options: .regularExpression) {
            text.replaceSubrange(range, with: "\"schemaVersion\" : 4")
        }
        try Data(text.utf8).write(to: projectJSON)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("cue-blocks.json"))

        let loaded = try ProjectPackage.load(from: dir)
        XCTAssertEqual(loaded.schemaVersion, ProjectPackage.currentSchemaVersion)
        XCTAssertTrue(loaded.cueBlocks.isEmpty)
    }

    func testValidatorAndQueries() {
        let blockID = UUID()
        let missingBlock = UUID()
        let fxMissing = UUID()
        let paletteMissing = UUID()
        let groupMissing = UUID()
        var project = ShowProject.empty(name: "V")
        project.cueBlocks = [
            CueBlock(
                id: blockID,
                name: "Empty",
                type: .color,
                levels: .empty,
                sourceGroupID: groupMissing
            ),
            CueBlock(
                id: UUID(),
                name: "Bad",
                type: .color,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(
                        fixtureId: fxMissing,
                        attributes: ["intensity": 1],
                        paletteRefs: ["color": paletteMissing]
                    )
                ])
            ),
        ]
        let listID = UUID()
        let cueID = UUID()
        let refID = UUID()
        project.cueLists = [
            CueList(
                id: listID,
                name: "Main",
                cues: [
                    Cue(
                        id: cueID,
                        number: 1,
                        name: "Q",
                        cueBlockRefs: [
                            CueBlockReference(id: refID, cueBlockID: blockID, enabled: true),
                            CueBlockReference(id: UUID(), cueBlockID: missingBlock, enabled: false),
                            CueBlockReference(id: UUID(), cueBlockID: blockID, enabled: true),
                        ]
                    )
                ]
            )
        ]

        let snap = ProjectValidator.validate(project)
        let codes = Set(snap.issues.map(\.message))
        XCTAssertTrue(snap.issues.contains { $0.message.contains("empty") || $0.message.contains("Empty") })
        XCTAssertTrue(snap.issues.contains { $0.message.contains("missing Cue Block") })
        XCTAssertTrue(snap.issues.contains { $0.message.contains("more than once") })
        XCTAssertTrue(snap.issues.contains { $0.message.contains("source group") })
        XCTAssertTrue(snap.issues.contains { $0.message.contains("missing fixture") })
        XCTAssertTrue(snap.issues.contains { $0.message.contains("missing palette") || $0.message.contains("Missing palette") })
        _ = codes

        XCTAssertEqual(project.cueBlockReferenceCount(blockID), 2)
        let sites = project.cueBlockReferenceSites(blockID)
        XCTAssertEqual(sites.count, 2)
        XCTAssertEqual(sites[0].cueListName, "Main")
        XCTAssertEqual(sites[0].referenceID, refID)
    }

    func testPaletteDependencyIncludesCueBlocks() {
        let paletteID = UUID()
        var project = ShowProject.empty(name: "P")
        project.palettes = [Palette(id: paletteID, name: "Blue", type: .color, values: ["colorB": 1])]
        project.cueBlocks = [
            CueBlock(
                name: "Uses palette",
                type: .color,
                levels: CueLevelData(fixtures: [
                    FixtureCueLevels(fixtureId: UUID(), paletteRefs: ["color": paletteID])
                ])
            )
        ]
        XCTAssertEqual(project.paletteReferenceCount(paletteID), 1)
        XCTAssertTrue(project.paletteReferenceCueSummaries(paletteID).contains { $0.contains("Cue Block") })
    }
}
