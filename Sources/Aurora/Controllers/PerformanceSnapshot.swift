import AuroraEngine
import AuroraModel
import Foundation

// Re-export presentation type used by shell views.
typealias PerformanceCueSummary = AuroraEngine.PerformanceCueSummary

/// Shared Mac Perform + remote presentation state (Stage C / P1-15 / UI-GATE-4).
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
    /// Live playback cue id when known (for Inspector CURRENT).
    var playbackCueID: UUID?
    var playbackPhase: String
    var song: SongPerformanceSnapshot
    var validationIssueCount: Int
    var outputStatusLine: String
    /// Total channels with level > 0 across **all** universes.
    var activeChannelCount: Int
    /// Number of universes that currently have at least one active channel.
    var activeUniverseCount: Int
    /// Semantically resolved current / next cue (never invent from index+1 alone).
    var currentCue: PerformanceCueSummary
    var nextCue: PerformanceCueSummary

    static let empty = PerformanceSnapshot(
        showName: "Untitled",
        isDirty: false,
        engineRunning: false,
        frameIndex: 0,
        frameRateHz: 40,
        cueIndex: -1,
        cueName: "",
        cueListID: nil,
        playbackCueID: nil,
        playbackPhase: "idle",
        song: .empty,
        validationIssueCount: 0,
        outputStatusLine: "Output: Null",
        activeChannelCount: 0,
        activeUniverseCount: 0,
        currentCue: .empty,
        nextCue: .empty
    )

    /// Sum of channels with level > 0 across every universe (UI-GATE-4).
    static func activeChannelTotals(universeLevels: [UInt16: [UInt8]]) -> (channels: Int, universes: Int) {
        var channels = 0
        var universes = 0
        for levels in universeLevels.values {
            let active = levels.filter { $0 > 0 }.count
            if active > 0 {
                universes += 1
                channels += active
            }
        }
        return (channels, universes)
    }

    static func build(
        project: ShowProject,
        isDirty: Bool,
        engineSnap: EngineFrameSnapshot,
        song: SongPerformanceSnapshot,
        outputStatusLine: String
    ) -> PerformanceSnapshot {
        let pb = engineSnap.playback
        let songCtx = SongCueResolveContext(
            songID: song.songID,
            entryIndex: song.entryIndex,
            entryCount: song.entryCount,
            currentEntryLabel: song.currentEntryLabel,
            nextEntryLabel: song.nextEntryLabel
        )
        let (current, next) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: pb,
            song: songCtx
        )

        var cueName = current.name
        if cueName.isEmpty {
            cueName = pb.cueName
        }

        let totals = activeChannelTotals(universeLevels: engineSnap.universeLevels)
        return PerformanceSnapshot(
            showName: project.metadata.name,
            isDirty: isDirty,
            engineRunning: engineSnap.isRunning,
            frameIndex: engineSnap.frameIndex,
            frameRateHz: engineSnap.frameRateHz,
            cueIndex: pb.cueIndex,
            cueName: cueName,
            cueListID: pb.listID ?? current.listID,
            playbackCueID: pb.cueID ?? current.cueID,
            playbackPhase: pb.phase.rawValue,
            song: song,
            validationIssueCount: engineSnap.resolutionIssues.count,
            outputStatusLine: outputStatusLine,
            activeChannelCount: totals.channels,
            activeUniverseCount: totals.universes,
            currentCue: current,
            nextCue: next
        )
    }
}

/// Workspace presentation mode (Build vs Perform).
enum WorkspaceMode: String, Sendable, CaseIterable, Equatable {
    case build
    case perform
}
