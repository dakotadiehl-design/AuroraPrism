import AuroraEngine
import AuroraModel
import Foundation

/// Shared Mac Perform + remote presentation state (Stage C / P1-15).
/// Built on a timer / after transport actions — not every engine frame for SwiftUI.
struct PerformanceSnapshot: Equatable, Sendable {
    var showName: String
    var isDirty: Bool
    var engineRunning: Bool
    var frameIndex: UInt64
    var frameRateHz: Double
    var cueIndex: Int
    var cueName: String
    var cueListID: UUID?
    var playbackPhase: String
    var song: SongPerformanceSnapshot
    var validationIssueCount: Int
    var outputStatusLine: String
    var activeChannelCount: Int

    static let empty = PerformanceSnapshot(
        showName: "Untitled",
        isDirty: false,
        engineRunning: false,
        frameIndex: 0,
        frameRateHz: 40,
        cueIndex: -1,
        cueName: "",
        cueListID: nil,
        playbackPhase: "idle",
        song: .empty,
        validationIssueCount: 0,
        outputStatusLine: "Output: Null",
        activeChannelCount: 0
    )

    static func build(
        project: ShowProject,
        isDirty: Bool,
        engineSnap: EngineFrameSnapshot,
        song: SongPerformanceSnapshot,
        outputStatusLine: String
    ) -> PerformanceSnapshot {
        let pb = engineSnap.playback
        var cueName = pb.cueName
        if cueName.isEmpty, pb.cueIndex >= 0,
           let list = project.cueLists.first(where: { $0.id == pb.listID })
            ?? project.cueLists.first,
           list.cues.indices.contains(pb.cueIndex) {
            cueName = list.cues[pb.cueIndex].name
        }
        let levels = engineSnap.universeLevels.values.first ?? []
        let active = levels.filter { $0 > 0 }.count
        return PerformanceSnapshot(
            showName: project.metadata.name,
            isDirty: isDirty,
            engineRunning: engineSnap.isRunning,
            frameIndex: engineSnap.frameIndex,
            frameRateHz: engineSnap.frameRateHz,
            cueIndex: pb.cueIndex,
            cueName: cueName,
            cueListID: pb.listID,
            playbackPhase: pb.phase.rawValue,
            song: song,
            validationIssueCount: engineSnap.resolutionIssues.count,
            outputStatusLine: outputStatusLine,
            activeChannelCount: active
        )
    }
}

/// Workspace presentation mode (Build vs Perform).
enum WorkspaceMode: String, Sendable, CaseIterable, Equatable {
    case build
    case perform
}
