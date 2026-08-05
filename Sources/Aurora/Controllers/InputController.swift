import AuroraCore
import AuroraEngine
import AuroraMIDI
import AuroraModel
import Foundation

/// CoreMIDI, RTP-MIDI, OSC, learn, and MIDI log (Stage C / UI-GATE-1 / UI-GATE-2).
@MainActor
final class InputController: ObservableObject {
    private let midi = MIDIInputManager()
    let midiLearn = MIDILearnSession()
    private let midiLearnFlag = MIDILearnFlag()
    let rtpMIDI = RTPMIDISession()
    private let oscServer = OSCInputServer(port: 9000)

    @Published private(set) var midiStatus: String = "MIDI: off"
    @Published private(set) var lastMIDIEvent: String = ""
    @Published private(set) var isMIDILearning: Bool = false
    @Published private(set) var oscStatus: String = "OSC: off"
    @Published private(set) var isOSCEnabled: Bool = false
    @Published private(set) var midiLog: [String] = []

    private let maxMIDILog = 100
    private var midiObserverToken: ControlEventObserverToken?

    func stopAll() {
        midi.stop()
        oscServer.stop()
    }

    /// Installs a **dedicated** MIDI log observer (does not replace other observers).
    func startMIDI(router: ControlActionRouter, session: @escaping () -> DocumentSession, onLog: @escaping (String) -> Void) {
        let learnFlag = midiLearnFlag
        // Remove prior subscription if re-started.
        if let token = midiObserverToken {
            router.removeUIObserver(token)
            midiObserverToken = nil
        }
        midiObserverToken = router.addUIObserver { [weak self] _, summary in
            Task { @MainActor in
                self?.appendMIDILog(summary)
                self?.lastMIDIEvent = summary
                self?.midiStatus = "MIDI: \(self?.midi.connectedCount ?? 0) src · \(summary)"
                self?.objectWillChange.send()
            }
        }
        midi.setHandler { [weak self] events in
            if learnFlag.isArmed {
                Task { @MainActor in
                    self?.handleMIDILearnOnly(events, session: session(), router: router, onLog: onLog)
                }
                return
            }
            router.handleMIDIEvents(events)
        }
        do {
            try midi.start()
            midiStatus = "MIDI: \(midi.connectedCount) sources"
        } catch {
            midiStatus = "MIDI: error"
        }
        objectWillChange.send()
    }

    func applySavedRTPMIDI(onLog: (String) -> Void) {
        let config = RTPMIDIConfig.load()
        rtpMIDI.apply(config)
        if config.enabled {
            onLog("RTP-MIDI enabled (\(rtpMIDI.localName))")
            try? midi.connectAllSources()
        }
    }

    func setRTPMIDIEnabled(_ enabled: Bool, onLog: (String) -> Void) {
        rtpMIDI.setEnabled(enabled)
        if enabled {
            try? midi.connectAllSources()
        }
        midiStatus = "\(midi.connectedCount) src · \(rtpMIDI.statusLine())"
        onLog(rtpMIDI.statusLine())
        objectWillChange.send()
    }

    /// OSC live dispatch runs on the network callback thread first (UI-GATE-2).
    /// Presentation updates hop to MainActor afterward only.
    func setOSCEnabled(
        _ enabled: Bool,
        router: ControlActionRouter,
        onUINotify: @escaping @MainActor (ShowAction, Float?) -> Void,
        onLog: (String) -> Void
    ) {
        if enabled {
            oscServer.setHandler { action, value in
                // Immediate live path — no MainActor wait.
                if let value {
                    let control = MIDIControlValue(normalized: Double(value), isTrigger: false)
                    router.dispatch(action, control: control, notifySummary: "OSC \(action.storageKey)")
                } else {
                    router.dispatch(action, notifySummary: "OSC \(action.storageKey)")
                }
                Task { @MainActor in
                    onUINotify(action, value)
                }
            }
            do {
                try oscServer.start()
                isOSCEnabled = true
                oscStatus = "OSC: :\(oscServer.port)"
                onLog("OSC listening on \(oscServer.port)")
            } catch {
                isOSCEnabled = false
                oscStatus = "OSC: error"
                onLog("OSC start failed: \(error.localizedDescription)")
            }
        } else {
            oscServer.stop()
            isOSCEnabled = false
            oscStatus = "OSC: off"
            onLog("OSC stopped")
        }
        objectWillChange.send()
    }

    func armMIDILearn(_ action: ShowAction) {
        midiLearn.arm(action)
        isMIDILearning = true
        midiLearnFlag.isArmed = true
        objectWillChange.send()
    }

    func cancelMIDILearn() {
        midiLearn.cancel()
        isMIDILearning = false
        midiLearnFlag.isArmed = false
        objectWillChange.send()
    }

    private func handleMIDILearnOnly(
        _ events: [MIDIEvent],
        session: DocumentSession,
        router: ControlActionRouter,
        onLog: (String) -> Void
    ) {
        for event in events {
            lastMIDIEvent = event.summary
            appendMIDILog(event.summary)
            if let learned = midiLearn.completeIfArmed(event: event) {
                isMIDILearning = false
                midiLearnFlag.isArmed = false
                do {
                    try session.perform(AddMIDIMappingCommand(mapping: learned.mapping))
                    router.updateMappings(session.project.midiMappings, project: session.project)
                    onLog("MIDI learned \(learned.action.storageKey)")
                } catch {
                    // surface via status on AppModel
                }
            }
        }
        midiStatus = "MIDI: \(midi.connectedCount) src · \(lastMIDIEvent)"
        objectWillChange.send()
    }

    private func appendMIDILog(_ message: String) {
        midiLog.append(message)
        if midiLog.count > maxMIDILog {
            midiLog.removeFirst(midiLog.count - maxMIDILog)
        }
    }
}
