import AuroraModel
import Foundation

/// Deterministic section/song transition ordering (Phase H).
///
/// Order (serialized control plane):
/// 1. old section `onExitActions`
/// 2. update active section/song context
/// 3. sequence reset/arm per each sequence's `resetPolicy`
/// 4. new section `onEnterActions`
/// 5. publish result (caller applies emissions + context)
public enum AMESectionTransition {
    public struct Request: Equatable, Sendable {
        public var previousSongID: UUID?
        public var previousSectionID: UUID?
        public var nextSongID: UUID?
        public var nextSectionID: UUID?
        public var project: ShowProject

        public init(
            previousSongID: UUID?,
            previousSectionID: UUID?,
            nextSongID: UUID?,
            nextSectionID: UUID?,
            project: ShowProject
        ) {
            self.previousSongID = previousSongID
            self.previousSectionID = previousSectionID
            self.nextSongID = nextSongID
            self.nextSectionID = nextSectionID
            self.project = project
        }
    }

    public struct Result: Equatable, Sendable {
        public var exitActions: [AuroraAction]
        public var enterActions: [AuroraAction]
        public var nextContext: AMEShowContext
        public var sectionChanged: Bool
        public var songChanged: Bool
        public var exitSectionName: String?
        public var enterSectionName: String?

        public init(
            exitActions: [AuroraAction] = [],
            enterActions: [AuroraAction] = [],
            nextContext: AMEShowContext,
            sectionChanged: Bool,
            songChanged: Bool,
            exitSectionName: String? = nil,
            enterSectionName: String? = nil
        ) {
            self.exitActions = exitActions
            self.enterActions = enterActions
            self.nextContext = nextContext
            self.sectionChanged = sectionChanged
            self.songChanged = songChanged
            self.exitSectionName = exitSectionName
            self.enterSectionName = enterSectionName
        }

        /// Flattened lifecycle actions in execution order (exit then enter).
        public var orderedLifecycleActions: [AuroraAction] {
            exitActions + enterActions
        }
    }

    public static func plan(_ request: Request) -> Result {
        let songChanged = request.previousSongID != request.nextSongID
        let sectionChanged = request.previousSectionID != request.nextSectionID

        var exitActions: [AuroraAction] = []
        var exitName: String?
        if sectionChanged, let prev = request.previousSectionID {
            if let section = findSection(id: prev, in: request.project) {
                exitActions = section.onExitActions
                exitName = section.name
            }
        }

        var enterActions: [AuroraAction] = []
        var enterName: String?
        if sectionChanged, let next = request.nextSectionID {
            if let section = findSection(id: next, in: request.project) {
                enterActions = section.onEnterActions
                enterName = section.name
            }
        }

        return Result(
            exitActions: exitActions,
            enterActions: enterActions,
            nextContext: AMEShowContext(
                activeSongID: request.nextSongID,
                activeSectionID: request.nextSectionID
            ),
            sectionChanged: sectionChanged,
            songChanged: songChanged,
            exitSectionName: exitName,
            enterSectionName: enterName
        )
    }

    private static func findSection(id: UUID, in project: ShowProject) -> SongSection? {
        for song in project.songs {
            if let s = song.sections.first(where: { $0.id == id }) {
                return s
            }
        }
        return nil
    }

    /// Song default tempo/meter provenance for Musical Engine when entering a song.
    public struct SongMusicalDefaults: Equatable, Sendable {
        public var tempoBPM: Double?
        public var meter: ShowMusicalMeter?
        public var tempoProvenance: String
        public var meterProvenance: String

        public init(
            tempoBPM: Double?,
            meter: ShowMusicalMeter?,
            tempoProvenance: String,
            meterProvenance: String
        ) {
            self.tempoBPM = tempoBPM
            self.meter = meter
            self.tempoProvenance = tempoProvenance
            self.meterProvenance = meterProvenance
        }
    }

    public static func musicalDefaults(
        forSongID songID: UUID?,
        project: ShowProject
    ) -> SongMusicalDefaults {
        guard let songID,
              let song = project.songs.first(where: { $0.id == songID })
        else {
            return SongMusicalDefaults(
                tempoBPM: project.ame.musicalSettings.defaultTempoBPM,
                meter: project.ame.musicalSettings.defaultMeter,
                tempoProvenance: "projectDefault",
                meterProvenance: "projectDefault"
            )
        }
        let tempo = song.defaultTempoBPM
        let meter = song.defaultMeter
        return SongMusicalDefaults(
            tempoBPM: tempo ?? project.ame.musicalSettings.defaultTempoBPM,
            meter: meter ?? project.ame.musicalSettings.defaultMeter,
            tempoProvenance: tempo != nil ? "songDefault" : "projectDefault",
            meterProvenance: meter != nil ? "songDefault" : "projectDefault"
        )
    }
}
