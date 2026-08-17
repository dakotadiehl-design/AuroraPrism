import AuroraMusical
import CoreMIDI
import Foundation

public enum MIDIHostTime {
    /// Convert CoreMIDI packet timestamp to monotonic `HostTime`.
    public static func fromCoreMIDI(_ midiTimeStamp: MIDITimeStamp) -> HostTime {
        if midiTimeStamp == 0 {
            return .now()
        }
        // MIDITimeStamp is in host ticks on Apple platforms when using CoreMIDI.
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = midiTimeStamp * UInt64(info.numer) / UInt64(info.denom)
        return HostTime(nanoseconds: nanos)
    }
}

public extension HostTime {
    /// TimeInterval representation for legacy `MIDIEvent.timestamp` (monotonic seconds, not wall-clock).
    var legacyTimeInterval: TimeInterval { seconds }

    /// Reconstruct `HostTime` from a legacy monotonic-seconds timestamp (e.g. `MIDIEvent.timestamp`).
    /// Returns nil for non-finite / negative / overflow values so callers can fall back defensively.
    static func fromLegacyMonotonicSeconds(_ seconds: TimeInterval) -> HostTime? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let ns = seconds * 1_000_000_000.0
        guard ns <= Double(UInt64.max) else { return nil }
        return HostTime(nanoseconds: UInt64(ns.rounded()))
    }
}
