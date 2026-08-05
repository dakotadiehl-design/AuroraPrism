import AuroraCore
import AuroraModel
import SwiftUI

public struct GroupsPanel: View {
    public var context: WorkspacePanelContext
    public var onChanged: () -> Void

    public init(context: WorkspacePanelContext, onChanged: @escaping () -> Void = {}) {
        self.context = context
        self.onChanged = onChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Groups").font(.headline)
                Spacer()
                Button("New from Selection") { createFromSelection() }
                .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
            }
            List(context.project.groups) { group in
                HStack {
                    VStack(alignment: .leading) {
                        Text(group.name)
                        Text("\(group.fixtureIds.count) fixtures")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Select") {
                        context.session.selectFixtures(Set(group.fixtureIds))
                        onChanged()
                    }
                    Button("Delete", role: .destructive) {
                        try? context.session.perform(RemoveGroupCommand(groupID: group.id))
                        onChanged()
                    }
                }
            }
        }
        .padding(8)
    }

    private func createFromSelection() {
        let ids = Array(context.session.selection.snapshot.fixtureIDs)
        let group = Group(name: "Group \(context.project.groups.count + 1)", fixtureIds: ids)
        try? context.session.perform(AddGroupCommand(group: group))
        onChanged()
    }
}
