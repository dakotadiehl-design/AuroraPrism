import AuroraEngine
import AuroraModel
import AuroraOutput
import XCTest

/// Stage C: PerformanceSnapshot.build is pure enough to test without the app target.
/// (App-target PerformanceSnapshot lives in Aurora; we mirror the critical contract here
/// via engine snapshot + song fields used by remote/perform UI.)
final class PerformanceSnapshotBuildTests: XCTestCase {
    func testEngineSnapshotCarriesCachedValidationCount() {
        var project = ShowProject.empty(name: "Perf")
        let u = UUID()
        let d = UUID()
        let f = UUID()
        project.universes = [Universe(id: u, number: 1)]
        project.fixtureDefinitions = [
            FixtureDefinition(
                id: d,
                manufacturer: "G",
                model: "D",
                channels: [ChannelDef(offset: 1, name: "I", attribute: "intensity")]
            )
        ]
        project.fixtures = [
            PatchedFixture(id: f, name: "F", definitionId: d, universeId: u, address: 1)
        ]
        // Broken palette ref on a cue → validation issues cached on load.
        let missing = UUID()
        project.cueLists = [
            CueList(name: "M", cues: [
                Cue(
                    number: 1,
                    name: "Q",
                    levels: CueLevelData(fixtures: [
                        FixtureCueLevels(fixtureId: f, paletteRefs: ["color": missing])
                    ])
                )
            ])
        ]

        let engine = LightingEngine(output: OutputManager())
        engine.load(project: project)
        engine.stepForTesting()
        let snap = engine.currentSnapshot()
        XCTAssertFalse(snap.resolutionIssues.isEmpty)
        XCTAssertEqual(engine.resolutionIssues.count, snap.resolutionIssues.count)
    }
}
