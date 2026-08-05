import AuroraModel
import Foundation

/// Resolves sparse cue levels with palette expansion and tracking into an `ActiveLook`.
public enum CueResolver {
    public static func resolveLook(cues: [Cue], index: Int, project: ShowProject) -> ActiveLook {
        guard index >= 0, index < cues.count else { return .empty }
        let target = cues[index]

        if target.tracking == .cueOnly {
            let resolved = PaletteResolver.resolve(levels: target.levels, project: project, cueID: target.id)
            return LookMath.activeLook(from: resolved.levels)
        }

        var look = ActiveLook()
        for i in 0...index {
            let cue = cues[i]
            if cue.tracking == .cueOnly, i != index { continue }
            let resolved = PaletteResolver.resolve(levels: cue.levels, project: project, cueID: cue.id)
            LookMath.mergeLevels(into: &look, levels: resolved.levels)
        }
        return look
    }

    public static func resolveLook(list: CueList, index: Int, project: ShowProject) -> ActiveLook {
        resolveLook(cues: list.cues, index: index, project: project)
    }

    /// Backward-compatible helper when project context is unavailable (literals only).
    public static func resolveLook(cues: [Cue], index: Int) -> ActiveLook {
        resolveLook(cues: cues, index: index, project: .empty())
    }
}
