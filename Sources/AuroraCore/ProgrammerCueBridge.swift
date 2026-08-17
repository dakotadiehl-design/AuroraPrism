import AuroraModel
import Foundation

/// Shared helpers for moving ephemeral Programmer levels into durable cue data.
///
/// Programmer values are engine-ephemeral until recorded/updated into a cue or preset
/// (`docs/UI_BACKEND_CONTRACT.md`). Save of the show package only writes `ShowProject`.
public enum ProgrammerCueBridge {
    /// User decision when Save is requested while the programmer has a look.
    public enum SaveLookDecision: Equatable, Sendable {
        case updateTargetCue
        case recordNewCue
        case saveWithoutLook
        case cancel
    }

    public struct CueTarget: Equatable, Sendable {
        public var listID: UUID
        public var cue: Cue

        public init(listID: UUID, cue: Cue) {
            self.listID = listID
            self.cue = cue
        }
    }

    /// Next display number for a newly recorded cue (array order is still append-only).
    public static func nextDisplayNumber(in list: CueList) -> Decimal {
        let maxNum = list.cues.map(\.number).max() ?? 0
        return maxNum + 1
    }

    /// Prefer playback/selected cue; else first cue of first non-empty list; else first cue of first list.
    public static func resolveUpdateTarget(
        project: ShowProject,
        preferredListID: UUID?,
        preferredCueID: UUID?
    ) -> CueTarget? {
        if let preferredCueID {
            for list in project.cueLists {
                if let preferredListID, list.id != preferredListID { continue }
                if let cue = list.cues.first(where: { $0.id == preferredCueID }) {
                    return CueTarget(listID: list.id, cue: cue)
                }
            }
            // Preferred list was wrong or missing — still search all lists by cue id.
            for list in project.cueLists {
                if let cue = list.cues.first(where: { $0.id == preferredCueID }) {
                    return CueTarget(listID: list.id, cue: cue)
                }
            }
        }
        if let preferredListID,
           let list = project.cueLists.first(where: { $0.id == preferredListID }),
           let cue = list.cues.first {
            return CueTarget(listID: list.id, cue: cue)
        }
        for list in project.cueLists where !list.cues.isEmpty {
            if let cue = list.cues.first {
                return CueTarget(listID: list.id, cue: cue)
            }
        }
        return nil
    }

    /// List used when recording a new cue (preferred list, else first list).
    public static func resolveRecordList(
        project: ShowProject,
        preferredListID: UUID?
    ) -> CueList? {
        if let preferredListID,
           let list = project.cueLists.first(where: { $0.id == preferredListID }) {
            return list
        }
        return project.cueLists.first
    }

    public static func makeRecordedCue(
        levels: CueLevelData,
        list: CueList,
        preferences: ProjectPreferences
    ) -> Cue {
        let displayNumber = nextDisplayNumber(in: list)
        return Cue(
            number: displayNumber,
            name: "Cue \(NSDecimalNumber(decimal: displayNumber).stringValue)",
            fadeIn: preferences.defaultFadeIn,
            fadeOut: preferences.defaultFadeOut,
            tracking: preferences.defaultTracking,
            levels: levels
        )
    }

    public static func cueByApplyingLevels(_ cue: Cue, levels: CueLevelData) -> Cue {
        var next = cue
        next.levels = levels
        return next
    }

    public static func levelsAreEmpty(_ levels: CueLevelData) -> Bool {
        levels.fixtures.isEmpty
            || levels.fixtures.allSatisfy { $0.attributes.isEmpty && $0.paletteRefs.isEmpty }
    }
}
