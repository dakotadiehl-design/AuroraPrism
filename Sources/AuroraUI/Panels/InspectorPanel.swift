import AuroraModel
import SwiftUI

/// Selection inspector (fixture-focused for PR8).
public struct InspectorPanel: View {
    public var context: WorkspacePanelContext

    public init(context: WorkspacePanelContext) {
        self.context = context
    }

    public var body: some View {
        let fixtureIDs = context.session.selection.snapshot.fixtureIDs
        if fixtureIDs.isEmpty {
            PlaceholderPanel(
                title: "Inspector",
                detail: "Select a fixture in the Patch panel to inspect it."
            )
        } else if fixtureIDs.count > 1 {
            PlaceholderPanel(
                title: "Inspector",
                detail: "\(fixtureIDs.count) fixtures selected."
            )
        } else if let id = fixtureIDs.first,
                  let fixture = context.project.fixtures.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(fixture.name)
                        .font(.title3.weight(.semibold))
                    labeled("Address", "\(fixture.address)")
                    labeled(
                        "End",
                        "\(fixture.endAddress(channelCount: context.project.channelCount(for: fixture)))"
                    )
                    if let universe = context.project.universe(id: fixture.universeId) {
                        labeled("Universe", "\(universe.number) — \(universe.name)")
                    }
                    if let definition = context.project.definition(id: fixture.definitionId) {
                        labeled("Personality", definition.displayName)
                        labeled("Channels", "\(definition.channelCount)")
                    }
                    if !fixture.notes.isEmpty {
                        labeled("Notes", fixture.notes)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } else {
            PlaceholderPanel(title: "Inspector", detail: "Selected fixture not found.")
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}
