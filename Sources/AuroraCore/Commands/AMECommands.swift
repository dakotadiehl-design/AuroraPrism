import AuroraModel
import Foundation

// MARK: - AME document edit commands (Wave 5)

@MainActor
public final class UpsertAMETriggerCommand: Command {
    public let name: String
    private let trigger: AMETriggerDefinition
    private var previous: AMETriggerDefinition?
    private var wasInsert = false

    public init(trigger: AMETriggerDefinition, name: String = "Edit AME Trigger") {
        self.trigger = trigger
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.triggers.firstIndex(where: { $0.id == trigger.id }) {
                previous = project.ame.triggers[idx]
                wasInsert = false
                project.ame.triggers[idx] = trigger
            } else {
                previous = nil
                wasInsert = true
                project.ame.triggers.append(trigger)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            if wasInsert {
                project.ame.triggers.removeAll { $0.id == trigger.id }
            } else if let previous, let idx = project.ame.triggers.firstIndex(where: { $0.id == trigger.id }) {
                project.ame.triggers[idx] = previous
            }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveAMETriggerCommand: Command {
    public let name: String
    private let triggerID: UUID
    private var removed: AMETriggerDefinition?
    private var removedIndex: Int?

    public init(triggerID: UUID, name: String = "Remove AME Trigger") {
        self.triggerID = triggerID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.triggers.firstIndex(where: { $0.id == triggerID }) {
                removedIndex = idx
                removed = project.ame.triggers[idx]
                project.ame.triggers.remove(at: idx)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed else { return }
        context.updateProject { project in
            let idx = min(removedIndex ?? project.ame.triggers.count, project.ame.triggers.count)
            project.ame.triggers.insert(removed, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class DuplicateAMETriggerCommand: Command {
    public let name: String
    private let sourceID: UUID
    private var created: AMETriggerDefinition?

    public init(triggerID: UUID, name: String = "Duplicate AME Trigger") {
        self.sourceID = triggerID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            guard let src = project.ame.triggers.first(where: { $0.id == sourceID }) else { return }
            var copy = src
            copy.id = UUID()
            copy.name = src.name.isEmpty ? "Trigger Copy" : "\(src.name) Copy"
            copy.friendlyName = copy.name
            created = copy
            project.ame.triggers.append(copy)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let created else { return }
        context.updateProject { project in
            project.ame.triggers.removeAll { $0.id == created.id }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpsertAMEMappingCommand: Command {
    public let name: String
    private let mapping: AMEMapping
    private var previous: AMEMapping?
    private var wasInsert = false

    public init(mapping: AMEMapping, name: String = "Edit AME Mapping") {
        self.mapping = mapping
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.mappings.firstIndex(where: { $0.id == mapping.id }) {
                previous = project.ame.mappings[idx]
                wasInsert = false
                project.ame.mappings[idx] = mapping
            } else {
                previous = nil
                wasInsert = true
                project.ame.mappings.append(mapping)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            if wasInsert {
                project.ame.mappings.removeAll { $0.id == mapping.id }
            } else if let previous, let idx = project.ame.mappings.firstIndex(where: { $0.id == mapping.id }) {
                project.ame.mappings[idx] = previous
            }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveAMEMappingCommand: Command {
    public let name: String
    private let mappingID: UUID
    private var removed: AMEMapping?
    private var removedIndex: Int?

    public init(mappingID: UUID, name: String = "Remove AME Mapping") {
        self.mappingID = mappingID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.mappings.firstIndex(where: { $0.id == mappingID }) {
                removedIndex = idx
                removed = project.ame.mappings[idx]
                project.ame.mappings.remove(at: idx)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed else { return }
        context.updateProject { project in
            let idx = min(removedIndex ?? project.ame.mappings.count, project.ame.mappings.count)
            project.ame.mappings.insert(removed, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class DuplicateAMEMappingCommand: Command {
    public let name: String
    private let sourceID: UUID
    private var created: AMEMapping?

    public init(mappingID: UUID, name: String = "Duplicate AME Mapping") {
        self.sourceID = mappingID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            guard let src = project.ame.mappings.first(where: { $0.id == sourceID }) else { return }
            var copy = src
            copy.id = UUID()
            copy.name = src.name.isEmpty ? "Mapping Copy" : "\(src.name) Copy"
            created = copy
            project.ame.mappings.append(copy)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let created else { return }
        context.updateProject { project in
            project.ame.mappings.removeAll { $0.id == created.id }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpsertAMESequenceCommand: Command {
    public let name: String
    private let sequence: AMETriggeredSequence
    private var previous: AMETriggeredSequence?
    private var wasInsert = false

    public init(sequence: AMETriggeredSequence, name: String = "Edit AME Sequence") {
        self.sequence = sequence
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.sequences.firstIndex(where: { $0.id == sequence.id }) {
                previous = project.ame.sequences[idx]
                wasInsert = false
                project.ame.sequences[idx] = sequence
            } else {
                previous = nil
                wasInsert = true
                project.ame.sequences.append(sequence)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            if wasInsert {
                project.ame.sequences.removeAll { $0.id == sequence.id }
            } else if let previous, let idx = project.ame.sequences.firstIndex(where: { $0.id == sequence.id }) {
                project.ame.sequences[idx] = previous
            }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveAMESequenceCommand: Command {
    public let name: String
    private let sequenceID: UUID
    private var removed: AMETriggeredSequence?
    private var removedIndex: Int?

    public init(sequenceID: UUID, name: String = "Remove AME Sequence") {
        self.sequenceID = sequenceID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.sequences.firstIndex(where: { $0.id == sequenceID }) {
                removedIndex = idx
                removed = project.ame.sequences[idx]
                project.ame.sequences.remove(at: idx)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed else { return }
        context.updateProject { project in
            let idx = min(removedIndex ?? project.ame.sequences.count, project.ame.sequences.count)
            project.ame.sequences.insert(removed, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class DuplicateAMESequenceCommand: Command {
    public let name: String
    private let sourceID: UUID
    private var created: AMETriggeredSequence?

    public init(sequenceID: UUID, name: String = "Duplicate AME Sequence") {
        self.sourceID = sequenceID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            guard let src = project.ame.sequences.first(where: { $0.id == sourceID }) else { return }
            var copy = src
            copy.id = UUID()
            copy.name = src.name.isEmpty ? "Sequence Copy" : "\(src.name) Copy"
            // Fresh step IDs so undo/delete identity stays unique.
            copy.steps = src.steps.map { step in
                var s = step
                s.id = UUID()
                return s
            }
            created = copy
            project.ame.sequences.append(copy)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let created else { return }
        context.updateProject { project in
            project.ame.sequences.removeAll { $0.id == created.id }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class SetAMEMusicalSettingsCommand: Command {
    public let name: String
    private let settings: MusicalEngineProjectSettings
    private var previous: MusicalEngineProjectSettings?

    public init(settings: MusicalEngineProjectSettings, name: String = "Edit AME Musical Settings") {
        self.settings = settings
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            previous = project.ame.musicalSettings
            project.ame.musicalSettings = settings
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous else { return }
        context.updateProject { project in
            project.ame.musicalSettings = previous
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpsertMIDISourceBindingCommand: Command {
    public let name: String
    private let binding: MIDISourceBinding
    private var previous: MIDISourceBinding?
    private var wasInsert = false

    public init(binding: MIDISourceBinding, name: String = "Edit MIDI Source Binding") {
        self.binding = binding
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.sourceBindings.firstIndex(where: { $0.id == binding.id }) {
                previous = project.ame.sourceBindings[idx]
                wasInsert = false
                project.ame.sourceBindings[idx] = binding
            } else {
                previous = nil
                wasInsert = true
                project.ame.sourceBindings.append(binding)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            if wasInsert {
                project.ame.sourceBindings.removeAll { $0.id == binding.id }
            } else if let previous, let idx = project.ame.sourceBindings.firstIndex(where: { $0.id == binding.id }) {
                project.ame.sourceBindings[idx] = previous
            }
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveMIDISourceBindingCommand: Command {
    public let name: String
    private let bindingID: UUID
    private var removed: MIDISourceBinding?
    private var removedIndex: Int?

    public init(bindingID: UUID, name: String = "Remove MIDI Source Binding") {
        self.bindingID = bindingID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let idx = project.ame.sourceBindings.firstIndex(where: { $0.id == bindingID }) {
                removedIndex = idx
                removed = project.ame.sourceBindings[idx]
                project.ame.sourceBindings.remove(at: idx)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed else { return }
        context.updateProject { project in
            let idx = min(removedIndex ?? project.ame.sourceBindings.count, project.ame.sourceBindings.count)
            project.ame.sourceBindings.insert(removed, at: idx)
            project.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class CommitAMELearnCommand: Command {
    public let name: String
    private let binding: MIDISourceBinding?
    private let trigger: AMETriggerDefinition
    private let mapping: AMEMapping
    private var previousBinding: MIDISourceBinding?
    private var previousTrigger: AMETriggerDefinition?
    private var previousMapping: AMEMapping?
    private var bindingWasInsert = false
    private var triggerWasInsert = false
    private var mappingWasInsert = false

    public init(
        binding: MIDISourceBinding?,
        trigger: AMETriggerDefinition,
        mapping: AMEMapping,
        name: String = "AME MIDI Learn"
    ) {
        self.binding = binding
        self.trigger = trigger
        self.mapping = mapping
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            if let binding {
                if let idx = project.ame.sourceBindings.firstIndex(where: { $0.id == binding.id }) {
                    previousBinding = project.ame.sourceBindings[idx]
                    bindingWasInsert = false
                    project.ame.sourceBindings[idx] = binding
                } else {
                    previousBinding = nil
                    bindingWasInsert = true
                    project.ame.sourceBindings.append(binding)
                }
            }
            if let idx = project.ame.triggers.firstIndex(where: { $0.id == trigger.id }) {
                previousTrigger = project.ame.triggers[idx]
                triggerWasInsert = false
                project.ame.triggers[idx] = trigger
            } else {
                previousTrigger = nil
                triggerWasInsert = true
                project.ame.triggers.append(trigger)
            }
            if let idx = project.ame.mappings.firstIndex(where: { $0.id == mapping.id }) {
                previousMapping = project.ame.mappings[idx]
                mappingWasInsert = false
                project.ame.mappings[idx] = mapping
            } else {
                previousMapping = nil
                mappingWasInsert = true
                project.ame.mappings.append(mapping)
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            if mappingWasInsert {
                project.ame.mappings.removeAll { $0.id == mapping.id }
            } else if let previousMapping, let idx = project.ame.mappings.firstIndex(where: { $0.id == mapping.id }) {
                project.ame.mappings[idx] = previousMapping
            }
            if triggerWasInsert {
                project.ame.triggers.removeAll { $0.id == trigger.id }
            } else if let previousTrigger, let idx = project.ame.triggers.firstIndex(where: { $0.id == trigger.id }) {
                project.ame.triggers[idx] = previousTrigger
            }
            if let binding {
                if bindingWasInsert {
                    project.ame.sourceBindings.removeAll { $0.id == binding.id }
                } else if let previousBinding, let idx = project.ame.sourceBindings.firstIndex(where: { $0.id == binding.id }) {
                    project.ame.sourceBindings[idx] = previousBinding
                }
            }
            project.metadata.modifiedAt = Date()
        }
    }
}
