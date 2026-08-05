import AuroraCore
import AuroraModel
import SwiftUI

public struct GroupsPanel: View {
    public var context: WorkspacePanelContext
    public var onChanged: () -> Void
    public var onInspectGroup: (UUID) -> Void

    public init(
        context: WorkspacePanelContext,
        onChanged: @escaping () -> Void = {},
        onInspectGroup: @escaping (UUID) -> Void = { _ in }
    ) {
        self.context = context
        self.onChanged = onChanged
        self.onInspectGroup = onInspectGroup
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Groups")
                    .font(AuroraTypography.panelTitle)
                    .foregroundStyle(AuroraColor.textSecondary)
                Spacer()
                Button("New from Selection") { createFromSelection() }
                    .disabled(context.session.selection.snapshot.fixtureIDs.isEmpty)
                    .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            List(context.project.groups) { group in
                HStack {
                    VStack(alignment: .leading) {
                        Text(group.name)
                            .font(AuroraTypography.secondary)
                        Text("\(group.fixtureIds.count) fixtures")
                            .font(AuroraTypography.metadata)
                            .foregroundStyle(AuroraColor.textTertiary)
                    }
                    Spacer()
                    Button("Select") {
                        context.session.selectFixtures(Set(group.fixtureIds))
                        onInspectGroup(group.id)
                        onChanged()
                    }
                    .controlSize(.small)
                    Button("Inspect") {
                        onInspectGroup(group.id)
                        onChanged()
                    }
                    .controlSize(.small)
                    Button("Delete", role: .destructive) {
                        try? context.session.perform(RemoveGroupCommand(groupID: group.id))
                        onChanged()
                    }
                    .controlSize(.small)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onInspectGroup(group.id)
                    onChanged()
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(AuroraColor.surfacePanel)
    }

    private func createFromSelection() {
        let ids = Array(context.session.selection.snapshot.fixtureIDs)
        let group = Group(name: "Group \(context.project.groups.count + 1)", fixtureIds: ids)
        try? context.session.perform(AddGroupCommand(group: group))
        onChanged()
    }
}
