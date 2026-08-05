import AuroraModel
import Foundation

/// Resolves sparse cue levels with palette expansion and tracking into an `ActiveLook`.
///
/// Tracking semantics (P0-6 / system design §7.4):
/// - **track:** accumulate attributes from tracking cues up to index (intermediate cue-only skipped).
/// - **cue-only target:** previous stage/tracked look + this cue’s sparse attributes (does not wipe
///   unspecified attributes to home/default).
public enum CueResolver {
    /// Resolves the look at `index`. For cue-only targets, uses `priorLook` if provided, otherwise
    /// the tracked look immediately before this cue.
    public static func resolveLook(
        cues: [Cue],
        index: Int,
        project: ShowProject,
        priorLook: ActiveLook? = nil
    ) -> ActiveLook {
        guard index >= 0, index < cues.count else { return .empty }
        let target = cues[index]

        if target.tracking == .cueOnly {
            let base = priorLook ?? trackedLook(cues: cues, beforeIndex: index, project: project)
            let resolved = PaletteResolver.resolve(levels: target.levels, project: project, cueID: target.id)
            var look = base
            LookMath.mergeLevels(into: &look, levels: resolved.levels)
            return look
        }

        return trackedLook(cues: cues, throughIndex: index, project: project)
    }

    public static func resolveLook(list: CueList, index: Int, project: ShowProject, priorLook: ActiveLook? = nil) -> ActiveLook {
        resolveLook(cues: list.cues, index: index, project: project, priorLook: priorLook)
    }

    /// Backward-compatible helper when project context is unavailable (literals only).
    public static func resolveLook(cues: [Cue], index: Int) -> ActiveLook {
        resolveLook(cues: cues, index: index, project: .empty())
    }

    /// Tracked accumulation through `throughIndex` (inclusive), skipping intermediate cue-only.
    public static func trackedLook(cues: [Cue], throughIndex: Int, project: ShowProject) -> ActiveLook {
        guard throughIndex >= 0, throughIndex < cues.count else { return .empty }
        var look = ActiveLook()
        for i in 0...throughIndex {
            let cue = cues[i]
            if cue.tracking == .cueOnly, i != throughIndex { continue }
            if cue.tracking == .cueOnly, i == throughIndex {
                // Target itself is cue-only — handled by resolveLook; tracked path shouldn't land here for target.
                let resolved = PaletteResolver.resolve(levels: cue.levels, project: project, cueID: cue.id)
                LookMath.mergeLevels(into: &look, levels: resolved.levels)
                continue
            }
            let resolved = PaletteResolver.resolve(levels: cue.levels, project: project, cueID: cue.id)
            LookMath.mergeLevels(into: &look, levels: resolved.levels)
        }
        return look
    }

    /// Tracked look of cues strictly before `index` (for cue-only base).
    public static func trackedLook(cues: [Cue], beforeIndex: Int, project: ShowProject) -> ActiveLook {
        guard beforeIndex > 0 else { return .empty }
        return trackedLook(cues: cues, throughIndex: beforeIndex - 1, project: project)
    }
}
