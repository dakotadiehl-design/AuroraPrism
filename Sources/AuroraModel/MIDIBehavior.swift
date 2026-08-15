import Foundation

/// Drum / device semantic role for note abstraction (P0-J drum baseline).
public enum DrumRole: String, Codable, Sendable, Hashable, CaseIterable {
    case kick
    case snare
    case hihatClosed
    case hihatOpen
    case tomHigh
    case tomMid
    case tomLow
    case crash
    case ride
    case clap
    case rim
    case accent
    case other
}

/// Single note → role binding (JSON-safe; avoids non-string dictionary keys).
public struct DrumNoteBinding: Codable, Equatable, Sendable, Hashable {
    public var note: UInt8
    public var role: DrumRole
    public init(note: UInt8, role: DrumRole) {
        self.note = note
        self.role = role
    }
}

/// Hardware note → semantic role map for a device (Electronic Drums smoke).
public struct DrumDeviceProfile: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Optional CoreMIDI device id filter.
    public var deviceID: String?
    /// Note bindings.
    public var noteBindings: [DrumNoteBinding]
    /// Optional song-section scoped overrides: section label → bindings.
    public var sectionBindings: [String: [DrumNoteBinding]]

    public init(
        id: UUID = UUID(),
        name: String = "Drums",
        deviceID: String? = nil,
        noteBindings: [DrumNoteBinding] = [],
        sectionBindings: [String: [DrumNoteBinding]] = [:]
    ) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.noteBindings = noteBindings
        self.sectionBindings = sectionBindings
    }

    public init(
        id: UUID = UUID(),
        name: String = "Drums",
        deviceID: String? = nil,
        noteRoles: [UInt8: DrumRole],
        sectionNoteRoles: [String: [UInt8: DrumRole]] = [:]
    ) {
        self.id = id
        self.name = name
        self.deviceID = deviceID
        self.noteBindings = noteRoles.map { DrumNoteBinding(note: $0.key, role: $0.value) }
            .sorted { $0.note < $1.note }
        var sections: [String: [DrumNoteBinding]] = [:]
        for (k, map) in sectionNoteRoles {
            sections[k] = map.map { DrumNoteBinding(note: $0.key, role: $0.value) }
                .sorted { $0.note < $1.note }
        }
        self.sectionBindings = sections
    }

    public func role(for note: UInt8, deviceID: String?, songSection: String?) -> DrumRole? {
        if let deviceID, let filter = self.deviceID, !filter.isEmpty, filter != deviceID {
            return nil
        }
        if let section = songSection, let map = sectionBindings[section],
           let r = map.first(where: { $0.note == note })?.role {
            return r
        }
        return noteBindings.first(where: { $0.note == note })?.role
    }

    /// GM-ish electronic kit defaults (note numbers common on e-kits).
    public static var generalMIDIKit: DrumDeviceProfile {
        DrumDeviceProfile(
            name: "GM Electronic Kit",
            noteRoles: [
                36: .kick, 35: .kick,
                38: .snare, 40: .snare,
                42: .hihatClosed, 44: .hihatClosed, 46: .hihatOpen,
                48: .tomHigh, 47: .tomMid, 45: .tomLow, 43: .tomLow,
                49: .crash, 57: .crash,
                51: .ride, 59: .ride,
                39: .clap, 37: .rim,
            ]
        )
    }
}

/// Envelope shape for temporary MIDI-driven lighting behaviors.
public enum MIDIEnvelopeKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Attack → Hold → Decay → Release (AHDR) — good for drum accents.
    case ahdr
    /// Attack → Decay → Sustain → Release.
    case adsr
    /// Instant on, linear release.
    case flash
}

public struct MIDIEnvelopeSpec: Codable, Equatable, Sendable, Hashable {
    public var kind: MIDIEnvelopeKind
    public var attack: TimeInterval
    public var hold: TimeInterval
    public var decay: TimeInterval
    public var sustain: Double
    public var release: TimeInterval

    public init(
        kind: MIDIEnvelopeKind = .ahdr,
        attack: TimeInterval = 0.01,
        hold: TimeInterval = 0.05,
        decay: TimeInterval = 0.15,
        sustain: Double = 0,
        release: TimeInterval = 0.2
    ) {
        self.kind = kind
        self.attack = max(0, attack)
        self.hold = max(0, hold)
        self.decay = max(0, decay)
        self.sustain = min(1, max(0, sustain))
        self.release = max(0, release)
    }

    public static let drumFlash = MIDIEnvelopeSpec(
        kind: .ahdr, attack: 0.005, hold: 0.03, decay: 0.12, sustain: 0, release: 0.08
    )

