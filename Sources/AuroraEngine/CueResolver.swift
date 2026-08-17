import AuroraModel
import Foundation

/// Result of resolving a cue look with structured diagnostics (Cue Blocks + palette issues).
public struct CueResolutionResult: Equatable, Sendable {
    public var look: ActiveLook
    public var issues: [CueBlockResolutionIssue]

    public init(look: ActiveLook = .empty, issues: [CueBlockResolutionIssue] = []) {
        self.look = look
        self.issues = issues
    }
}

/// Resolves sparse cue levels with Cue Block composition, palette expansion, and tracking into an `ActiveLook`.
///
/// Tracking semantics (P0-6 / system design §7.4):
/// - **track:** accumulate attributes from tracking cues up to index (intermediate cue-only skipped).
/// - **cue-only target:** previous stage/tracked look + this cue’s sparse attributes (does not wipe
///   unspecified attributes to home/default).
///
/// Merge precedence within a cue:
/// `earlier Cue Block < later Cue Block < cue palette refs < cue literals`
///
/// Capability filtering applies only to Cue Block contributions (legacy palette/literal path unchanged).
public enum CueResolver {
    // MARK: - Compatibility wrappers (ActiveLook only)

    /// Resolves the look at `index`. For cue-only targets, uses `priorLook` if provided, otherwise
    /// the tracked look immediately before this cue.
    public static func resolveLook(
        cues: [Cue],
        index: Int,
        project: ShowProject,
        priorLook: ActiveLook? = nil
    ) -> ActiveLook {
        resolveLookDetailed(cues: cues, index: index, project: project, priorLook: priorLook).look
    }

    public static func resolveLook(list: CueList, index: Int, project: ShowProject, priorLook: ActiveLook? = nil) -> ActiveLook {
        resolveLook(cues: list.cues, index: index, project: project, priorLook: priorLook)
    }

    /// Backward-compatible helper when project context is unavailable (literals only).
    public static func resolveLook(cues: [Cue], index: Int) -> ActiveLook {
        resolveLook(cues: cues, index: index, project: .empty())
    }

    public static func trackedLook(cues: [Cue], throughIndex: Int, project: ShowProject) -> ActiveLook {
        trackedLookDetailed(cues: cues, throughIndex: throughIndex, project: project).look
    }

    public static func trackedLook(cues: [Cue], beforeIndex: Int, project: ShowProject) -> ActiveLook {
        trackedLookDetailed(cues: cues, beforeIndex: beforeIndex, project: project).look
    }

    // MARK: - Issue-aware entry points

    public static func resolveLookDetailed(
        cues: [Cue],
        index: Int,
        project: ShowProject,
        priorLook: ActiveLook? = nil
    ) -> CueResolutionResult {
        guard index >= 0, index < cues.count else { return CueResolutionResult() }
        let target = cues[index]

        if target.tracking == .cueOnly {
            let baseResult: CueResolutionResult
            if let priorLook {
                baseResult = CueResolutionResult(look: priorLook, issues: [])
            } else {
                baseResult = trackedLookDetailed(cues: cues, beforeIndex: index, project: project)
            }
            let composed = composeCue(target, project: project)
            var look = baseResult.look
            LookMath.mergeLevels(into: &look, levels: composed.levels)
            return CueResolutionResult(
                look: look,
                issues: baseResult.issues + composed.issues
            )
        }

        return trackedLookDetailed(cues: cues, throughIndex: index, project: project)
    }

    public static func resolveLookDetailed(
        list: CueList,
        index: Int,
        project: ShowProject,
        priorLook: ActiveLook? = nil
    ) -> CueResolutionResult {
        resolveLookDetailed(cues: list.cues, index: index, project: project, priorLook: priorLook)
    }

    /// Tracked accumulation through `throughIndex` (inclusive), skipping intermediate cue-only.
    public static func trackedLookDetailed(
        cues: [Cue],
        throughIndex: Int,
        project: ShowProject
    ) -> CueResolutionResult {
        guard throughIndex >= 0, throughIndex < cues.count else { return CueResolutionResult() }
        var look = ActiveLook()
        var issues: [CueBlockResolutionIssue] = []
        for i in 0...throughIndex {
            let cue = cues[i]
            if cue.tracking == .cueOnly, i != throughIndex { continue }
            let composed = composeCue(cue, project: project)
            LookMath.mergeLevels(into: &look, levels: composed.levels)
            issues.append(contentsOf: composed.issues)
        }
        return CueResolutionResult(look: look, issues: issues)
    }

    /// Tracked look of cues strictly before `index` (for cue-only base).
    public static func trackedLookDetailed(
        cues: [Cue],
        beforeIndex: Int,
        project: ShowProject
    ) -> CueResolutionResult {
        guard beforeIndex > 0 else { return CueResolutionResult() }
        return trackedLookDetailed(cues: cues, throughIndex: beforeIndex - 1, project: project)
    }

    // MARK: - Composition

    /// Shared path for track and cue-only so composition cannot diverge.
    private static func composeCue(_ cue: Cue, project: ShowProject) -> CueBlockResolver.Result {
        // When there are no Cue Block refs, still run through CueBlockResolver so palette
        // issues are threaded; capability filter is a no-op on empty block contributions.
        CueBlockResolver.resolveCueLevels(cue: cue, project: project)
    }
}
