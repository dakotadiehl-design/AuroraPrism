import AuroraModel
import Foundation

/// Resolved cue identity for Perform / remote / inspector (UI-02 A4).
public struct PerformanceCueSummary: Equatable, Sendable {
    public var listID: UUID?
    public var cueID: UUID?
    public var number: Decimal?
    public var name: String
    public var sectionLabel: String?

    public init(
        listID: UUID? = nil,
        cueID: UUID? = nil,
        number: Decimal? = nil,
        name: String = "",
        sectionLabel: String? = nil
    ) {
        self.listID = listID
        self.cueID = cueID
        self.number = number
        self.name = name
        self.sectionLabel = sectionLabel
    }

    public static let empty = PerformanceCueSummary()

    public var numberDisplay: String {
        guard let number else { return "" }
        return NSDecimalNumber(decimal: number).stringValue
    }
}

/// Song fields needed to resolve next cue without inventing identity (UI-02 A4).
public struct SongCueResolveContext: Equatable, Sendable {
    public var songID: UUID?
    public var entryIndex: Int
    public var entryCount: Int
    public var currentEntryLabel: String
    public var nextEntryLabel: String?

    public init(
        songID: UUID? = nil,
        entryIndex: Int = -1,
        entryCount: Int = 0,
        currentEntryLabel: String = "",
        nextEntryLabel: String? = nil
    ) {
        self.songID = songID
        self.entryIndex = entryIndex
        self.entryCount = entryCount
        self.currentEntryLabel = currentEntryLabel
        self.nextEntryLabel = nextEntryLabel
    }

    public static let empty = SongCueResolveContext()
}

/// Pure presentation resolution for current/next cue.
public enum PerformanceCuePresentation {
    /// Resolve current/next cue semantics.
    /// Never invents CURRENT from an unrelated first cue list (post-UI-02 gate G2).
    public static func resolveCues(
        project: ShowProject,
        playback: PlaybackSnapshot,
        song: SongCueResolveContext
    ) -> (current: PerformanceCueSummary, next: PerformanceCueSummary) {
        let sectionCurrent = song.currentEntryLabel.isEmpty ? nil : song.currentEntryLabel
        let current = resolveCurrent(project: project, playback: playback, sectionLabel: sectionCurrent)
        let next = resolveNext(project: project, playback: playback, song: song, current: current)
        return (current, next)
    }

    /// CURRENT resolution order:
    /// 1) cueID + listID · 2) cueID scan · 3) listID + valid index · 4) name-only · 5) empty
    private static func resolveCurrent(
        project: ShowProject,
        playback: PlaybackSnapshot,
        sectionLabel: String?
    ) -> PerformanceCueSummary {
        // 1. listID + cueID
        if let listID = playback.listID, let cueID = playback.cueID,
           let list = project.cueLists.first(where: { $0.id == listID }),
           let cue = list.cues.first(where: { $0.id == cueID }) {
            return summary(list: list, cue: cue, playback: playback, sectionLabel: sectionLabel)
        }

        // 2. cueID alone (listID missing or stale)
        if let cueID = playback.cueID {
            for list in project.cueLists {
                if let cue = list.cues.first(where: { $0.id == cueID }) {
                    return summary(list: list, cue: cue, playback: playback, sectionLabel: sectionLabel)
                }
            }
        }

        // 3. listID + valid index only when the list is found by ID (never first-list fallback)
        if let listID = playback.listID,
           let list = project.cueLists.first(where: { $0.id == listID }),
           playback.cueIndex >= 0,
           list.cues.indices.contains(playback.cueIndex) {
            let cue = list.cues[playback.cueIndex]
            return summary(list: list, cue: cue, playback: playback, sectionLabel: sectionLabel)
        }

        // 4. Textual name fallback — no fabricated number/list identity from another list
        if !playback.cueName.isEmpty {
            return PerformanceCueSummary(
                listID: playback.listID,
                cueID: playback.cueID,
                number: nil,
                name: playback.cueName,
                sectionLabel: sectionLabel
            )
        }

        // 5. Unknown
        return .empty
    }

