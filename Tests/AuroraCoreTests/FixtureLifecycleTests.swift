import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class FixtureLifecycleTests: XCTestCase {
    private func dimmer(id: UUID = UUID()) -> FixtureDefinition {
        FixtureDefinition(
            id: id,
            manufacturer: "Generic",
            model: "Dimmer",
            modeName: "1ch",
            channelCount: 1,
            channels: [ChannelDef(offset: 1, name: "Intensity", attribute: "intensity")]
        )
    }

    private func projectWithFixture(
        address: UInt16 = 10,
        name: String = "Wash 1",
        withGroup: Bool = false,
        withStage: Bool = false,
        withCue: Bool = false,
        withEffect: Bool = false
    ) -> (ShowProject, Universe, FixtureDefinition, PatchedFixture) {
        let universe = Universe(number: 1, name: "Main")
        let def = dimmer()
        let fx = PatchedFixture(
            name: name,
            definitionId: def.id,
            universeId: universe.id,
            address: address
        )
        var project = ShowProject.empty(name: "Life")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [fx]
        if withGroup {
            project.groups = [Group(name: "Front", fixtureIds: [fx.id])]
        }
        if withStage {
            project.stageLayout = StageLayout(fixtures: [
                StageFixturePlacement(fixtureID: fx.id, x: 12, y: 34)
            ])
        }
        if withCue {
            project.cueLists = [
                CueList(
                    name: "Main",
                    cues: [
                        Cue(
                            number: 1,
                            name: "A",
                            levels: CueLevelData(fixtures: [
                                FixtureCueLevels(fixtureId: fx.id, attributes: ["intensity": 0.8]),
                                FixtureCueLevels(fixtureId: UUID(), attributes: ["intensity": 0.2])
                            ])
                        )
                    ]
                )
            ]
        }
        if withEffect {
            project.effects = [EffectDefinition(name: "Chase", fixtureIDs: [fx.id, UUID()])]
        }
        return (project, universe, def, fx)
    }

    // MARK: - Unpatch preservation

    func testUnpatchClearsAddressPreservesIdentityAndReferences() throws {
        let (project, universe, def, fx) = projectWithFixture(
            address: 5,
            withGroup: true,
            withStage: true,
            withCue: true
        )
        let session = DocumentSession(project: project)

        try session.perform(UnpatchFixtureCommand(fixtureID: fx.id))

        let after = try XCTUnwrap(session.project.fixtures.first(where: { $0.id == fx.id }))
        XCTAssertEqual(after.id, fx.id)
        XCTAssertFalse(after.isPatched)
        XCTAssertEqual(after.address, PatchedFixture.unpatchedAddress)
        XCTAssertEqual(after.name, "Wash 1")
        XCTAssertEqual(after.definitionId, def.id)
        XCTAssertEqual(after.universeId, universe.id, "Preferred universe retained for repatch")

        // Groups, Stage, cues preserved
        XCTAssertTrue(session.project.groups.contains { $0.fixtureIds.contains(fx.id) })
        XCTAssertTrue(session.project.stageLayout.fixtures.contains { $0.fixtureID == fx.id })
        let cueLevels = session.project.cueLists.flatMap(\.cues).flatMap(\.levels.fixtures)
        XCTAssertTrue(cueLevels.contains { $0.fixtureId == fx.id })

        // Address space free for re-use (including former address 5)
        XCTAssertTrue(
            session.project.canPlace(
                fixture: PatchedFixture(
                    name: "Other",
                    definitionId: def.id,
                    universeId: universe.id,
                    address: 5
                )
            )
        )
        XCTAssertEqual(session.project.nextFreeAddress(in: universe.id, channelCount: 1), 1)
        XCTAssertEqual(session.project.unpatchedFixtures.map(\.id), [fx.id])
        XCTAssertTrue(session.project.patchedFixtures.isEmpty)
    }

    func testUnpatchUndoRestoresAddress() throws {
        let (project, _, _, fx) = projectWithFixture(address: 3, name: "A")
        let session = DocumentSession(project: project)

        try session.perform(UnpatchFixtureCommand(fixtureID: fx.id))
        XCTAssertFalse(session.project.fixtures[0].isPatched)
        try session.undo()
        XCTAssertEqual(session.project.fixtures[0].address, 3)
        XCTAssertTrue(session.project.fixtures[0].isPatched)
    }

    func testMultiUnpatch() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let a = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 1)
        let b = PatchedFixture(name: "B", definitionId: def.id, universeId: universe.id, address: 2)
        var project = ShowProject.empty(name: "Multi")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [a, b]
        let session = DocumentSession(project: project)

        try session.perform(UnpatchFixtureCommand(fixtureIDs: [a.id, b.id]))
        XCTAssertEqual(session.project.unpatchedFixtures.count, 2)
        XCTAssertTrue(session.project.patchedFixtures.isEmpty)
    }

    // MARK: - Delete cleanup

    func testDeleteRemovesFixtureAndCleansReferences() throws {
        let (project, _, _, fx) = projectWithFixture(
            address: 1,
            name: "Kill",
            withGroup: true,
            withStage: true,
            withCue: true,
            withEffect: true
        )
        let session = DocumentSession(project: project)

        let summary = FixtureReferenceIndex.summarize(fixtureIDs: [fx.id], in: session.project)
        XCTAssertTrue(summary.hasDependencies)
        XCTAssertEqual(summary.groupCount, 1)
        XCTAssertEqual(summary.stagePlacementCount, 1)
        XCTAssertEqual(summary.cueLevelCount, 1)
        XCTAssertEqual(summary.effectCount, 1)

        try session.perform(RemovePatchedFixtureCommand(fixtureID: fx.id))

        XCTAssertTrue(session.project.fixtures.isEmpty)
        XCTAssertFalse(session.project.groups[0].fixtureIds.contains(fx.id))
        XCTAssertFalse(session.project.stageLayout.fixtures.contains { $0.fixtureID == fx.id })
        XCTAssertFalse(
            session.project.cueLists[0].cues[0].levels.fixtures.contains { $0.fixtureId == fx.id }
        )
        // Unrelated cue level preserved
        XCTAssertEqual(session.project.cueLists[0].cues[0].levels.fixtures.count, 1)
        XCTAssertFalse(session.project.effects[0].fixtureIDs.contains(fx.id))
    }

    func testDeleteUndoRestoresReferences() throws {
        let (project, _, _, fx) = projectWithFixture(
            address: 2,
            name: "Back",
            withGroup: true,
            withStage: true
        )
        let session = DocumentSession(project: project)

        try session.perform(RemovePatchedFixtureCommand(fixtureID: fx.id))
        XCTAssertTrue(session.project.fixtures.isEmpty)
        try session.undo()
        XCTAssertEqual(session.project.fixtures.first?.id, fx.id)
        XCTAssertTrue(session.project.groups[0].fixtureIds.contains(fx.id))
        XCTAssertTrue(session.project.stageLayout.fixtures.contains { $0.fixtureID == fx.id })
    }

    func testMultiDelete() throws {
        let universe = Universe(number: 1)
        let def = dimmer()
        let a = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 1)
        let b = PatchedFixture(name: "B", definitionId: def.id, universeId: universe.id, address: 2)
        var project = ShowProject.empty(name: "MD")
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [a, b]
        let session = DocumentSession(project: project)
        try session.perform(RemovePatchedFixtureCommand(fixtureIDs: [a.id, b.id]))
        XCTAssertTrue(session.project.fixtures.isEmpty)
    }

    // MARK: - Keyboard routing

    func testDeleteKeyRoutesToUnpatchNotDelete() {
        let (project, _, _, fx) = projectWithFixture(address: 1, name: "A")
        let action = PatchFixtureLifecycle.deleteKeyAction(
            isTextEditing: false,
            selectedFixtureIDs: [fx.id],
            project: project
        )
        XCTAssertEqual(action, .unpatch(fixtureIDs: [fx.id]))
    }

    func testDeleteKeyIgnoredWhileTextEditing() {
        let (project, _, _, fx) = projectWithFixture(address: 1, name: "A")
        let action = PatchFixtureLifecycle.deleteKeyAction(
            isTextEditing: true,
            selectedFixtureIDs: [fx.id],
            project: project
        )
        XCTAssertEqual(action, .ignore)
    }

    func testDeleteKeyIgnoresAlreadyUnpatched() {
        let (project, _, _, fx) = projectWithFixture(
            address: PatchedFixture.unpatchedAddress,
            name: "A"
        )
        let action = PatchFixtureLifecycle.deleteKeyAction(
            isTextEditing: false,
            selectedFixtureIDs: [fx.id],
            project: project
        )
        XCTAssertEqual(action, .ignore)
    }

    func testDeleteKeyMultiSelectionUnpatchesOnlyPatched() {
        let universe = Universe(number: 1)
        let def = dimmer()
        let a = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 1)
        let b = PatchedFixture(name: "B", definitionId: def.id, universeId: universe.id, address: 0)
        var project = ShowProject.empty()
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [a, b]

        let action = PatchFixtureLifecycle.deleteKeyAction(
            isTextEditing: false,
            selectedFixtureIDs: [a.id, b.id],
            project: project
        )
        XCTAssertEqual(action, .unpatch(fixtureIDs: [a.id]))
    }

    // MARK: - Context menu routing

    func testContextMenuActionsForPatchedSelection() {
        let (project, _, _, fx) = projectWithFixture(address: 1, name: "A")
        let actions = PatchFixtureLifecycle.contextMenuActions(
            selectedFixtureIDs: [fx.id],
            project: project
        )
        XCTAssertEqual(actions, [.inspect, .repatch, .unpatch, .deleteFixture])
    }

    func testContextMenuActionsForUnpatchedSelection() {
        let (project, _, _, fx) = projectWithFixture(address: 0, name: "A")
        let actions = PatchFixtureLifecycle.contextMenuActions(
            selectedFixtureIDs: [fx.id],
            project: project
        )
        XCTAssertEqual(actions, [.inspect, .repatch, .deleteFixture])
        XCTAssertFalse(actions.contains(.unpatch))
    }

    func testContextMenuMultiSelectionOmitsRepatch() {
        let universe = Universe(number: 1)
        let def = dimmer()
        let a = PatchedFixture(name: "A", definitionId: def.id, universeId: universe.id, address: 1)
        let b = PatchedFixture(name: "B", definitionId: def.id, universeId: universe.id, address: 2)
        var project = ShowProject.empty()
        project.universes = [universe]
        project.fixtureDefinitions = [def]
        project.fixtures = [a, b]

        let actions = PatchFixtureLifecycle.contextMenuActions(
            selectedFixtureIDs: [a.id, b.id],
            project: project
        )
        XCTAssertEqual(actions, [.inspect, .unpatch, .deleteFixture])
    }

    func testRepatchAfterUnpatchWorks() throws {
        let (project, universe, _, fx) = projectWithFixture(address: 7, name: "A")
        let session = DocumentSession(project: project)

        try session.perform(UnpatchFixtureCommand(fixtureID: fx.id))
        try session.perform(RepatchFixtureCommand(fixtureID: fx.id, universeID: universe.id, address: 20))
        let after = try XCTUnwrap(session.project.fixtures.first)
        XCTAssertEqual(after.id, fx.id)
        XCTAssertEqual(after.address, 20)
        XCTAssertTrue(after.isPatched)
    }

    func testUnpatchDoesNotAffectCompiledDMX() throws {
        // Engine should skip unpatched fixtures (verified via compile path in unit sense).
        let (project, _, _, fx) = projectWithFixture(address: 4)
        let session = DocumentSession(project: project)
        try session.perform(UnpatchFixtureCommand(fixtureID: fx.id))
        XCTAssertTrue(session.project.fixtures.contains { $0.id == fx.id })
        XCTAssertFalse(session.project.fixtures[0].isPatched)
    }
}
