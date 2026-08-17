import AuroraCore
import AuroraModel
import XCTest

@MainActor
final class AMECommandsTests: XCTestCase {
    func testRemoveMappingRestoresIndexOnUndo() throws {
        var project = ShowProject.empty(name: "AME")
        let a = AMEMapping(name: "A", actions: [.go])
        let b = AMEMapping(name: "B", actions: [.stop])
        let c = AMEMapping(name: "C", actions: [.back])
        project.ame.mappings = [a, b, c]
        let session = DocumentSession(project: project)

        try session.perform(RemoveAMEMappingCommand(mappingID: b.id))
        XCTAssertEqual(session.project.ame.mappings.map(\.name), ["A", "C"])

        try session.undo()
        XCTAssertEqual(session.project.ame.mappings.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(session.project.ame.mappings[1].id, b.id)
    }

    func testRemoveTriggerRestoresIndexOnUndo() throws {
        var project = ShowProject.empty(name: "AME")
        let t0 = AMETriggerDefinition(name: "T0")
        let t1 = AMETriggerDefinition(name: "T1")
        let t2 = AMETriggerDefinition(name: "T2")
        project.ame.triggers = [t0, t1, t2]
        let session = DocumentSession(project: project)

        try session.perform(RemoveAMETriggerCommand(triggerID: t1.id))
        try session.undo()
        XCTAssertEqual(session.project.ame.triggers.map(\.name), ["T0", "T1", "T2"])
    }

    func testRemoveSequenceRestoresIndexOnUndo() throws {
        var project = ShowProject.empty(name: "AME")
        let s0 = AMETriggeredSequence(name: "S0")
        let s1 = AMETriggeredSequence(name: "S1")
        project.ame.sequences = [s0, s1]
        let session = DocumentSession(project: project)

        try session.perform(RemoveAMESequenceCommand(sequenceID: s0.id))
        XCTAssertEqual(session.project.ame.sequences.map(\.name), ["S1"])
        try session.undo()
        XCTAssertEqual(session.project.ame.sequences.map(\.name), ["S0", "S1"])
    }

    func testUpsertMappingEditUndo() throws {
        var project = ShowProject.empty(name: "AME")
        var mapping = AMEMapping(name: "Original", actions: [.go])
        project.ame.mappings = [mapping]
        let session = DocumentSession(project: project)

        mapping.name = "Edited"
        mapping.behavior = .toggle
        mapping.actions = [.blind]
        try session.perform(UpsertAMEMappingCommand(mapping: mapping))
        XCTAssertEqual(session.project.ame.mappings[0].name, "Edited")
        XCTAssertEqual(session.project.ame.mappings[0].behavior, .toggle)

        try session.undo()
        XCTAssertEqual(session.project.ame.mappings[0].name, "Original")
        XCTAssertEqual(session.project.ame.mappings[0].behavior, .trigger)
    }

    func testDuplicateMapping() throws {
        var project = ShowProject.empty(name: "AME")
        let mapping = AMEMapping(name: "Snare", actions: [.go])
        project.ame.mappings = [mapping]
        let session = DocumentSession(project: project)

        try session.perform(DuplicateAMEMappingCommand(mappingID: mapping.id))
        XCTAssertEqual(session.project.ame.mappings.count, 2)
        XCTAssertEqual(session.project.ame.mappings[1].name, "Snare Copy")
        XCTAssertNotEqual(session.project.ame.mappings[1].id, mapping.id)

        try session.undo()
        XCTAssertEqual(session.project.ame.mappings.count, 1)
    }

    func testLearnCommitUndoRestoresDocument() throws {
        let project = ShowProject.empty(name: "AME")
        let session = DocumentSession(project: project)
        let binding = MIDISourceBinding(displayName: "Pad", lastCoreMIDIUniqueID: 1)
        let trigger = AMETriggerDefinition(name: "Learned", sourceBindingID: binding.id, data1Min: 36, data1Max: 36)
        let mapping = AMEMapping(name: "Learned", triggerID: trigger.id, actions: [.go])

        try session.perform(CommitAMELearnCommand(binding: binding, trigger: trigger, mapping: mapping))
        XCTAssertEqual(session.project.ame.mappings.count, 1)
        XCTAssertEqual(session.project.ame.triggers.count, 1)
        XCTAssertEqual(session.project.ame.sourceBindings.count, 1)

        try session.undo()
        XCTAssertTrue(session.project.ame.mappings.isEmpty)
        XCTAssertTrue(session.project.ame.triggers.isEmpty)
        XCTAssertTrue(session.project.ame.sourceBindings.isEmpty)
    }

    func testMusicalSettingsCommandUndo() throws {
        var project = ShowProject.empty(name: "AME")
        project.ame.musicalSettings.defaultTempoBPM = 120
        let session = DocumentSession(project: project)
        var settings = project.ame.musicalSettings
        settings.defaultTempoBPM = 96
        settings.timingPolicy = .externalPreferredFallback
        settings.freewheelSeconds = 3
        try session.perform(SetAMEMusicalSettingsCommand(settings: settings))
        XCTAssertEqual(session.project.ame.musicalSettings.defaultTempoBPM, 96)
        XCTAssertEqual(session.project.ame.musicalSettings.timingPolicy, .externalPreferredFallback)
        try session.undo()
        XCTAssertEqual(session.project.ame.musicalSettings.defaultTempoBPM, 120)
    }

    func testSourceBindingCRUD() throws {
        let project = ShowProject.empty(name: "AME")
        let session = DocumentSession(project: project)
        let binding = MIDISourceBinding(displayName: "Pad", endpointNameHint: "Pad")
        try session.perform(UpsertMIDISourceBindingCommand(binding: binding))
        XCTAssertEqual(session.project.ame.sourceBindings.count, 1)
        try session.perform(RemoveMIDISourceBindingCommand(bindingID: binding.id))
        XCTAssertTrue(session.project.ame.sourceBindings.isEmpty)
        try session.undo()
        XCTAssertEqual(session.project.ame.sourceBindings.count, 1)
    }
}
