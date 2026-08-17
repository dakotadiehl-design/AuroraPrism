import AuroraModel
import XCTest

final class AMEPhaseAModelTests: XCTestCase {
    func testSongDecodeWithoutSectionsGetsMain() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"Legacy","artist":"","notes":"","entries":[],"annotations":[]}
        """
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        XCTAssertEqual(song.sections.count, 1)
        XCTAssertEqual(song.sections[0].name, "Main")
    }

    func testSectionMigrationHelperProposesButDoesNotApply() {
        let entries = [
            SongEntry(target: .cueList(UUID()), label: "Intro"),
            SongEntry(target: .cueList(UUID()), label: "Chorus"),
        ]
        let proposed = SongSectionMigrationHelper.proposeSections(from: entries)
        XCTAssertEqual(proposed.map(\.name), ["Intro", "Chorus"])
        var song = Song(title: "T", entries: entries, sections: [])
        XCTAssertEqual(song.sections[0].name, "Main")
        song.sections = []
        SongSectionMigrationHelper.ensureDefaultMainSection(&song)
        XCTAssertEqual(song.sections[0].name, "Main")
    }

    func testLegacyOwnershipClaimSuppressesOnlyClaimedIDs() {
        let legacyID = UUID()
        let otherID = UUID()
        var doc = AMEProjectDocument.empty
        doc.mappings = [AMEMapping(name: "Migrated", claimsLegacyMappingID: legacyID)]
        XCTAssertFalse(AMELegacyOwnership.shouldRunLegacyMapping(id: legacyID, document: doc))
        XCTAssertTrue(AMELegacyOwnership.shouldRunLegacyMapping(id: otherID, document: doc))
    }

    func testAuroraActionSafetyRecursive() {
        XCTAssertTrue(AuroraAction.panic.isSafetyCritical)
        XCTAssertTrue(AuroraAction.compound([.go, .panic]).isSafetyCritical)
        XCTAssertTrue(AuroraAction.compound([.compound([.blackout])]).isSafetyCritical)
        XCTAssertFalse(AuroraAction.compound([.go, .fireCue(UUID())]).isSafetyCritical)
        XCTAssertFalse(AuroraAction.tapTempo.isSafetyCritical)
    }

    func testAuroraActionCompoundRoundTripLossless() throws {
        let nested = AuroraAction.compound([
            .go,
            .fireCue(UUID(uuidString: "00000000-0000-4000-8000-000000000099")!),
            .compound([.panic, .toggleBlackout]),
        ])
        let data = try JSONEncoder().encode(nested)
        let decoded = try JSONDecoder().decode(AuroraAction.self, from: data)
        XCTAssertEqual(decoded, nested)
        XCTAssertTrue(decoded.isSafetyCritical)
    }

    func testEverySimpleActionRoundTrip() throws {
        let samples: [AuroraAction] = [
            .go, .stop, .back, .panic, .tapTempo,
            .fireCue(UUID()), .fireCueIndex(3),
            .programmerAttribute("intensity"),
            .setTempoBPM(118.5),
            .enterSection(UUID()),
        ]
        for action in samples {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(AuroraAction.self, from: data)
            XCTAssertEqual(decoded, action, "failed for \(action.storageKey)")
        }
    }

    func testValidatorFlagsEmptySequenceAndSafetyQuantize() {
        var project = ShowProject.empty()
        let seqID = UUID()
        project.ame.sequences = [AMETriggeredSequence(id: seqID, name: "Empty")]
        project.ame.mappings = [
            AMEMapping(
                name: "Bad",
                triggerID: UUID(),
                actions: [.compound([.panic])],
                quantizeBoundary: .nextBar
            ),
        ]
        // Also add trigger so missing_when not only issue
        let tid = project.ame.mappings[0].triggerID!
        project.ame.triggers = [AMETriggerDefinition(id: tid, name: "T")]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "empty_sequence" })
        XCTAssertTrue(issues.contains { $0.code == "safety_quantized" })
    }

    func testValidatorDuplicateLegacyClaims() {
        var project = ShowProject.empty()
        let legacy = UUID()
        let t1 = UUID()
        let t2 = UUID()
        project.ame.triggers = [
            AMETriggerDefinition(id: t1, name: "a"),
            AMETriggerDefinition(id: t2, name: "b"),
        ]
        project.ame.mappings = [
            AMEMapping(name: "A", triggerID: t1, claimsLegacyMappingID: legacy),
            AMEMapping(name: "B", triggerID: t2, claimsLegacyMappingID: legacy),
        ]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "duplicate_legacy_mapping_claim" })
    }

    func testPackageRoundTripIncludesAME() throws {
        var project = ShowProject.sample()
        project.ame.triggers = [
            AMETriggerDefinition(name: "Snare", friendlyName: "Snare", messageType: .noteOn, data1Min: 38, data1Max: 38),
        ]
        project.ame.mappings = [
            AMEMapping(
                name: "Snare GO",
                triggerID: project.ame.triggers[0].id,
                actions: [.go, .compound([.fireCueIndex(1)])]
            ),
        ]
        project.ame.musicalSettings.defaultTempoBPM = 118
        project.ame.musicalSettings.defaultMeter = .sixEight
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ame-closeout-\(UUID().uuidString).aurora", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProjectPackage.save(project, to: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ame.json").path))
        let loaded = try ProjectPackage.load(from: dir)
        XCTAssertEqual(loaded.schemaVersion, ProjectPackage.currentSchemaVersion)
        XCTAssertEqual(loaded.ame.triggers.count, 1)
        XCTAssertEqual(loaded.ame.mappings[0].actions.count, 2)
        if case .compound(let inner) = loaded.ame.mappings[0].actions[1] {
            XCTAssertEqual(inner.count, 1)
        } else {
            XCTFail("expected compound preserved")
        }
        XCTAssertEqual(loaded.ame.musicalSettings.defaultTempoBPM, 118)
        XCTAssertEqual(loaded.ame.musicalSettings.defaultMeter.beatGrouping, [3, 3])
        XCTAssertEqual(loaded.songs[0].sections.first?.name, "Main")
    }

    func testSchemaV3MigratesToV4WithMainSection() throws {
        var project = ShowProject.sample()
        project.schemaVersion = 3
        project.songs[0].sections = []
        let migrated = try SchemaMigration.migrate(project)
        XCTAssertEqual(migrated.schemaVersion, 4)
        XCTAssertEqual(migrated.songs[0].sections.first?.name, "Main")
    }

    func testTypedSectionLifecycleActionsRoundTrip() throws {
        var project = ShowProject.empty()
        let section = SongSection(
            name: "Intro",
            onEnterActions: [.go, .compound([.panic])],
            onExitActions: [.stop]
        )
        project.songs = [Song(title: "S", sections: [section])]
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-\(UUID().uuidString).aurora", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProjectPackage.save(project, to: dir)
        let loaded = try ProjectPackage.load(from: dir)
        XCTAssertEqual(loaded.songs[0].sections[0].onEnterActions.count, 2)
        XCTAssertTrue(loaded.songs[0].sections[0].onEnterActions[1].isSafetyCritical)
    }
}
