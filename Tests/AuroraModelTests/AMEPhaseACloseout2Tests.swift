import AuroraModel
import XCTest

/// Second Phase A closeout: meter persistence, validator robustness, compound decode.
final class AMEPhaseACloseout2Tests: XCTestCase {
    func testSongMeterGroupingRoundTrip() throws {
        var project = ShowProject.empty()
        let meter223 = try ShowMusicalMeter(numerator: 7, denominator: 8, beatGrouping: [2, 2, 3])
        let meter322 = try ShowMusicalMeter(numerator: 7, denominator: 8, beatGrouping: [3, 2, 2])
        project.songs = [
            Song(title: "A", defaultMeter: meter223),
            Song(title: "B", defaultMeter: meter322),
        ]
        project.ame.musicalSettings.defaultMeter = .sixEight
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meter-\(UUID().uuidString).aurora", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProjectPackage.save(project, to: dir)
        let loaded = try ProjectPackage.load(from: dir)
        XCTAssertEqual(loaded.songs[0].defaultMeter?.beatGrouping, [2, 2, 3])
        XCTAssertEqual(loaded.songs[1].defaultMeter?.beatGrouping, [3, 2, 2])
        XCTAssertEqual(loaded.ame.musicalSettings.defaultMeter.beatGrouping, [3, 3])
        XCTAssertNotEqual(loaded.songs[0].defaultMeter, loaded.songs[1].defaultMeter)
    }

    func testLegacyNumDenMigration() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"L","artist":"","notes":"","entries":[],"annotations":[],"defaultMeterNumerator":6,"defaultMeterDenominator":8}
        """
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        XCTAssertEqual(song.defaultMeter?.beatGrouping, [3, 3])
    }

    func testDuplicateMappingIDsDoNotTrap() {
        var project = ShowProject.empty()
        let id = UUID()
        let t = UUID()
        project.ame.triggers = [AMETriggerDefinition(id: t, name: "T")]
        project.ame.mappings = [
            AMEMapping(id: id, name: "A", triggerID: t, actions: [.go]),
            AMEMapping(id: id, name: "B", triggerID: t, actions: [.stop]),
        ]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "duplicate_mapping_id" })
    }

    func testIllegalCrossSongOverride() {
        var project = ShowProject.empty()
        let songA = UUID()
        let songB = UUID()
        let secA = UUID()
        project.songs = [
            Song(id: songA, title: "A", sections: [SongSection(id: secA, name: "Intro")]),
            Song(id: songB, title: "B", sections: [SongSection(name: "V")]),
        ]
        let parentID = UUID()
        let childID = UUID()
        let t = UUID()
        project.ame.triggers = [AMETriggerDefinition(id: t, name: "T")]
        project.ame.mappings = [
            AMEMapping(id: parentID, name: "Parent", scope: .song(songB), triggerID: t, actions: [.go]),
            AMEMapping(
                id: childID,
                name: "Child",
                scope: .section(secA),
                triggerID: t,
                actions: [.stop],
                overrideParentID: parentID
            ),
        ]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "illegal_override_scope" })
    }

    func testExclusiveSectionsNotFalselyAmbiguous() {
        var project = ShowProject.empty()
        let song = UUID()
        let sec1 = UUID()
        let sec2 = UUID()
        project.songs = [
            Song(id: song, title: "S", sections: [
                SongSection(id: sec1, name: "A"),
                SongSection(id: sec2, name: "B"),
            ]),
        ]
        let parent = UUID()
        let t = UUID()
        project.ame.triggers = [AMETriggerDefinition(id: t, name: "T")]
        project.ame.mappings = [
            AMEMapping(id: parent, name: "P", priority: 1, scope: .song(song), triggerID: t, actions: [.go]),
            AMEMapping(id: UUID(), name: "C1", priority: 5, scope: .section(sec1), triggerID: t, actions: [.stop], overrideParentID: parent),
            AMEMapping(id: UUID(), name: "C2", priority: 5, scope: .section(sec2), triggerID: t, actions: [.back], overrideParentID: parent),
        ]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertFalse(issues.contains { $0.code == "ambiguous_override" })
    }

    func testMIDIData128Rejected() {
        var project = ShowProject.empty()
        project.ame.triggers = [
            AMETriggerDefinition(name: "Bad", data1Min: 128),
        ]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "invalid_midi_data" })
    }

    func testNegativeDebounceRejected() {
        var project = ShowProject.empty()
        let t = UUID()
        project.ame.triggers = [AMETriggerDefinition(id: t, name: "T")]
        project.ame.mappings = [
            AMEMapping(name: "M", triggerID: t, actions: [.go], debounceMilliseconds: -1),
        ]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "invalid_debounce" })
    }

    func testInvalidBPMRejected() {
        var project = ShowProject.empty()
        project.ame.musicalSettings.defaultTempoBPM = 5
        project.songs = [Song(title: "S", defaultTempoBPM: 999)]
        let issues = AMEConfigurationValidator.validate(project: project)
        XCTAssertTrue(issues.contains { $0.code == "invalid_bpm" })
        XCTAssertTrue(issues.contains { $0.code == "invalid_song_bpm" })
    }

    func testTaggedCompoundMissingActionsFails() {
        let json = #"{"type":"compound"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(AuroraAction.self, from: Data(json.utf8)))
    }

    func testTaggedEmptyCompoundOK() throws {
        let action = AuroraAction.compound([])
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(AuroraAction.self, from: data)
        XCTAssertEqual(decoded, .compound([]))
    }

    func testLegacyCompoundReturnsNil() {
        XCTAssertNil(AuroraAction.fromLegacy(storageKey: "compound", parameter: "3"))
    }
}
