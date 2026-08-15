import AuroraModel
import Foundation

/// Registers a package-relative media asset on the show (C4.5 Stage imports).
@MainActor
public final class RegisterMediaAssetCommand: Command {
    public let name: String
    private let asset: MediaAssetRef
    private var didInsert = false

    public init(asset: MediaAssetRef, name: String = "Register Media") {
        self.asset = asset
        self.name = name
    }

    public func perform(context: CommandContext) throws {
        if context.project.mediaAssets.contains(where: { $0.id == asset.id || $0.relativePath == asset.relativePath }) {
            didInsert = false
            return
        }
        context.updateProject { project in
            project.mediaAssets.append(asset)
            project.metadata.modifiedAt = Date()
        }
        didInsert = true
    }

    public func undo(context: CommandContext) throws {
        guard didInsert else { return }
        context.updateProject { project in
            project.mediaAssets.removeAll { $0.id == asset.id }
            project.metadata.modifiedAt = Date()
        }
    }
}
