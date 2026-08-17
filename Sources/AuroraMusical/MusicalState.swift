import Foundation

/// Continuous musical timing (owned by Musical Engine / timing providers).
///
/// Does **not** include song/section identity — that is `ShowMusicalContext`.
public struct MusicalTimingState: Codable, Equatable, Sendable {
    public var transport: MusicalTransport
    public var tempoBPM: Double?
    public var tempoProvenance: MusicalValueProvenance
    public var meter: MusicalMeter?
    public var meterProvenance: MusicalValueProvenance
    public var quarterNotePhase: Double?
    public var quarterNotePosition: QuarterNotePosition?
    public var positionProvenance: MusicalValueProvenance
    public var barBeat: BarBeatPosition?
    public var timingPolicy: TimingSourcePolicy
    public var selectedSourceID: String?
    public var activeSourceID: String?
    public var sourceHealth: TimingSourceHealth
    public var sync: MusicalSyncState
    public var fallback: TimingFallbackState
    public var activeSourceCapabilities: TimingSourceCapabilities
    public var diagnostics: MusicalTimingDiagnostics

    public init(
        transport: MusicalTransport = .stopped,
        tempoBPM: Double? = nil,
        tempoProvenance: MusicalValueProvenance = .unknown,
        meter: MusicalMeter? = nil,
        meterProvenance: MusicalValueProvenance = .unknown,
        quarterNotePhase: Double? = nil,
        quarterNotePosition: QuarterNotePosition? = nil,
        positionProvenance: MusicalValueProvenance = .unknown,
        barBeat: BarBeatPosition? = nil,
        timingPolicy: TimingSourcePolicy = .internalOnly,
        selectedSourceID: String? = nil,
        activeSourceID: String? = nil,
        sourceHealth: TimingSourceHealth = .unavailable,
        sync: MusicalSyncState = .unlocked,
        fallback: TimingFallbackState = .notApplicable,
        activeSourceCapabilities: TimingSourceCapabilities = .init(),
        diagnostics: MusicalTimingDiagnostics = .empty
    ) {
        self.transport = transport
        self.tempoBPM = tempoBPM
        self.tempoProvenance = tempoProvenance
        self.meter = meter
        self.meterProvenance = meterProvenance
        self.quarterNotePhase = quarterNotePhase
        self.quarterNotePosition = quarterNotePosition
        self.positionProvenance = positionProvenance
        self.barBeat = barBeat
        self.timingPolicy = timingPolicy
        self.selectedSourceID = selectedSourceID
        self.activeSourceID = activeSourceID
        self.sourceHealth = sourceHealth
        self.sync = sync
        self.fallback = fallback
        self.activeSourceCapabilities = activeSourceCapabilities
        self.diagnostics = diagnostics
    }

    public static let initial = MusicalTimingState()
}

/// Structural show context (Song Mode / show control — not MIDI Clock).
public struct ShowMusicalContext: Codable, Equatable, Sendable {
    public var activeSongID: UUID?
    public var activeSectionID: UUID?
    public var songDefaultTempoBPM: Double?
    public var songDefaultMeter: MusicalMeter?

    public init(
        activeSongID: UUID? = nil,
        activeSectionID: UUID? = nil,
        songDefaultTempoBPM: Double? = nil,
        songDefaultMeter: MusicalMeter? = nil
    ) {
        self.activeSongID = activeSongID
        self.activeSectionID = activeSectionID
        self.songDefaultTempoBPM = songDefaultTempoBPM
        self.songDefaultMeter = songDefaultMeter
    }

    public static let empty = ShowMusicalContext()
}

public struct MusicalState: Codable, Equatable, Sendable {
    public var timing: MusicalTimingState
    public var context: ShowMusicalContext

    public init(timing: MusicalTimingState = .initial, context: ShowMusicalContext = .empty) {
        self.timing = timing
        self.context = context
    }

    public static let initial = MusicalState()
}
