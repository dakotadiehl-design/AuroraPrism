import AppKit
import AuroraCore
import AuroraModel
import SwiftUI

/// Compact fixture / group browser for Build workspace (UI-02A).
public struct FixtureBrowserPanel: View {
    public var context: WorkspacePanelContext
    /// Explicit user click for inspection (not programmatic selection) — UI-02 B1.
    public var onInspectFixtures: ([UUID]) -> Void
    /// Explicit group row click for group inspection.
    public var onInspectGroup: (UUID) -> Void

    @State private var query = ""
    @State private var librarySelectedID: UUID?
    @State private var errorText: String?
    @State private var showLibrary = false

    public init(
        context: WorkspacePanelContext,
        onInspectFixtures: @escaping ([UUID]) -> Void = { _ in },
        onInspectGroup: @escaping (UUID) -> Void = { _ in }
    ) {
        self.context = context
        self.onInspectFixtures = onInspectFixtures
        self.onInspectGroup = onInspectGroup
    }

    private var selectedIDs: Set<UUID> {
        context.session.selection.snapshot.fixtureIDs
    }

    private var orderedSelection: [UUID] {
        context.session.selection.snapshot.orderedFixtureIDs
    }

    private var selectionSummary: some View {
        let orderPreview = orderedSelection.prefix(8).enumerated().map { i, id in
            let n = context.project.fixtures.first(where: { $0.id == id })?.name ?? "·"
            return "\(i + 1).\(n)"
        }.joined(separator: " → ")
        let more = orderedSelection.count > 8 ? " …" : ""
        return VStack(alignment: .leading, spacing: 2) {
            Text("Selection: \(orderedSelection.count)")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.accentBright)
            Text("Order: \(orderPreview)\(more)")
                .font(AuroraTypography.metadata)
                .foregroundStyle(AuroraColor.textTertiary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var filteredFixtures: [PatchedFixture] {
        let all = context.project.fixtures
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }

    private var filteredGroups: [AuroraModel.Group] {
        let all = context.project.groups
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            AuroraSearchField(text: $query, placeholder: "Search fixtures…")
                .padding(6)

            if !selectedIDs.isEmpty {
                selectionSummary
            }

            if context.project.fixtures.isEmpty && context.project.groups.isEmpty {
                AuroraEmptyState(
                    title: "No fixtures patched",
                    detail: "Add a universe, then patch from the library.",
                    systemImage: "lightbulb"
                )
                if context.fixtureLibrary != nil {
                    Button("Show Library") { showLibrary = true }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 8)
                }
            } else {
                List {
                    if !filteredGroups.isEmpty {
                        Section("Groups") {
                            ForEach(filteredGroups) { group in
                                groupRow(group)
                            }
                        }
                    }
                    Section("Fixtures (\(filteredFixtures.count))") {
                        ForEach(filteredFixtures) { fixture in
                            fixtureRow(fixture)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(AuroraColor.surfacePanel)
            }

            if let errorText {
                Text(errorText)
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.critical)
                    .padding(6)
            }

            if showLibrary, context.fixtureLibrary != nil {
                Divider()
                libraryPatchBar
            } else if context.fixtureLibrary != nil {
                HStack {
                    Button(showLibrary ? "Hide Library" : "Library / Patch") {
                        showLibrary.toggle()
                    }
                    .font(AuroraTypography.metadata)
                    .buttonStyle(.borderless)
                    .foregroundStyle(AuroraColor.accentBright)
                    Spacer()
                }
                .padding(6)
            }
        }
        .background(AuroraColor.surfacePanel)
        .auroraDensity(.compact)
    }

    private func fixtureRow(_ fixture: PatchedFixture) -> some View {
        let selected = selectedIDs.contains(fixture.id)
        return Button {
            if NSEvent.modifierFlags.contains(.command) {
                context.session.toggleFixtureSelection(fixture.id)
            } else {
                context.session.selectFixturesOrdered([fixture.id], extending: false)
            }
            onInspectFixtures(context.session.selection.snapshot.orderedFixtureIDs)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(selected ? AuroraColor.accentBright : AuroraColor.textTertiary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(fixture.name)
                    .font(AuroraTypography.secondary)
                    .foregroundStyle(selected ? AuroraColor.textPrimary : AuroraColor.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(fixture.address)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? AuroraColor.surfaceSelected : Color.clear)
    }

    private func groupRow(_ group: AuroraModel.Group) -> some View {
        let selected = !group.fixtureIds.isEmpty && Set(group.fixtureIds).isSubset(of: selectedIDs)
        return Button {
            context.session.selectFixturesOrdered(group.fixtureIds, extending: false)
            onInspectGroup(group.id)
        } label: {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10))
                    .foregroundStyle(AuroraColor.textTertiary)
                Text(group.name)
                    .font(AuroraTypography.secondary)
                    .foregroundStyle(selected ? AuroraColor.textPrimary : AuroraColor.textSecondary)
                Spacer()
                Text("\(group.fixtureIds.count)")
                    .font(AuroraTypography.metadata)
                    .foregroundStyle(AuroraColor.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? AuroraColor.surfaceSelected : Color.clear)
    }

    private var libraryPatchBar: some View {
        let library = context.fixtureLibrary!
        let results = query.isEmpty ? library.definitions : library.search(query)
        return VStack(spacing: 4) {
            Text("Library")
                .font(AuroraTypography.controlLabel)
                .foregroundStyle(AuroraColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            List(results, id: \.id, selection: $librarySelectedID) { def in
                Text(def.displayName)
                    .font(AuroraTypography.metadata)
                    .tag(def.id)
            }
            .frame(height: 100)
            Button("Patch Selected Personality") { patchSelected() }
                .disabled(librarySelectedID == nil || context.project.universes.isEmpty)
                .font(AuroraTypography.metadata)
        }
        .padding(6)
    }

    private func patchSelected() {
        errorText = nil
        guard let library = context.fixtureLibrary,
              let librarySelectedID,
              let definition = library.definitions.first(where: { $0.id == librarySelectedID })
        else { return }
        guard let universe = context.project.universes.first else {
            errorText = "Add a universe first."
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
