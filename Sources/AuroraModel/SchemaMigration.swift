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

    /// Per-version step. v1 is current — identity path only until v2 lands.
    private static func migrateStep(_ project: ShowProject, from version: Int) throws -> ShowProject {
        switch version {
        case 1:
            // Future: 1 → 2 transforms go here.
            return project
        default:
            throw SchemaMigrationError.unsupportedVersion(found: version, supportedMaximum: currentVersion)
        }
    }
}
