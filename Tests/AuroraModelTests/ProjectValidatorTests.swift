import AuroraModel
import XCTest

final class ProjectValidatorTests: XCTestCase {
    func testMissingDefinitionAndStableIDs() {
        var project = ShowProject.empty(name: "V")
        let u = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: UUID(), universeId: u, address: 1)
        ]
        let a = ProjectValidator.validate(project)
        let b = ProjectValidator.validate(project)
        XCTAssertFalse(a.issues.isEmpty)
        XCTAssertEqual(a.issues.map(\.id), b.issues.map(\.id))
        XCTAssertTrue(a.issues.contains { $0.message.contains("missing definition") })
    }

    func testMissingPaletteRef() {
        var project = ShowProject.empty()
        let missing = UUID()
        let cue = Cue(
            number: 1,
            name: "C",
            levels: CueLevelData(fixtures: [
                FixtureCueLevels(fixtureId: UUID(), paletteRefs: ["color": missing])
            ])
        )
        project.cueLists = [CueList(name: "M", cues: [cue])]
        let issues = ProjectValidator.validate(project).issues
        XCTAssertTrue(issues.contains { $0.paletteID == missing })
    }

    func testGroupDivergenceDetected() {
        var project = ShowProject.empty()
        let f = UUID()
        let g = UUID()
        let u = UUID()
        let d = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(id: d, manufacturer: "G", model: "D", channels: [
                ChannelDef(offset: 1, name: "I", attribute: "intensity")
            ])
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1, groupIds: [g])
        ]
        project.groups = [Group(id: g, name: "G", fixtureIds: [])]
        let issues = ProjectValidator.validate(project).issues
        XCTAssertTrue(issues.contains { $0.message.contains("diverge") })
    }

    /// PRE-UI-1: duplicate universe numbers are integrity errors.
    func testDuplicateUniverseNumberDetected() {
        var project = ShowProject.empty()
        project.universes = [
            Universe(id: UUID(), number: 1, name: "A"),
            Universe(id: UUID(), number: 1, name: "B"),
        ]
        let issues = ProjectValidator.validate(project).issues
        XCTAssertTrue(issues.contains { $0.message.contains("Duplicate universe number") })
    }

    func testDuplicateCueIDsAcrossListsDetected() {
        var project = ShowProject.empty()
        let cueID = UUID()
        project.cueLists = [
            CueList(name: "A", cues: [Cue(id: cueID, number: 1, name: "1")]),
            CueList(name: "B", cues: [Cue(id: cueID, number: 1, name: "dup")]),
        ]
        let issues = ProjectValidator.validate(project).issues
        XCTAssertTrue(issues.contains { $0.message.contains("Duplicate cue") })
    }

    func testDuplicateEffectOrderDetected() {
        var project = ShowProject.empty()
        project.effects = [
            EffectDefinition(name: "E1", order: 1),
            EffectDefinition(name: "E2", order: 1),
        ]
        let issues = ProjectValidator.validate(project).issues
        XCTAssertTrue(issues.contains { $0.message.contains("Duplicate effect order") })
    }
}
