import AuroraCore
import AuroraModel
import SwiftUI

/// Fixture library browser (full implementation in PR8).
public struct FixtureBrowserPanel: View {
    public var context: WorkspacePanelContext

    public init(context: WorkspacePanelContext) {
        self.context = context
    }

    public var body: some View {
        if context.fixtureLibrary == nil {
            PlaceholderPanel(
                title: WorkspacePanelID.fixtureBrowser.title,
                detail: "Load a fixture library to browse personalities. PR8 wires the seed library."
            )
        } else {
            FixtureBrowserContent(context: context)
        }
    }
}

/// Real browser UI (used when a library is injected).
struct FixtureBrowserContent: View {
    var context: WorkspacePanelContext
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var errorText: String?

    private var library: FixtureLibraryBox { context.fixtureLibrary! }

    private var results: [FixtureDefinition] {
        query.isEmpty ? library.definitions : library.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search fixtures", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            List(results, id: \.id, selection: $selectedID) { definition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.displayName)
                        .font(.body)
                    Text("\(definition.channelCount) ch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(definition.id)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            }

            HStack {
                Button("Patch Selected") {
                    patchSelected()
                }
                .disabled(selectedID == nil || context.project.universes.isEmpty)
                Spacer()
            }
            .padding(8)
        }
    }

    private func patchSelected() {
        errorText = nil
        guard let selectedID,
              let definition = library.definitions.first(where: { $0.id == selectedID })
        else { return }
        guard let universe = context.project.universes.first else {
            errorText = "Add a universe in the Patch panel first."
            return
        }
        let embed = library.makeEmbeddableCopy(definition)
        let channelCount = embed.channelCount
        let address = context.project.nextFreeAddress(in: universe.id, channelCount: channelCount) ?? 1
        let fixture = PatchedFixture(
            name: "\(embed.model) \(context.project.fixtures.count + 1)",
            definitionId: embed.id,
            universeId: universe.id,
            address: address
        )
        do {
            try context.session.perform(PatchFixtureCommand(definition: embed, fixture: fixture))
        } catch {
            errorText = error.localizedDescription
        }
    }
}