    private static func summary(
        list: CueList,
        cue: Cue,
        playback: PlaybackSnapshot,
        sectionLabel: String?
    ) -> PerformanceCueSummary {
        PerformanceCueSummary(
            listID: list.id,
            cueID: cue.id,
            number: cue.number,
            name: cue.name.isEmpty ? playback.cueName : cue.name,
            sectionLabel: sectionLabel
        )
    }

    private static func resolveNext(
        project: ShowProject,
        playback: PlaybackSnapshot,
        song: SongCueResolveContext,
        current: PerformanceCueSummary
    ) -> PerformanceCueSummary {
        if song.songID != nil, song.entryIndex + 1 < song.entryCount,
           let songObj = project.songs.first(where: { $0.id == song.songID }),
           songObj.entries.indices.contains(song.entryIndex + 1) {
            let nextEntry = songObj.entries[song.entryIndex + 1]
            let section = nextEntry.label.isEmpty ? song.nextEntryLabel : nextEntry.label
            switch nextEntry.target {
            case .cue(let listID, let cueID):
                if let list = project.cueLists.first(where: { $0.id == listID }),
                   let cue = list.cues.first(where: { $0.id == cueID }) {
                    return PerformanceCueSummary(
                        listID: listID,
                        cueID: cueID,
                        number: cue.number,
                        name: cue.name,
                        sectionLabel: section
                    )
                }
                return PerformanceCueSummary(
                    listID: listID,
                    cueID: cueID,
                    number: nil,
                    name: section ?? "—",
                    sectionLabel: section
                )
            case .cueList(let listID):
                if let list = project.cueLists.first(where: { $0.id == listID }),
                   let cue = list.cues.first {
                    return PerformanceCueSummary(
                        listID: listID,
                        cueID: cue.id,
                        number: cue.number,
                        name: cue.name,
                        sectionLabel: section ?? list.name
                    )
                }
                return PerformanceCueSummary(
                    listID: listID,
                    cueID: nil,
                    number: nil,
                    name: section ?? "—",
                    sectionLabel: section
                )
            }
        }

        // Sequential next only on a known list identity (current or playback listID).
        if let listID = current.listID ?? playback.listID,
           let list = project.cueLists.first(where: { $0.id == listID }) {
            let currentIndex: Int? = {
                if let cueID = current.cueID ?? playback.cueID {
                    return list.cues.firstIndex(where: { $0.id == cueID })
                }
                if playback.cueIndex >= 0, list.cues.indices.contains(playback.cueIndex) {
                    return playback.cueIndex
                }
                // A loaded playback list parks at -1 before its first GO. The
                // list identity is authoritative, so cue 0 is safely NEXT;
                // this is not a fallback to an unrelated project list.
                if playback.cueIndex == -1, playback.cueID == nil, current.cueID == nil {
                    return -1
                }
                return nil
            }()
            if let currentIndex, currentIndex + 1 < list.cues.count {
                let cue = list.cues[currentIndex + 1]
                return PerformanceCueSummary(
                    listID: list.id,
                    cueID: cue.id,
                    number: cue.number,
                    name: cue.name,
                    sectionLabel: nil
                )
            }
        }

        if let section = song.nextEntryLabel {
            return PerformanceCueSummary(
                listID: nil,
                cueID: nil,
                number: nil,
                name: "",
                sectionLabel: section
            )
        }
        return .empty
    }

    /// Whether an inspected cue is the live CURRENT cue (UI-02 A5).
    public static func isCurrentCue(
        inspectedCueID: UUID,
        inspectedListID: UUID,
        playbackCueID: UUID?,
        playbackListID: UUID?,
        playbackCueIndex: Int,
        cueIndexInList: Int
    ) -> Bool {
        if let playbackCueID {
            return inspectedCueID == playbackCueID
        }
        guard let playbackListID, playbackListID == inspectedListID, playbackCueIndex >= 0 else {
            return false
        }
        return cueIndexInList == playbackCueIndex
    }
}
