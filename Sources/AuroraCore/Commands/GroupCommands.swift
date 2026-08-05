import AuroraModel
import Foundation

@MainActor
public final class AddGroupCommand: Command {
    public let name = "Add Group"
    private let group: Group
    public init(group: Group) { self.group = group }
    public func perform(context: CommandContext) throws {
        context.updateProject {
            $0.groups.append(group)
            GroupMembership.syncFixtureGroupIds(&$0)
            $0.metadata.modifiedAt = Date()
        }
    }
    public func undo(context: CommandContext) throws {
        context.updateProject {
            $0.groups.removeAll { $0.id == group.id }
            GroupMembership.syncFixtureGroupIds(&$0)
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class RemoveGroupCommand: Command {
    public let name = "Remove Group"
    private let groupID: UUID
    private var removed: Group?
    public init(groupID: UUID) { self.groupID = groupID }
    public func perform(context: CommandContext) throws {
        guard let g = context.project.groups.first(where: { $0.id == groupID }) else {
            throw CommandError.message("Group not found")
        }
        removed = g
        context.updateProject {
            $0.groups.removeAll { $0.id == groupID }
            GroupMembership.syncFixtureGroupIds(&$0)
            $0.metadata.modifiedAt = Date()
        }
    }
    public func undo(context: CommandContext) throws {
        guard let removed else { return }
        context.updateProject {
            $0.groups.append(removed)
            GroupMembership.syncFixtureGroupIds(&$0)
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpdateGroupCommand: Command {
    public let name = "Update Group"
    private let group: Group
    private var previous: Group?
    public init(group: Group) { self.group = group }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.groups.firstIndex(where: { $0.id == group.id }) else {
            throw CommandError.message("Group not found")
        }
        previous = context.project.groups[i]
        context.updateProject {
            $0.groups[i] = group
            GroupMembership.syncFixtureGroupIds(&$0)
            $0.metadata.modifiedAt = Date()
        }
    }
    public func undo(context: CommandContext) throws {
        guard let previous, let i = context.project.groups.firstIndex(where: { $0.id == previous.id }) else { return }
        context.updateProject {
            $0.groups[i] = previous
            GroupMembership.syncFixtureGroupIds(&$0)
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class AddPaletteCommand: Command {
    public let name = "Add Palette"
    private let palette: Palette
    public init(palette: Palette) { self.palette = palette }
    public func perform(context: CommandContext) throws {
        context.updateProject { $0.palettes.append(palette); $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        context.updateProject { $0.palettes.removeAll { $0.id == palette.id }; $0.metadata.modifiedAt = Date() }
    }
}

@MainActor
public final class RemovePaletteCommand: Command {
    public let name = "Remove Palette"
    private let paletteID: UUID
    private var removed: Palette?
    private var removedIndex: Int?
    public init(paletteID: UUID) { self.paletteID = paletteID }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.palettes.firstIndex(where: { $0.id == paletteID }) else {
            throw CommandError.message("Palette not found")
        }
        removed = context.project.palettes[i]
        removedIndex = i
        context.updateProject { $0.palettes.remove(at: i); $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        context.updateProject {
            let idx = min(removedIndex, $0.palettes.count)
            $0.palettes.insert(removed, at: idx)
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpdatePaletteCommand: Command {
    public let name = "Update Palette"
    private let palette: Palette
    private var previous: Palette?
    public init(palette: Palette) { self.palette = palette }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.palettes.firstIndex(where: { $0.id == palette.id }) else {
            throw CommandError.message("Palette not found")
        }
        previous = context.project.palettes[i]
        context.updateProject { $0.palettes[i] = palette; $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        guard let previous, let i = context.project.palettes.firstIndex(where: { $0.id == previous.id }) else { return }
        context.updateProject { $0.palettes[i] = previous; $0.metadata.modifiedAt = Date() }
    }
}

@MainActor
public final class AddPresetCommand: Command {
    public let name = "Add Preset"
    private let preset: Preset
    public init(preset: Preset) { self.preset = preset }
    public func perform(context: CommandContext) throws {
        context.updateProject { $0.presets.append(preset); $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        context.updateProject { $0.presets.removeAll { $0.id == preset.id }; $0.metadata.modifiedAt = Date() }
    }
}

@MainActor
public final class RemovePresetCommand: Command {
    public let name = "Remove Preset"
    private let presetID: UUID
    private var removed: Preset?
    private var removedIndex: Int?
    public init(presetID: UUID) { self.presetID = presetID }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.presets.firstIndex(where: { $0.id == presetID }) else {
            throw CommandError.message("Preset not found")
        }
        removed = context.project.presets[i]
        removedIndex = i
        context.updateProject { $0.presets.remove(at: i); $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        context.updateProject {
            let idx = min(removedIndex, $0.presets.count)
            $0.presets.insert(removed, at: idx)
            $0.metadata.modifiedAt = Date()
        }
    }
}

@MainActor
public final class UpdatePresetCommand: Command {
    public let name = "Update Preset"
    private let preset: Preset
    private var previous: Preset?
    public init(preset: Preset) { self.preset = preset }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.presets.firstIndex(where: { $0.id == preset.id }) else {
            throw CommandError.message("Preset not found")
        }
        previous = context.project.presets[i]
        context.updateProject { $0.presets[i] = preset; $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        guard let previous, let i = context.project.presets.firstIndex(where: { $0.id == previous.id }) else { return }
        context.updateProject { $0.presets[i] = previous; $0.metadata.modifiedAt = Date() }
    }
}

@MainActor
public final class AddSongCommand: Command {
    public let name = "Add Song"
    private let song: Song
    public init(song: Song) { self.song = song }
    public func perform(context: CommandContext) throws {
        context.updateProject { $0.songs.append(song); $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        context.updateProject { $0.songs.removeAll { $0.id == song.id }; $0.metadata.modifiedAt = Date() }
    }
}

@MainActor
public final class UpdateSongCommand: Command {
    public let name = "Update Song"
    private let song: Song
    private var previous: Song?
    public init(song: Song) { self.song = song }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.songs.firstIndex(where: { $0.id == song.id }) else {
            throw CommandError.message("Song not found")
        }
        previous = context.project.songs[i]
        context.updateProject { $0.songs[i] = song; $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        guard let previous, let i = context.project.songs.firstIndex(where: { $0.id == previous.id }) else { return }
        context.updateProject { $0.songs[i] = previous; $0.metadata.modifiedAt = Date() }
    }
}

@MainActor
public final class RemoveSongCommand: Command {
    public let name = "Remove Song"
    private let songID: UUID
    private var removed: Song?
    private var removedIndex: Int?
    public init(songID: UUID) { self.songID = songID }
    public func perform(context: CommandContext) throws {
        guard let i = context.project.songs.firstIndex(where: { $0.id == songID }) else {
            throw CommandError.message("Song not found")
        }
        removed = context.project.songs[i]
        removedIndex = i
        context.updateProject { $0.songs.remove(at: i); $0.metadata.modifiedAt = Date() }
    }
    public func undo(context: CommandContext) throws {
        guard let removed, let removedIndex else { return }
        context.updateProject {
            let idx = min(removedIndex, $0.songs.count)
            $0.songs.insert(removed, at: idx)
            $0.metadata.modifiedAt = Date()
        }
    }
}