    /// Level 0…1 at `t` seconds after note-on. `released` when note-off received.
    public func level(at t: TimeInterval, released: Bool, releaseStart: TimeInterval?) -> Double {
        if released, let rs = releaseStart {
            let rt = max(0, t - rs)
            if release <= 0 { return 0 }
            let base: Double
            switch kind {
            case .ahdr, .flash:
                base = levelBeforeRelease(at: min(t, rs))
            case .adsr:
                base = levelBeforeRelease(at: min(t, rs))
            }
            return base * max(0, 1 - rt / release)
        }
        return levelBeforeRelease(at: t)
    }

    private func levelBeforeRelease(at t: TimeInterval) -> Double {
        switch kind {
        case .flash:
            if t < attack { return attack <= 0 ? 1 : t / attack }
            return 1
        case .ahdr:
            var cursor = 0.0
            if t < attack {
                return attack <= 0 ? 1 : t / attack
            }
            cursor += attack
            if t < cursor + hold { return 1 }
            cursor += hold
            if t < cursor + decay {
                let u = decay <= 0 ? 1 : (t - cursor) / decay
                return 1 + (sustain - 1) * u
            }
            return sustain
        case .adsr:
            if t < attack {
                return attack <= 0 ? 1 : t / attack
            }
            let afterA = t - attack
            if afterA < decay {
                let u = decay <= 0 ? 1 : afterA / decay
                return 1 + (sustain - 1) * u
            }
            return sustain
        }
    }
}

/// Reusable MIDI-driven behavior definition (persisted).
public struct MIDIBehaviorDefinition: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    /// Optional drum role trigger (when set, matches resolved drum role instead of raw note).
    public var drumRole: DrumRole?
    /// Or raw MIDI match fields (when drumRole is nil).
    public var messageType: String
    public var channel: UInt8?
    public var data1Min: UInt8?
    public var data1Max: UInt8?
    public var deviceID: String?
    public var songSectionContext: String?
    /// Target attribute on selection (or all fixtures when empty selection uses fixtureIDs).
    public var attribute: String
    public var fixtureIDs: [UUID]
    /// Peak level scaled by velocity (0…1).
    public var peakLevel: Double
    public var velocityScale: Bool
    public var envelope: MIDIEnvelopeSpec
    /// Maximum concurrent live instances of this behavior.
    public var maxConcurrent: Int

    public init(
        id: UUID = UUID(),
        name: String = "Behavior",
        enabled: Bool = true,
        drumRole: DrumRole? = nil,
        messageType: String = "noteOn",
        channel: UInt8? = nil,
        data1Min: UInt8? = nil,
        data1Max: UInt8? = nil,
        deviceID: String? = nil,
        songSectionContext: String? = nil,
        attribute: String = "intensity",
        fixtureIDs: [UUID] = [],
        peakLevel: Double = 1,
        velocityScale: Bool = true,
        envelope: MIDIEnvelopeSpec = .drumFlash,
        maxConcurrent: Int = 8
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.drumRole = drumRole
        self.messageType = messageType
        self.channel = channel
        self.data1Min = data1Min
        self.data1Max = data1Max
        self.deviceID = deviceID
        self.songSectionContext = songSectionContext
        self.attribute = attribute
        self.fixtureIDs = fixtureIDs
        self.peakLevel = min(1, max(0, peakLevel))
        self.velocityScale = velocityScale
        self.envelope = envelope
        self.maxConcurrent = max(1, maxConcurrent)
    }
}

/// Outbound MIDI feedback profile (LED / CC / note echo).
public struct MIDIFeedbackProfile: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var deviceID: String?
    public var channel: UInt8
    /// When true, do not echo events that originated from the same device (loop prevention).
    public var preventFeedbackLoop: Bool
    /// Map show state keys → CC numbers for continuous feedback.
    public var masterIntensityCC: UInt8?
    public var blackoutNote: UInt8?
    public var goNote: UInt8?

    public init(
        id: UUID = UUID(),
        name: String = "Feedback",
        enabled: Bool = true,
        deviceID: String? = nil,
        channel: UInt8 = 0,
        preventFeedbackLoop: Bool = true,
        masterIntensityCC: UInt8? = 7,
        blackoutNote: UInt8? = nil,
        goNote: UInt8? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.deviceID = deviceID
        self.channel = channel
        self.preventFeedbackLoop = preventFeedbackLoop
        self.masterIntensityCC = masterIntensityCC
        self.blackoutNote = blackoutNote
        self.goNote = goNote
    }
}
