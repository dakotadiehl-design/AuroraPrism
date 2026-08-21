import AuroraCore
import AuroraDiagnostics
import AuroraEngine
import AuroraMIDI
import AuroraModel
import Foundation

/// CoreMIDI, RTP-MIDI, OSC, learn, and MIDI log (Stage C / UI-GATE-1 / UI-GATE-2).
@MainActor
final class InputController: ObservableObject {
    private let midi = MIDIInputManager()
    let midiOut = MIDIOutputManager()
    let midiLearn = MIDILearnSession()
    private let midiLearnFlag = MIDILearnFlag()
    let rtpMIDI = RTPMIDISession()
    private let oscServer = OSCInputServer(port: 9000)

    /// Structured health for toolbar/status (ST-01). Prefer over string parsing.
    @Published private(set) var midiHealth: MIDIHealthSnapshot = .off
    /// Legacy display string — derived from `midiHealth` + last event.
    @Published private(set) var midiStatus: String = "MIDI: off"
    @Published private(set) var lastMIDIEvent: String = ""
    @Published private(set) var isMIDILearning: Bool = false
    @Published private(set) var oscStatus: String = "OSC: off"
    @Published private(set) var isOSCEnabled: Bool = false
    @Published private(set) var midiLog: [String] = []

    private let maxMIDILog = 100
    private var midiObserverToken: ControlEventObserverToken?
    private var midiSubsystemRunning = false

    func stopAll() {
        midi.stop()
        midiOut.stop()
        oscServer.stop()
        midiSubsystemRunning = false
        publishHealth(sourceCount: 0, failed: false)
    }

    /// Optional clock adapter from show control (timing independent of channel-voice Learn path).
    private weak var clockAdapter: MIDIClockTimingAdapter?
    /// Optional inventory listener (binding resolution / Musical Engine source admit).
    private var inventoryListener: (([MIDIDeviceInfo]) -> Void)?

    /// Current CoreMIDI source inventory (canonical `uid:` / `ep:` ids).
    var midiSources: [MIDIDeviceInfo] { midi.sources }

    /// Bind Musical Engine clock adapter (must be set before or with startMIDI).
    func attachClockAdapter(_ adapter: MIDIClockTimingAdapter) {
        clockAdapter = adapter
    }

    /// Called whenever the live source inventory changes (hotplug).
    func setInventoryListener(_ listener: (([MIDIDeviceInfo]) -> Void)?) {
        inventoryListener = listener
        if midiSubsystemRunning {
            listener?(midi.sources)
        }
    }

