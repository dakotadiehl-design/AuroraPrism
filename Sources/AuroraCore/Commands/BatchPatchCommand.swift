import AuroraModel
import Foundation

/// Atomic multi-fixture patch from a validated `PatchBatchPlan` (Wave 2 — one path for drag/click/next-free).
@MainActor
public final class BatchPatchCommand: Command {
    public let name: String
    private let plan: PatchBatchPlan
    private var createdIDs: [UUID] = []

    public init(plan: PatchBatchPlan, name: String = "Patch Fixtures") {
        self.plan = plan
        self.name = name
    }

    public var createdFixtureIDs: [UUID] { createdIDs }

    public func perform(context: CommandContext) throws {
        guard plan.isValid, !plan.starts.isEmpty else {
            throw CommandError.message(plan.rejectionReason ?? "Invalid patch plan")
        }
        // Re-validate against current project.
        let fresh = PatchBatchPlanner.plan(
            project: context.project,
            definitionID: plan.definitionID,
            universeID: plan.universeID,
            startAddress: plan.startAddress,
            quantity: plan.quantity,
            namePrefix: plan.namePrefix
        )
        guard fresh.isValid else {
            throw CommandError.message(fresh.rejectionReason ?? "Patch no longer valid")
        }
        createdIDs = []
        context.updateProject { project in
            for (i, start) in fresh.starts.enumerated() {
                let id = UUID()
                createdIDs.append(id)
                project.fixtures.append(PatchedFixture(
                    id: id,
                    name: "\(fresh.namePrefix) \(i + 1)",
                    definitionId: fresh.definitionID,
                    universeId: fresh.universeID,
                    address: start
                ))
            }
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        let ids = Set(createdIDs)
        context.updateProject { project in
            project.fixtures.removeAll { ids.contains($0.id) }
            project.metadata.modifiedAt = Date()
        }
    }
}
