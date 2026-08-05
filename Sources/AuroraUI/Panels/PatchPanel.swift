import AuroraCore
import AuroraModel
import SwiftUI

/// Patch map / table for the current show.
public struct PatchPanel: View {
    public var context: WorkspacePanelContext
    @State private var selectedUniverseID: UUID?
    @State private var errorText: String?
    @State private var repatchFixtureID: UUID?
    @State private var repatchAddress: String = ""

    public init(context: WorkspacePanelContext) {
        self.context = context
    }

    private var universes: [Universe] { context.project.universes }

    private var selectedUniverse: Universe? {
        if let selectedUniverseID {
            return universes.first { $0.id == selectedUniverseID }
        }
        return universes.first
    }

    private var fixturesInUniverse: [PatchedFixture] {
        guard let uid = selectedUniverse?.id else { return [] }
        return context.project.fixtures
            .filter { $0.universeId == uid }
            .sorted { $0.address < $1.address }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                if universes.isEmpty {
                    Text("No universes")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Universe", selection: Binding(
                        get: { selectedUniverse?.id ?? universes[0].id },
                        set: { selectedUniverseID = $0 }
                    )) {
                        ForEach(universes) { universe in
                            Text("\(universe.number): \(universe.name)").tag(universe.id)
                        }
                    }
                    .labelsHidden()
                }
                Spacer()
                Button("Add Universe") { addUniverse() }
                Button("Clone") { cloneSelected() }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                Button("Remove") { removeSelected() }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
            }
            .padding(8)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            }

            if fixturesInUniverse.isEmpty {
                PlaceholderPanel(
                    title: "Patch",
                    detail: universes.isEmpty
                        ? "Add a universe, then patch fixtures from the Fixture Browser."
                        : "No fixtures in this universe. Patch from the Fixture Browser."
                )
            } else {
                Table(fixturesInUniverse, selection: fixtureSelection) {
                    TableColumn("Addr") { fixture in
                        Text("\(fixture.address)")
                            .font(.body.monospaced())
                    }
                    .width(50)
                    TableColumn("End") { fixture in
                        let end = fixture.endAddress(channelCount: context.project.channelCount(for: fixture))
                        Text("\(end)")
                            .font(.body.monospaced())
                    }
                    .width(50)
                    TableColumn("Name") { fixture in
                        Text(fixture.name)
                    }
                    TableColumn("Personality") { fixture in
                        Text(context.project.definition(id: fixture.definitionId)?.displayName ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
                .onTapGesture {} // selection via table
            }

            if !context.project.patchConflicts().isEmpty {
                Text("Warning: \(context.project.patchConflicts().count) patch overlap(s)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
            }
        }
        .onAppear {
            if selectedUniverseID == nil {
                selectedUniverseID = universes.first?.id
            }
        }
        .sheet(item: $repatchFixtureID) { id in
            VStack(alignment: .leading, spacing: 12) {
                Text("Repatch Fixture").font(.headline)
                TextField("DMX address", text: $repatchAddress)
                HStack {
                    Button("Cancel") { repatchFixtureID = nil }
                    Button("Apply") { applyRepatch(id) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 280)
        }
    }

    private var fixtureSelection: Binding<Set<PatchedFixture.ID>> {
        Binding(
            get: { context.session.selection.snapshot.fixtureIDs },
            set: { context.session.selectFixtures($0) }
        )
    }

    private func addUniverse() {
        errorText = nil
        let number = (universes.map(\.number).max() ?? 0) + 1
        do {
            try context.session.perform(AddUniverseCommand(universe: Universe(number: number)))
            selectedUniverseID = context.project.universes.last?.id
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func removeSelected() {
        errorText = nil
        let ids = context.session.selection.snapshot.fixtureIDs
        do {
            try context.session.beginGroup(named: "Remove Fixtures")
            for id in ids {
                try context.session.perform(RemovePatchedFixtureCommand(fixtureID: id))
            }
            try context.session.endGroup()
        } catch {
            try? context.session.cancelGroup()
            errorText = error.localizedDescription
        }
    }

    private func cloneSelected() {
        errorText = nil
        guard let id = context.session.selection.snapshot.fixtureIDs.first else { return }
        do {
            try context.session.perform(ClonePatchedFixtureCommand(sourceFixtureID: id))
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func applyRepatch(_ id: UUID) {
        errorText = nil
        guard let address = UInt16(repatchAddress),
              let universeID = selectedUniverse?.id
        else {
            errorText = "Invalid address"
            return
        }
        do {
            try context.session.perform(
                RepatchFixtureCommand(fixtureID: id, universeID: universeID, address: address)
            )
            repatchFixtureID = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
