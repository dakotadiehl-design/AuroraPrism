import Foundation

/// Schema migration pipeline (P2-9). Current packages are schema v1.
public enum SchemaMigrationError: Error, Equatable, Sendable {
    case unsupportedVersion(found: Int, supportedMaximum: Int)
    case migrationFailed(String)
}

/// Migrates raw package version numbers toward the current domain model.
public enum SchemaMigration {
    public static var currentVersion: Int { ProjectPackage.currentSchemaVersion }

    /// Migrate an already-decoded project from its `schemaVersion` to current.
    public static func migrate(_ project: ShowProject) throws -> ShowProject {
        var result = project
        var version = result.schemaVersion
        if version <= 0 {
            throw SchemaMigrationError.unsupportedVersion(found: version, supportedMaximum: currentVersion)
        }
        while version < currentVersion {
            result = try migrateStep(result, from: version)
            version += 1
            result.schemaVersion = version
        }
        if version > currentVersion {
            throw SchemaMigrationError.unsupportedVersion(found: version, supportedMaximum: currentVersion)
        }
        return result
    }

    /// Per-version step.
    private static func migrateStep(_ project: ShowProject, from version: Int) throws -> ShowProject {
        switch version {
        case 1:
            // v1 → v2: ensure stage layout exists; fixture generic/cell fields default via decode.
            var next = project
            if next.stageLayout.fixtures.isEmpty && next.stageLayout.scenic.isEmpty {
                next.stageLayout = .empty
            }
            return next
        case 2:
            // v2 → v3: advanced MIDI assets default empty if absent.
            var next = project
            if next.drumProfiles.isEmpty {
                // Seed a GM kit so Electronic Drums scenario has a starting profile.
                next.drumProfiles = [.generalMIDIKit]
            }
            return next
        case 3:
            // v3 → v4: AME document empty; ensure each song has a default Main section.
            // Do NOT synthesize sections from SongEntry.label (labels may mean cue notes only).
            var next = project
            for i in next.songs.indices {
                SongSectionMigrationHelper.ensureDefaultMainSection(&next.songs[i])
            }
            return next
        case 4:
            // v4 → v5: Cue Blocks collection defaults empty; cues without cueBlockRefs already decode [].
            // Do NOT convert palettes or presets into Cue Blocks.
            var next = project
            if next.cueBlocks.isEmpty == false {
                // Preserve any blocks already present (e.g. in-memory upgrades).
            } else {
                next.cueBlocks = []
            }
            return next
        default:
            throw SchemaMigrationError.unsupportedVersion(found: version, supportedMaximum: currentVersion)
        }
    }
}
