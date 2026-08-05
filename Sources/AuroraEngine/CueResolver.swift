import AuroraModel
import Foundation

/// Resolves sparse cue levels with tracking into an `ActiveLook`.
public enum CueResolver {
    /// Builds the look at `index` in `cues` (0-based). Empty if index out of range.
    public static func resolveLook(cues: [Cue], index: Int) -> ActiveLook {
        guard index >= 0, index < cues.count else { return .empty }
        let target = cues[index]

        if target.tracking == .cueOnly {
            return LookMath.activeLook(from: target.levels)
        }

        var look = ActiveLook()
        for i in 0...index {
            let cue = cues[i]
            // Intermediate cue-only cues do not contribute to tracked state.
            if cue.tracking == .cueOnly, i != index { continue }
            LookMath.mergeLevels(into: &look, levels: cue.levels)
        }
        return look
    }

    public static func resolveLook(list: CueList, index: Int) -> ActiveLook {
        resolveLook(cues: list.cues, index: index)
    }
}
