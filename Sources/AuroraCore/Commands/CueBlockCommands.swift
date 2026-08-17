import AuroraModel
import Foundation

// MARK: - Cue Block organizational groups

@MainActor
public final class AddCueBlockGroupCommand: Command {
    public let name = "Add Cue Block Group"
    private let group: CueBlockGroup

    public init(group: CueBlockGroup) { self.group = group }

    public func perform(context: CommandContext) throws {
        guard !context.project.cueBlockGroups.contains(where: { $0.id == group.id }) else {
            throw CommandError.message("Cue Block Group already exists")
        }
        context.updateProject {
            $0.cueBlockGroups.append(group)
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject {
            $0.cueBlockGroups.removeAll { $0.id == group.id }
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpdateCueBlockGroupCommand: Command {
    public let name = "Update Cue Block Group"
    private let group: CueBlockGroup
    private var previous: CueBlockGroup?

    public init(group: CueBlockGroup) { self.group = group }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.cueBlockGroups.firstIndex(where: { $0.id == group.id }) else {
            throw CommandError.message("Cue Block Group not found")
        }
        previous = context.project.cueBlockGroups[index]
        context.updateProject {
            $0.cueBlockGroups[index] = group
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous,
              let index = context.project.cueBlockGroups.firstIndex(where: { $0.id == previous.id })
        else { return }
        context.updateProject {
            $0.cueBlockGroups[index] = previous
            $0.metadata.modifiedAt = Date()
        }
    }
}

/// Removes the organizational folder but preserves its lighting data by moving contained
/// Cue Blocks to the virtual Unfiled section. Undo restores both folder position and membership.
@MainActor
public final class RemoveCueBlockGroupCommand: Command {
    public let name = "Remove Cue Block Group"
    private let groupID: UUID
    private var removed: CueBlockGroup?
    private var removedIndex: Int?
    private var affectedBlockIDs: [UUID] = []

    public init(groupID: UUID) { self.groupID = groupID }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.cueBlockGroups.firstIndex(where: { $0.id == groupID }) else {
            throw CommandError.message("Cue Block Group not found")
        }
        removed = context.project.cueBlockGroups[index]
        removedIndex = index
        affectedBlockIDs = context.project.cueBlocks.filter { $0.cueBlockGroupID == groupID }.map(\.id)
        let affected = Set(affectedBlockIDs)
        context.updateProject {
            $0.cueBlockGroups.remove(at: index)
            for blockIndex in $0.cueBlocks.indices where affected.contains($0.cueBlocks[blockIndex].id) {
                $0.cueBlocks[blockIndex].cueBlockGroupID = nil
            }
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        let affected = Set(affectedBlockIDs)
        context.updateProject {
            $0.cueBlockGroups.insert(removed, at: min(removedIndex, $0.cueBlockGroups.count))
            for blockIndex in $0.cueBlocks.indices where affected.contains($0.cueBlocks[blockIndex].id) {
                $0.cueBlocks[blockIndex].cueBlockGroupID = removed.id
            }
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class MoveCueBlockToGroupCommand: Command {
    public let name = "Move Cue Block to Group"
    private let cueBlockID: UUID
    private let destinationGroupID: UUID?
    private var previousGroupID: UUID?

    public init(cueBlockID: UUID, destinationGroupID: UUID?) {
        self.cueBlockID = cueBlockID
        self.destinationGroupID = destinationGroupID
    }

    public func perform(context: CommandContext) throws {
        guard let index = context.project.cueBlocks.firstIndex(where: { $0.id == cueBlockID }) else {
            throw CommandError.message("Cue Block not found")
        }
        if let destinationGroupID,
           !context.project.cueBlockGroups.contains(where: { $0.id == destinationGroupID }) {
            throw CommandError.message("Cue Block Group not found")
        }
        previousGroupID = context.project.cueBlocks[index].cueBlockGroupID
        context.updateProject {
            $0.cueBlocks[index].cueBlockGroupID = destinationGroupID
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let index = context.project.cueBlocks.firstIndex(where: { $0.id == cueBlockID }) else { return }
        context.updateProject {
            $0.cueBlocks[index].cueBlockGroupID = previousGroupID
            $0.metadata.modifiedAt = Date()
        }
    }
}

// MARK: - Cue Block library

@MainActor
public final class AddCueBlockCommand: Command {
    public let name = "Add Cue Block"
    private let cueBlock: CueBlock

    public init(cueBlock: CueBlock) {
        self.cueBlock = cueBlock
    }

    public func perform(context: CommandContext) throws {
        if context.project.cueBlocks.contains(where: { $0.id == cueBlock.id }) {
            throw CommandError.message("Cue Block already exists")
        }
        context.updateProject {
            $0.cueBlocks.append(cueBlock)
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        context.updateProject {
            $0.cueBlocks.removeAll { $0.id == cueBlock.id }
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpdateCueBlockCommand: Command {
    public let name = "Update Cue Block"
    private let cueBlock: CueBlock
    private var previous: CueBlock?

    public init(cueBlock: CueBlock) {
        self.cueBlock = cueBlock
    }

    public func perform(context: CommandContext) throws {
        guard let i = context.project.cueBlocks.firstIndex(where: { $0.id == cueBlock.id }) else {
            throw CommandError.message("Cue Block not found")
        }
        previous = context.project.cueBlocks[i]
        context.updateProject {
            $0.cueBlocks[i] = cueBlock
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previous,
              let i = context.project.cueBlocks.firstIndex(where: { $0.id == previous.id })
        else { return }
        context.updateProject {
            $0.cueBlocks[i] = previous
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveCueBlockCommand: Command {
    public let name = "Remove Cue Block"
    private let cueBlockID: UUID
    private var removed: CueBlock?
    private var removedIndex: Int?

    public init(cueBlockID: UUID) {
        self.cueBlockID = cueBlockID
    }

    public func perform(context: CommandContext) throws {
        guard let i = context.project.cueBlocks.firstIndex(where: { $0.id == cueBlockID }) else {
            throw CommandError.message("Cue Block not found")
        }
        removed = context.project.cueBlocks[i]
        removedIndex = i
        // Leave cue references intact (broken refs are validated/resolved safely).
        context.updateProject {
            $0.cueBlocks.remove(at: i)
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        context.updateProject {
            let idx = min(removedIndex, $0.cueBlocks.count)
            $0.cueBlocks.insert(removed, at: idx)
            $0.metadata.modifiedAt = Date()
        }
    }
}

// MARK: - Cue Block references on cues

@MainActor
public final class AddCueBlockReferenceCommand: Command {
    public let name = "Add Cue Block Reference"
    private let listID: UUID
    private let cueID: UUID
    /// Stable identity: constructed once so undo/redo preserves the same reference id.
    private let reference: CueBlockReference

    public init(listID: UUID, cueID: UUID, reference: CueBlockReference) {
        self.listID = listID
        self.cueID = cueID
        self.reference = reference
    }

    public convenience init(listID: UUID, cueID: UUID, cueBlockID: UUID, enabled: Bool = true) {
        self.init(
            listID: listID,
            cueID: cueID,
            reference: CueBlockReference(cueBlockID: cueBlockID, enabled: enabled)
        )
    }

    public var referenceID: UUID { reference.id }

    public func perform(context: CommandContext) throws {
        guard context.project.cueBlocks.contains(where: { $0.id == reference.cueBlockID }) else {
            throw CommandError.message("Cue Block not found")
        }
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        guard let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID }) else {
            throw CommandError.message("Cue not found")
        }
        let cue = context.project.cueLists[listIndex].cues[cueIndex]
        if cue.cueBlockRefs.contains(where: { $0.id == reference.id }) {
            throw CommandError.message("Cue Block reference id already exists on cue")
        }
        if cue.cueBlockRefs.contains(where: { $0.cueBlockID == reference.cueBlockID }) {
            throw CommandError.message("Cue already references this Cue Block")
        }
        context.updateProject {
            $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs.append(reference)
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }),
              let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID })
        else { return }
        context.updateProject {
            $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs.removeAll { $0.id == reference.id }
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveCueBlockReferenceCommand: Command {
    public let name = "Remove Cue Block Reference"
    private let listID: UUID
    private let cueID: UUID
    private let referenceID: UUID
    private var removed: CueBlockReference?
    private var removedIndex: Int?

    public init(listID: UUID, cueID: UUID, referenceID: UUID) {
        self.listID = listID
        self.cueID = cueID
        self.referenceID = referenceID
    }

    public func perform(context: CommandContext) throws {
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        guard let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID }) else {
            throw CommandError.message("Cue not found")
        }
        let refs = context.project.cueLists[listIndex].cues[cueIndex].cueBlockRefs
        guard let i = refs.firstIndex(where: { $0.id == referenceID }) else {
            throw CommandError.message("Cue Block reference not found")
        }
        removed = refs[i]
        removedIndex = i
        context.updateProject {
            $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs.remove(at: i)
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex,
              let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }),
              let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID })
        else { return }
        context.updateProject {
            var refs = $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs
            let idx = min(removedIndex, refs.count)
            refs.insert(removed, at: idx)
            $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs = refs
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class MoveCueBlockReferenceCommand: Command {
    public let name = "Move Cue Block Reference"
    private let listID: UUID
    private let cueID: UUID
    private let referenceID: UUID
    private let toIndex: Int
    private var fromIndex: Int?

    public init(listID: UUID, cueID: UUID, referenceID: UUID, toIndex: Int) {
        self.listID = listID
        self.cueID = cueID
        self.referenceID = referenceID
        self.toIndex = toIndex
    }

    public func perform(context: CommandContext) throws {
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        guard let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID }) else {
            throw CommandError.message("Cue not found")
        }
        let refs = context.project.cueLists[listIndex].cues[cueIndex].cueBlockRefs
        guard let from = refs.firstIndex(where: { $0.id == referenceID }) else {
            throw CommandError.message("Cue Block reference not found")
        }
        fromIndex = from
        // Match ReorderCueCommand: clamp desired final index.
        let dest = min(max(0, toIndex), max(0, refs.count - 1))
        guard dest != from else { return }
        context.updateProject {
            var list = $0.cueLists[listIndex]
            var cue = list.cues[cueIndex]
            let ref = cue.cueBlockRefs.remove(at: from)
            cue.cueBlockRefs.insert(ref, at: dest)
            list.cues[cueIndex] = cue
            $0.cueLists[listIndex] = list
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let fromIndex,
              let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }),
              let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID }),
              let current = context.project.cueLists[listIndex].cues[cueIndex].cueBlockRefs.firstIndex(where: { $0.id == referenceID })
        else { return }
        context.updateProject {
            var list = $0.cueLists[listIndex]
            var cue = list.cues[cueIndex]
            let ref = cue.cueBlockRefs.remove(at: current)
            let insertAt = min(fromIndex, cue.cueBlockRefs.count)
            cue.cueBlockRefs.insert(ref, at: insertAt)
            list.cues[cueIndex] = cue
            $0.cueLists[listIndex] = list
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class SetCueBlockReferenceEnabledCommand: Command {
    public let name = "Set Cue Block Reference Enabled"
    private let listID: UUID
    private let cueID: UUID
    private let referenceID: UUID
    private let enabled: Bool
    private var previousEnabled: Bool?

    public init(listID: UUID, cueID: UUID, referenceID: UUID, enabled: Bool) {
        self.listID = listID
        self.cueID = cueID
        self.referenceID = referenceID
        self.enabled = enabled
    }

    public func perform(context: CommandContext) throws {
        guard let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }) else {
            throw CommandError.message("Cue list not found")
        }
        guard let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID }) else {
            throw CommandError.message("Cue not found")
        }
        guard let refIndex = context.project.cueLists[listIndex].cues[cueIndex].cueBlockRefs
            .firstIndex(where: { $0.id == referenceID })
        else {
            throw CommandError.message("Cue Block reference not found")
        }
        previousEnabled = context.project.cueLists[listIndex].cues[cueIndex].cueBlockRefs[refIndex].enabled
        context.updateProject {
            $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs[refIndex].enabled = enabled
            $0.metadata.modifiedAt = Date()
        }
    }

    public func undo(context: CommandContext) throws {
        guard let previousEnabled,
              let listIndex = context.project.cueLists.firstIndex(where: { $0.id == listID }),
              let cueIndex = context.project.cueLists[listIndex].cues.firstIndex(where: { $0.id == cueID }),
              let refIndex = context.project.cueLists[listIndex].cues[cueIndex].cueBlockRefs
                .firstIndex(where: { $0.id == referenceID })
        else { return }
        context.updateProject {
            $0.cueLists[listIndex].cues[cueIndex].cueBlockRefs[refIndex].enabled = previousEnabled
            $0.metadata.modifiedAt = Date()
        }
    }
}
