import AuroraModel
import Foundation

/// Place a patched fixture onto the Stage (creates StageFixturePlacement only).
@MainActor
public final class PlaceFixtureOnStageCommand: Command {
    public let name: String
    private let fixtureID: UUID
    private let x: Double
    private let y: Double
    private var createdPlacementID: UUID?

    public init(fixtureID: UUID, x: Double, y: Double, name: String = "Place on Stage") {
        self.fixtureID = fixtureID
        self.x = x
        self.y = y
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        guard context.project.fixtures.contains(where: { $0.id == fixtureID }) else {
            throw CommandError.message("Fixture not found")
        }
        if context.project.stageLayout.fixtures.contains(where: { $0.fixtureID == fixtureID }) {
            throw CommandError.message("Fixture already on Stage")
        }
        let category = context.project.fixtures.first(where: { $0.id == fixtureID })
            .flatMap { context.project.definition(id: $0.definitionId)?.category } ?? "generic"
        let placement = StageFixturePlacement.placed(fixtureID: fixtureID, x: x, y: y, category: category)
        createdPlacementID = placement.id
        context.updateProject { project in
            var layout = project.stageLayout
            layout.fixtures.append(placement)
            project.stageLayout = layout
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let pid = createdPlacementID else { return }
        context.updateProject { project in
            var layout = project.stageLayout
            layout.fixtures.removeAll { $0.id == pid }
            project.stageLayout = layout
            project.metadata.modifiedAt = Date()
        }
    }
}

/// Remove Stage placement only — fixture remains patched (Amendment §8).
@MainActor
public final class RemoveFromStageCommand: Command {
    public let name: String
    private let fixtureIDs: [UUID]
    private var removed: [StageFixturePlacement] = []

    public init(fixtureIDs: [UUID], name: String = "Remove From Stage") {
        self.fixtureIDs = fixtureIDs
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        let set = Set(fixtureIDs)
        removed = context.project.stageLayout.fixtures.filter { set.contains($0.fixtureID) }
        guard !removed.isEmpty else { return }
        context.updateProject { project in
            var layout = project.stageLayout
            layout.fixtures.removeAll { set.contains($0.fixtureID) }
            project.stageLayout = layout
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard !removed.isEmpty else { return }
        context.updateProject { project in
            var layout = project.stageLayout
            for p in removed {
                if !layout.fixtures.contains(where: { $0.fixtureID == p.fixtureID }) {
                    layout.fixtures.append(p)
                }
            }
            project.stageLayout = layout
            project.metadata.modifiedAt = Date()
        }
    }
}

/// Deterministic grid placement for all unplaced fixtures (one undo).
@MainActor
public final class PlaceAllUnplacedCommand: Command {
    public let name: String
    private var created: [StageFixturePlacement] = []

    public init(name: String = "Place All Unplaced") {
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        let placed = Set(context.project.stageLayout.fixtures.map(\.fixtureID))
        let unplaced = context.project.fixtures.filter { !placed.contains($0.id) }
        guard !unplaced.isEmpty else { return }
        let cols = 8
        let spacingX = 90.0
        let spacingY = 90.0
        let originX = 80.0
        let originY = 80.0
        created = []
        for (i, fx) in unplaced.enumerated() {
            let col = i % cols
            let row = i / cols
            let category = context.project.definition(id: fx.definitionId)?.category ?? "generic"
            created.append(StageFixturePlacement.placed(
                fixtureID: fx.id,
                x: originX + Double(col) * spacingX,
                y: originY + Double(row) * spacingY,
                category: category
            ))
        }
        context.updateProject { project in
            var layout = project.stageLayout
            layout.fixtures.append(contentsOf: created)
            project.stageLayout = layout
            project.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        let ids = Set(created.map(\.id))
        context.updateProject { project in
            var layout = project.stageLayout
            layout.fixtures.removeAll { ids.contains($0.id) }
            project.stageLayout = layout
            project.metadata.modifiedAt = Date()
        }
    }
}
