import AuroraModel
import Foundation

public extension DocumentSession {
    /// Embeds definitions as needed and patches multiple fixtures as a single undo group.
    func patchFixtures(_ requests: [PatchRequest], groupName: String = "Patch Fixtures") throws {
        guard !requests.isEmpty else { return }
        try beginGroup(named: groupName)

        do {
            // Track provisional placements so auto-addressing doesn't collide within the batch.
            var provisional = project

            for request in requests {
                var definition = request.definition
                if provisional.definition(id: definition.id) == nil {
                    try perform(EmbedFixtureDefinitionCommand(definition: definition))
                    provisional.fixtureDefinitions.append(definition)
                } else if let existing = provisional.definition(id: definition.id) {
                    definition = existing
                }

                let channelCount = definition.channelCount
                let address: UInt16
                if let explicit = request.address {
                    address = explicit
                } else if let next = provisional.nextFreeAddress(in: request.universeID, channelCount: channelCount) {
                    address = next
                } else {
                    throw CommandError.noFreeAddress(universeID: request.universeID, channelCount: channelCount)
                }

                let fixture = PatchedFixture(
                    name: request.name,
                    definitionId: definition.id,
                    universeId: request.universeID,
                    address: address,
                    notes: request.notes
                )
                try perform(AddPatchedFixtureCommand(fixture: fixture))
                provisional.fixtures.append(fixture)
            }

            try endGroup()
        } catch {
            try? cancelGroup()
            throw error
        }
    }
}
