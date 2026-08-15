import Foundation

// MARK: - Stage imported media (C4.5)

/// Project-portable Stage image media: package-relative paths under `media/stage/`.
///
/// Unsaved projects stage bytes under Application Support; on save they are embedded
/// into the `.aurora` package. Legacy absolute App Support paths migrate on save.
public enum StageMediaSupport {
    public static let packageStageMediaDirectory = "media/stage"
    public static let stagingFolderName = "Aurora/stage-media-pending"
    public static let legacyAppSupportFolderName = "Aurora/stage-media"

    /// Create a new package-relative media path for an imported Stage image.
    public static func makeRelativeStageMediaPath(fileExtension: String) -> String {
        let ext = fileExtension.isEmpty ? "png" : fileExtension.lowercased()
        return "\(packageStageMediaDirectory)/\(UUID().uuidString).\(ext)"
    }

    public static func isAbsoluteFilePath(_ ref: String) -> Bool {
        ref.hasPrefix("/") || (ref.count > 2 && ref[ref.index(ref.startIndex, offsetBy: 1)] == ":")
    }

    public static func isPackageRelativeStageMedia(_ ref: String) -> Bool {
        let n = normalizeRelativePath(ref)
        return n.hasPrefix("media/")
    }

    /// Reject `..` and absolute escape attempts. Returns nil if unsafe.
    public static func validatedPackageRelativePath(_ ref: String) -> String? {
        let n = normalizeRelativePath(ref)
        guard !n.isEmpty, !n.hasPrefix("/"), !n.contains("://") else { return nil }
        let parts = n.split(separator: "/")
        guard !parts.contains("..") else { return nil }
        guard n.hasPrefix("media/") else { return nil }
        return n
    }

    public static func normalizeRelativePath(_ ref: String) -> String {
        var s = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("./") { s = String(s.dropFirst(2)) }
        return s
    }

    public static func stagingRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(stagingFolderName, isDirectory: true)
    }

    public static func stagingFileURL(forRelativePath relativePath: String) -> URL? {
        guard let safe = validatedPackageRelativePath(relativePath) else { return nil }
        // Flatten to filename under staging root (avoid nested path surprises).
        let name = (safe as NSString).lastPathComponent
        return stagingRootURL().appendingPathComponent(name, isDirectory: false)
    }

    /// Resolve a Stage `mediaRef` to a readable file URL if possible.
    public static func resolveFileURL(
        mediaRef: String,
        packageRoot: URL?
    ) -> URL? {
        let fm = FileManager.default
        if isAbsoluteFilePath(mediaRef) {
            let url = URL(fileURLWithPath: mediaRef)
            if fm.fileExists(atPath: url.path) { return url }
            // Fall through: try same filename inside package media/stage
            if let packageRoot {
                let name = url.lastPathComponent
                let candidate = packageRoot
                    .appendingPathComponent(packageStageMediaDirectory, isDirectory: true)
                    .appendingPathComponent(name)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }
        guard let safe = validatedPackageRelativePath(mediaRef) else { return nil }
        if let packageRoot {
            let inPackage = packageRoot.appendingPathComponent(safe)
            // Ensure resolved path stays under package root
            let packagePath = packageRoot.standardizedFileURL.path
            let resolvedPath = inPackage.standardizedFileURL.path
            if resolvedPath.hasPrefix(packagePath), fm.fileExists(atPath: resolvedPath) {
                return inPackage
            }
        }
        if let staged = stagingFileURL(forRelativePath: safe), fm.fileExists(atPath: staged.path) {
            return staged
        }
        return nil
    }

    /// Copy an imported user file into staging (and optionally directly into an open package).
    /// Returns package-relative `media/stage/…` path.
    @discardableResult
    public static func importImage(
        from sourceURL: URL,
        intoOpenPackage packageRoot: URL?
    ) throws -> (relativePath: String, absoluteFileURL: URL) {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let relative = makeRelativeStageMediaPath(fileExtension: ext)
        let fileName = (relative as NSString).lastPathComponent

        if let packageRoot {
            let stageDir = packageRoot.appendingPathComponent(packageStageMediaDirectory, isDirectory: true)
            try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)
            let dest = stageDir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: sourceURL, to: dest)
            // Mirror to staging so unsaved edits after Save As edge cases still resolve.
            let staging = stagingRootURL()
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let staged = staging.appendingPathComponent(fileName)
            if !fm.fileExists(atPath: staged.path) {
                try? fm.copyItem(at: dest, to: staged)
            }
            return (relative, dest)
        } else {
            let staging = stagingRootURL()
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let dest = staging.appendingPathComponent(fileName)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: sourceURL, to: dest)
            return (relative, dest)
        }
    }

    /// Ensure all Stage imported images are present under `packageRoot/media/stage/` and
    /// rewrite absolute/legacy `mediaRef` values to package-relative form.
    public static func materializeStageMedia(
        into packageRoot: URL,
        project: inout ShowProject
    ) throws {
        let fm = FileManager.default
        let stageDir = packageRoot.appendingPathComponent(packageStageMediaDirectory, isDirectory: true)
        try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)

        var assetsByPath = Dictionary(uniqueKeysWithValues: project.mediaAssets.map { ($0.relativePath, $0) })
        var changed = false

        for i in project.stageLayout.objects.indices {
            guard project.stageLayout.objects[i].kind == .importedImage else { continue }
            guard let ref = project.stageLayout.objects[i].mediaRef, !ref.isEmpty else { continue }

            let fileName: String
            let sourceURL: URL?

            if isAbsoluteFilePath(ref) {
                let abs = URL(fileURLWithPath: ref)
                fileName = abs.lastPathComponent
                sourceURL = fm.fileExists(atPath: abs.path) ? abs : nil
            } else if let safe = validatedPackageRelativePath(ref) {
                fileName = (safe as NSString).lastPathComponent
                if let existing = resolveFileURL(mediaRef: safe, packageRoot: packageRoot) {
                    sourceURL = existing
                } else {
                    sourceURL = nil
                }
            } else {
                continue
            }

            let dest = stageDir.appendingPathComponent(fileName)
            let relative = "\(packageStageMediaDirectory)/\(fileName)"

            if let sourceURL, !fm.fileExists(atPath: dest.path) || sourceURL.standardizedFileURL != dest.standardizedFileURL {
                if sourceURL.standardizedFileURL != dest.standardizedFileURL {
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    // If source is already dest, skip
                    if sourceURL.path != dest.path {
                        try fm.copyItem(at: sourceURL, to: dest)
                    }
                }
            }

            if project.stageLayout.objects[i].mediaRef != relative {
                project.stageLayout.objects[i].mediaRef = relative
                changed = true
            }

            if assetsByPath[relative] == nil {
                let asset = MediaAssetRef(
                    name: project.stageLayout.objects[i].name.isEmpty
                        ? fileName
                        : project.stageLayout.objects[i].name,
                    relativePath: relative,
                    notes: "Stage imported image"
                )
                project.mediaAssets.append(asset)
                assetsByPath[relative] = asset
                changed = true
            }

            // Keep staging mirror for open-session resolution after save.
            if fm.fileExists(atPath: dest.path) {
                let staging = stagingRootURL()
                try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
                let staged = staging.appendingPathComponent(fileName)
                if !fm.fileExists(atPath: staged.path) {
                    try? fm.copyItem(at: dest, to: staged)
                }
            }

            _ = changed
        }
    }
}
