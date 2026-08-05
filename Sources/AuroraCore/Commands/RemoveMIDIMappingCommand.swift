import AuroraModel
import Foundation

@MainActor
public final class RemoveMIDIMappingCommand: Command {
    public let name: String
    private let mappingID: UUID
    private var removed: MIDIMapping?

    public init(mappingID: UUID, name: String = "Remove MIDI Mapping") {
        self.mappingID = mappingID
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let m = context.project.midiMappings.first(where: { $0.id == mappingID }) else {
            throw CommandError.message("MIDI mapping not found")
        }
        removed = m
        context.updateProject { project in
            project.midiMappings.removeAll { $0.id == mappingID }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed else { return }
        context.updateProject { project in
            project.midiMappings.append(removed)
            project.metadata.modifiedAt = Date()
        }
    }
}
