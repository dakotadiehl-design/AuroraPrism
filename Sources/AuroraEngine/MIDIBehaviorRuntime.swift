import AuroraModel
import Foundation

/// Live instance of a MIDI behavior envelope (engine frame path).
public struct MIDILiveBehavior: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var definitionID: UUID
    public var attribute: String
    public var fixtureIDs: [UUID]
    public var peak: Double
    public var envelope: MIDIEnvelopeSpec
    public var startTime: TimeInterval
    public var released: Bool
    public var releaseStart: TimeInterval?
    public var sourceKey: String

    public init(
        id: UUID = UUID(),
        definitionID: UUID,
        attribute: String,
        fixtureIDs: [UUID],
        peak: Double,
        envelope: MIDIEnvelopeSpec,
        startTime: TimeInterval,
        released: Bool = false,
        releaseStart: TimeInterval? = nil,
        sourceKey: String = ""
    ) {
        self.id = id
        self.definitionID = definitionID
        self.attribute = attribute
        self.fixtureIDs = fixtureIDs
        self.peak = peak
        self.envelope = envelope
        self.startTime = startTime
        self.released = released
        self.releaseStart = releaseStart
        self.sourceKey = sourceKey
    }

    public func level(at time: TimeInterval) -> Double {
        let t = max(0, time - startTime)
        let env = envelope.level(at: t, released: released, releaseStart: releaseStart.map { max(0, $0 - startTime) })
        return peak * env
    }

    public func isFinished(at time: TimeInterval) -> Bool {
        let t = max(0, time - startTime)
        if released, let rs = releaseStart {
            let rt = t - max(0, rs - startTime)
            return rt >= envelope.release
        }
        // Auto-finish flash/ahdr when sustain is 0 and past decay (no note-off needed).
        if envelope.sustain <= 0.001, !released {
            let end = envelope.attack + envelope.hold + envelope.decay + envelope.release
            return t >= end
        }
        return false
    }
}

/// Concurrent MIDI behavior stack applied above effects / below programmer (optional layer).
/// Actually applied **after** effects and **before** programmer so programmer wins.
public final class MIDIBehaviorRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var definitions: [MIDIBehaviorDefinition] = []
    private var drumProfiles: [DrumDeviceProfile] = []
    private var live: [MIDILiveBehavior] = []
    public var maxGlobalConcurrent: Int = 32

    public init() {}

    public func load(definitions: [MIDIBehaviorDefinition], drums: [DrumDeviceProfile]) {
        lock.lock()
        self.definitions = definitions
        self.drumProfiles = drums
        lock.unlock()
    }

    public var liveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return live.count
    }

    public func clear() {
        lock.lock()
        live.removeAll()
        lock.unlock()
    }

    public func panic() {
        clear()
    }

    /// Resolve drum role for a note event.
    public func resolveDrumRole(note: UInt8, deviceID: String, songSection: String?) -> DrumRole? {
        lock.lock()
        let profiles = drumProfiles
        lock.unlock()
        for p in profiles {
            if let r = p.role(for: note, deviceID: deviceID, songSection: songSection) {
                return r
            }
        }
        return nil
    }

    /// Trigger matching behaviors from a note-on (or CC as flash).
    public func noteOn(
        note: UInt8,
        velocity: UInt8,
        channel: UInt8,
        deviceID: String,
        songSection: String?,
        time: TimeInterval,
        selection: [UUID]
    ) {
        let role = resolveDrumRole(note: note, deviceID: deviceID, songSection: songSection)
        lock.lock()
        defer { lock.unlock() }
        let defs = definitions.filter(\.enabled)
        for def in defs {
            if let section = def.songSectionContext, !section.isEmpty, section != songSection {
                continue
            }
            if let d = def.deviceID, !d.isEmpty, d != deviceID { continue }
            if let ch = def.channel, ch != channel { continue }

            if let drumRole = def.drumRole {
                guard drumRole == role else { continue }
            } else {
                guard def.messageType == "noteOn" else { continue }
                if let lo = def.data1Min, note < lo { continue }
                if let hi = def.data1Max, note > hi { continue }
            }

            let targets = def.fixtureIDs.isEmpty ? selection : def.fixtureIDs
            guard !targets.isEmpty else { continue }

            var peak = def.peakLevel
            if def.velocityScale {
                peak *= Double(velocity) / 127.0
            }

            // Concurrency per definition
            let existing = live.filter { $0.definitionID == def.id }
            if existing.count >= def.maxConcurrent {
                if let oldest = existing.min(by: { $0.startTime < $1.startTime }) {
                    live.removeAll { $0.id == oldest.id }
                }
            }
            if live.count >= maxGlobalConcurrent {
                live.sort { $0.startTime < $1.startTime }
                live.removeFirst()
            }

            live.append(MIDILiveBehavior(
                definitionID: def.id,
                attribute: def.attribute,
                fixtureIDs: targets,
                peak: peak,
                envelope: def.envelope,
                startTime: time,
                sourceKey: "\(deviceID):\(channel):\(note)"
            ))
        }
    }

    public func noteOff(note: UInt8, channel: UInt8, deviceID: String, time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(deviceID):\(channel):\(note)"
        for i in live.indices {
            if live[i].sourceKey == key, !live[i].released {
                live[i].released = true
                live[i].releaseStart = time
            }
        }
    }

    /// Release all live instances owned by a MIDI device (unplug / source disconnect).
    /// Marks matching instances released at `time` so release envelopes can complete.
    @discardableResult
    public func releaseAll(forDeviceID deviceID: String, at time: TimeInterval) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let prefix = deviceID + ":"
        var count = 0
        for i in live.indices {
            if live[i].sourceKey.hasPrefix(prefix), !live[i].released {
                live[i].released = true
                live[i].releaseStart = time
                count += 1
            }
        }
        return count
    }

    /// Apply live envelopes onto look and prune finished.
    public func apply(on look: ActiveLook, time: TimeInterval) -> ActiveLook {
        lock.lock()
        live.removeAll { $0.isFinished(at: time) }
        let instances = live
        lock.unlock()
        guard !instances.isEmpty else { return look }
        var result = look
        for inst in instances {
            let level = inst.level(at: time)
            guard level > 0.0001 else { continue }
            for fx in inst.fixtureIDs {
                var attrs = result.fixtureAttributes[fx] ?? [:]
                let base = attrs[inst.attribute] ?? 0
                // Additive blend capped at 1 (accent on top of playback).
                attrs[inst.attribute] = min(1, max(base, level))
                // For intensity-style, prefer max; for continuous, max is safer for accents.
                result.fixtureAttributes[fx] = attrs
            }
        }
        return result
    }
}