    /// Installs a **dedicated** MIDI log observer (does not replace other observers).
    func startMIDI(router: ControlActionRouter, session: @escaping () -> DocumentSession) {
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
                self?.refreshStatusLine(detail: summary)
                self?.objectWillChange.send()
            }
        }
        // Full ingress → Musical Engine clock path (runs even when Learn is armed).
        // Capture adapter reference for nonisolated CoreMIDI callback.
        let adapter = clockAdapter
        midi.setIngressHandler { ingress in
            adapter?.handle(ingress: ingress)
        }
        midi.setHandler { [weak self] events in
            if learnFlag.isArmed {
                Task { @MainActor in
                    self?.handleMIDILearnOnly(events, session: session(), router: router)
                }
                // Still allow AME learn path if armed for AME
                if router.isAMELearning {
                    router.handleAMELearnEvents(events)
                }
                return
            }
            for e in events {
                self?.midiOut.noteInputFrom(sourceID: e.sourceID)
            }
            if router.isAMELearning {
                router.handleAMELearnEvents(events)
                return
            }
            router.handleMIDIEvents(events)
        }
        // ST-01: hotplug inventory updates without requiring MIDI traffic.
        midi.setInventoryChangeHandler { [weak self] count in
            Task { @MainActor in
                guard let self else { return }
                self.publishHealth(sourceCount: count, failed: false)
                self.inventoryListener?(self.midi.sources)
            }
        }
        midi.setSourceLifecycleHandler { [weak router] event in
            if case .disconnected(let sourceID) = event {
                router?.handleMIDISourceDisconnected(sourceID)
            }
        }
        do {
            try midi.start()
            try? midiOut.start()
            midiSubsystemRunning = true
            publishHealth(sourceCount: midi.connectedCount, failed: false)
        } catch {
            midiSubsystemRunning = false
            publishHealth(sourceCount: 0, failed: true, errorMessage: PrismErrorReporting.userFacingMessage(for: error))
        }
        objectWillChange.send()
    }

    /// Push master/blackout/GO feedback to configured profiles.
    func sendMIDIFeedback(
        profiles: [MIDIFeedbackProfile],
        masterIntensity: Double,
        blackout: Bool,
        goPulse: Bool = false
    ) {
        midiOut.applyFeedback(
            profiles: profiles,
            masterIntensity: masterIntensity,
            blackout: blackout,
            goPulse: goPulse
        )
    }

    func applySavedRTPMIDI() {
        let config = RTPMIDIConfig.load()
        rtpMIDI.apply(config)
        if config.enabled {
            PrismLog.notice(.controlRTPMIDI, "control.rtpMIDI.started", "RTP-MIDI is on.")
            try? midi.connectAllSources()
            if midiSubsystemRunning {
                publishHealth(sourceCount: midi.connectedCount, failed: false, detail: rtpMIDI.statusLine())
            }
        }
    }

    func setRTPMIDIEnabled(_ enabled: Bool) {
        rtpMIDI.setEnabled(enabled)
        if enabled {
            try? midi.connectAllSources()
        }
        if midiSubsystemRunning {
            publishHealth(sourceCount: midi.connectedCount, failed: false, detail: rtpMIDI.statusLine())
        }
        PrismLog.notice(
            .controlRTPMIDI,
            enabled ? "control.rtpMIDI.started" : "control.rtpMIDI.stopped",
            rtpMIDI.statusLine()
        )
        objectWillChange.send()
    }

    /// OSC live dispatch runs on the network callback thread first (UI-GATE-2).
    /// Presentation updates hop to MainActor afterward only.
    func setOSCEnabled(
        _ enabled: Bool,
        router: ControlActionRouter,
        onUINotify: @escaping @MainActor (ShowAction, Float?) -> Void
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
            } catch {
                isOSCEnabled = false
                oscStatus = "OSC: error — \(PrismErrorReporting.userFacingMessage(for: error))"
            }
        } else {
            oscServer.stop()
            isOSCEnabled = false
            oscStatus = "OSC: off"
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
        router: ControlActionRouter
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
                    PrismLog.info(.controlMIDI, "control.midi.learned", "Prism learned a MIDI mapping.")
                } catch {
                    _ = PrismErrorReporting.statusMessage(for: error, operation: "learn MIDI", category: .controlMIDI)
                }
            }
        }
        refreshStatusLine(detail: lastMIDIEvent)
        objectWillChange.send()
    }

    private func publishHealth(sourceCount: Int, failed: Bool, errorMessage: String? = nil, detail: String? = nil) {
        if failed {
            midiHealth = .failed(errorMessage ?? "MIDI error")
        } else if !midiSubsystemRunning {
            midiHealth = .off
        } else {
            midiHealth = .running(sourceCount: sourceCount, detail: detail)
        }
        midiStatus = midiHealth.statusLine
        objectWillChange.send()
    }

    private func refreshStatusLine(detail: String?) {
        guard midiSubsystemRunning else {
            midiStatus = midiHealth.statusLine
            return
        }
        let count = midi.connectedCount
        if let detail, !detail.isEmpty {
            midiStatus = "MIDI: \(count) src · \(detail)"
            // Keep structured state; only the display line includes last event.
            if count > 0 {
                midiHealth = MIDIHealthSnapshot(
                    state: .ready,
                    connectedSourceCount: count,
                    lastError: nil,
                    statusLine: midiStatus
                )
            } else {
                midiHealth = MIDIHealthSnapshot(
                    state: .off,
                    connectedSourceCount: 0,
                    lastError: nil,
                    statusLine: midiStatus
                )
            }
        } else {
            publishHealth(sourceCount: count, failed: false)
        }
    }

    private func appendMIDILog(_ message: String) {
        midiLog.append(message)
        if midiLog.count > maxMIDILog {
            midiLog.removeFirst(midiLog.count - maxMIDILog)
        }
    }
}
