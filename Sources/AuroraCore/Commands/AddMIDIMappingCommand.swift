import AuroraModel
import Foundation

@MainActor
public final class AddMIDIMappingCommand: Command {
    public let name: String
    private let mapping: MIDIMapping

    public init(mapping: MIDIMapping, name: String = "Add MIDI Mapping") {
        self.mapping = mapping
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        context.updateProject { project in
            project.midiMappings.removeAll {
                $0.action == mapping.action && $0.actionParameter == mapping.actionParameter
                    && $0.messageType == mapping.messageType
            }
            project.midiMappings.append(mapping)
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject { project in
            project.midiMappings.removeAll { $0.id == mapping.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
