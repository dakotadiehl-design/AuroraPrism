import AuroraMusical
import Foundation

/// Routes decoded MIDI timing messages into a `MusicalTimingSink` (Musical Engine).
///
/// Channel-voice performance events are ignored — those belong to AME.
/// System Real-Time (clock/start/stop/continue) and System Common SPP are forwarded
/// with source identity preserved for engine admission.
public final class MIDIClockTimingAdapter: @unchecked Sendable {
    private let lock = NSLock()
    private weak var sink: MusicalTimingSink?
    /// Optional filter: only forward events from this source ID (in addition to engine admission).
    private var preferredSourceID: String?

    public init(sink: MusicalTimingSink? = nil) {
        self.sink = sink
    }

    public func setSink(_ sink: MusicalTimingSink?) {
        lock.lock()
        self.sink = sink
        lock.unlock()
    }

    public func setPreferredSourceID(_ sourceID: String?) {
        lock.lock()
        preferredSourceID = sourceID
        lock.unlock()
    }

    /// Current preferred source filter (for host diagnostics / tests).
    public var preferredSourceIDForDiagnostics: String? {
        lock.lock(); defer { lock.unlock() }
        return preferredSourceID
    }

    /// Forward a batch of ingress events (e.g. from one CoreMIDI packet).
    public func handle(ingress events: [MIDIIngressEvent]) {
        lock.lock()
        let sink = self.sink
        let preferred = preferredSourceID
        lock.unlock()
        guard let sink else { return }

        for event in events {
            if let preferred, event.sourceID != preferred { continue }
            switch event {
            case .systemRealtime(let rt, let sourceID, let hostTime):
                switch rt {
                case .timingClock:
                    sink.receiveClockPulse(from: sourceID, at: hostTime)
                case .start:
                    sink.receiveTransportStart(from: sourceID, at: hostTime)
                case .continue:
                    sink.receiveTransportContinue(from: sourceID, at: hostTime)
                case .stop:
                    sink.receiveTransportStop(from: sourceID, at: hostTime)
                case .activeSensing, .systemReset, .other:
                    break
                }
            case .systemCommon(let common, let sourceID, let hostTime):
                if case .songPositionPointer(let sixteenths) = common {
                    let pos = QuarterNotePosition.fromMIDISongPositionSixteenths(sixteenths)
                    sink.receiveSongPosition(pos, from: sourceID, at: hostTime)
                }
            case .channelVoice:
                break
            }
        }
    }

    /// Convenience: parse bytes and forward timing only.
    public func handle(
        bytes: [UInt8],
        sourceID: String,
        hostTime: HostTime,
        parser: MIDIStreamParser = MIDIStreamParser()
    ) {
        let events = parser.parseIngress(bytes: bytes, sourceID: sourceID, hostTime: hostTime)
        handle(ingress: events)
    }
}
