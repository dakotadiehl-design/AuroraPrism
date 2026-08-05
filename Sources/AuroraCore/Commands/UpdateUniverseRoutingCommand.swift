import AuroraModel
import Foundation

/// Change a universe's protocol route (HW-01 pre-UI-09 operator path).
@MainActor
public final class UpdateUniverseRoutingCommand: Command {
    public let name: String
    private let universeID: UUID
    private let protocolHint: UniverseProtocolHint
    private var previousHint: UniverseProtocolHint?

    public init(universeID: UUID, protocolHint: UniverseProtocolHint, name: String = "Update Universe Routing") {
        self.universeID = universeID
        self.protocolHint = protocolHint
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard let i = context.project.universes.firstIndex(where: { $0.id == universeID }) else {
            throw CommandError.message("Universe not found")
        }
        previousHint = context.project.universes[i].protocolHint
        context.updateProject { project in
            project.universes[i].protocolHint = protocolHint
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previousHint,
              let i = context.project.universes.firstIndex(where: { $0.id == universeID })
        else { return }
        context.updateProject { project in
            project.universes[i].protocolHint = previousHint
            project.metadata.modifiedAt = Date()
        }
    }
}
