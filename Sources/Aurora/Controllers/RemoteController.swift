import AuroraEngine
import AuroraModel
import AuroraRemote
import Foundation

/// Web/TCP remote lifecycle and session policy (Stage C / REM second-pass).
@MainActor
final class RemoteController: ObservableObject {
    let remoteHost = RemoteHost()
    private(set) var remoteWeb: RemoteWebServer?
    @Published private(set) var remoteStatus: String = "Remote: off"
    /// True only when both required listeners are actually `.ready` (REM-01).
    @Published private(set) var isActuallyRunning: Bool = false
    @Published private(set) var tcpListenerState: RemoteListenerState = .stopped
    @Published private(set) var webListenerState: RemoteListenerState = .stopped

    private var remoteSnapshotTimer: Timer?
    private var lastWebPort: UInt16 = 8743
    private var lastBindLabel: String = "this Mac"
    private var lastPort: UInt16 = 8742
    private var generation: UInt64 = 0

    func stopAll() {
        generation &+= 1
        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = nil
        remoteHost.setStateHandler { _ in }
        remoteWeb?.setStateHandler { _ in }
        remoteHost.stop()
        remoteWeb?.stop()
        remoteWeb = nil
        tcpListenerState = .stopped
        webListenerState = .stopped
        isActuallyRunning = false
        remoteStatus = "Remote: off"
    }

    /// Authoritative remote configure+start. Config applied before listeners; ready only after NW ready.
    func setRemoteEnabled(
        _ enabled: Bool,
        pin: String? = nil,
        port: UInt16 = 8742,
        webPort: UInt16 = 8743,
        bindPolicy: RemoteBindPolicy = .loopbackOnly,
        onAction: @escaping @Sendable (RemoteShowAction) -> Void,
        makeSnapshot: @escaping () -> RemoteSnapshot,
        onLog: @escaping (String) -> Void
    ) {
        generation &+= 1
        let gen = generation

        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = nil
        remoteHost.setStateHandler { _ in }
        remoteWeb?.setStateHandler { _ in }
        remoteHost.stop()
        remoteWeb?.stop()
        remoteWeb = nil
        tcpListenerState = .stopped
        webListenerState = .stopped
        isActuallyRunning = false

        var config = remoteHost.sessions.configSnapshot
        config.enabled = enabled
        config.port = port
        config.bindPolicy = bindPolicy
        if enabled {
            let chosen = (pin?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            config.pin = chosen ?? RemoteHostConfig.generatePIN()
        }
        remoteHost.sessions.updateConfig(config)

        guard enabled else {
            remoteStatus = "Remote: off"
            onLog("Remote stopped")
            return
        }

        lastPort = port
        lastWebPort = webPort
        switch bindPolicy {
        case .loopbackOnly: lastBindLabel = "this Mac"
        case .privateLAN, .allInterfaces: lastBindLabel = "all interfaces"
        }

        remoteHost.setActionHandler(onAction)

        let web = RemoteWebServer(sessions: remoteHost.sessions, port: webPort)
        web.setActionHandler(onAction)
        remoteWeb = web

        // Seed snapshot once on MainActor; timer keeps provider updated.
        let initial = makeSnapshot()
        remoteHost.setSnapshotProvider { initial }
        web.setSnapshotProvider { initial }

        remoteStatus = "Remote starting · TCP :\(port) · Web :\(webPort)…"
        onLog("Remote starting TCP \(port) + web \(webPort)")

        remoteHost.setStateHandler { [weak self] state in
            Task { @MainActor in
                self?.noteTCPState(state, generation: gen, onLog: onLog)
            }
        }
        web.setStateHandler { [weak self] state in
            Task { @MainActor in
                self?.noteWebState(state, generation: gen, onLog: onLog)
            }
        }

        do {
            try remoteHost.start()
            try web.start()
            startRemoteSnapshotTimer(makeSnapshot: makeSnapshot)
        } catch {
            failAll(reason: error.localizedDescription, generation: gen, onLog: onLog)
        }
    }

    private func noteTCPState(_ state: RemoteListenerState, generation gen: UInt64, onLog: @escaping (String) -> Void) {
        guard gen == generation else { return }
        tcpListenerState = state
        reconcileListenerStates(onLog: onLog)
    }

    private func noteWebState(_ state: RemoteListenerState, generation gen: UInt64, onLog: @escaping (String) -> Void) {
        guard gen == generation else { return }
        webListenerState = state
        reconcileListenerStates(onLog: onLog)
    }

    private func reconcileListenerStates(onLog: (String) -> Void) {
        if tcpListenerState.isFailed || webListenerState.isFailed {
            let reason: String
            if case .failed(let r) = tcpListenerState {
                reason = "TCP: \(r)"
            } else if case .failed(let r) = webListenerState {
                reason = "Web: \(r)"
            } else {
                reason = "listener failed"
            }
            failAll(reason: reason, generation: generation, onLog: onLog)
            return
        }

        let tcpReady = tcpListenerState.isReady
        let webReady = webListenerState.isReady
        if tcpReady && webReady {
            isActuallyRunning = true
            var tcpEP = ":\(lastPort)"
            var webEP = ":\(lastWebPort)"
            if case .ready(let e) = tcpListenerState { tcpEP = e }
            if case .ready(let e) = webListenerState { webEP = e }
            remoteStatus = "Remote on · TCP \(tcpEP) · Web \(webEP) · \(lastBindLabel)"
        } else if case .starting = tcpListenerState, case .starting = webListenerState {
            isActuallyRunning = false
            remoteStatus = "Remote starting · TCP :\(lastPort) · Web :\(lastWebPort)…"
        } else if tcpReady || webReady {
            // Partial — still waiting for the other; not fully running yet.
            isActuallyRunning = false
            remoteStatus = "Remote starting · waiting for listeners…"
        }
    }

    private func failAll(reason: String, generation gen: UInt64, onLog: (String) -> Void) {
        guard gen == generation else { return }
        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = nil
        remoteHost.setStateHandler { _ in }
        remoteWeb?.setStateHandler { _ in }
        remoteHost.stop()
        remoteWeb?.stop()
        remoteWeb = nil
        tcpListenerState = .stopped
        webListenerState = .stopped
        isActuallyRunning = false
        // Keep sessions.config.enabled for re-apply; actualRunning is the runtime truth.
        remoteStatus = "Remote: error — \(reason)"
        onLog("Remote failed: \(reason)")
    }

    private func startRemoteSnapshotTimer(makeSnapshot: @escaping () -> RemoteSnapshot) {
        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // REM-07: periodic idle reclaim so client count self-heals.
                _ = self.remoteHost.sessions.reclaimInactive()
                let snap = makeSnapshot()
                self.remoteHost.setSnapshotProvider { snap }
                self.remoteWeb?.setSnapshotProvider { snap }
                self.remoteHost.broadcastSnapshot()
            }
        }
    }

    func setLockedToViewer(_ locked: Bool) {
        remoteHost.sessions.setLockedToViewer(locked)
        if isActuallyRunning {
            remoteStatus = locked ? "Remote: locked (viewer)" : "Remote: operators allowed"
        }
    }

    func kickAll(onAction: @escaping @Sendable (RemoteShowAction) -> Void, onLog: (String) -> Void) {
        let ids = remoteHost.sessions.kickAll()
        onLog("Kicked \(ids.count) remote client(s)")
        // Tokens already invalidated; web clients must re-auth (REM-03).
        // Do not restart listeners — kick is not a rebind.
    }

    private var snapshotRevision: UInt64 = 0

    /// Monotonic revision for command acks (REM-05). Snapshot timer also bumps this.
    var currentSnapshotRevision: UInt64 { snapshotRevision }

    func makeRemoteSnapshot(
        project: ShowProject,
        engine: LightingEngine,
        song: SongPerformanceSnapshot,
        songStatusFallback: String,
        outputStatusLine: String = ""
    ) -> RemoteSnapshot {
        let engineSnap = engine.currentSnapshot()
        let pb = engineSnap.playback
        let active = PerformanceSnapshot.activeChannelTotals(universeLevels: engineSnap.universeLevels).channels
        let songCtx = SongCueResolveContext(
            songID: song.songID,
            entryIndex: song.entryIndex,
            entryCount: song.entryCount,
            currentEntryLabel: song.currentEntryLabel,
            nextEntryLabel: song.nextEntryLabel
        )
        let (current, next) = PerformanceCuePresentation.resolveCues(
            project: project,
            playback: pb,
            song: songCtx
        )
        snapshotRevision &+= 1
        return RemoteSnapshot(
            snapshotRevision: snapshotRevision,
            showName: project.metadata.name,
            engineRunning: engine.isRunning,
            cueIndex: pb.cueIndex,
            cueName: current.name.isEmpty ? nil : current.name,
            currentCue: RemoteCueSummaryDTO(
                listID: current.listID,
                cueID: current.cueID,
                numberDisplay: current.numberDisplay,
                name: current.name,
                sectionLabel: current.sectionLabel
            ),
            nextCue: RemoteCueSummaryDTO(
                listID: next.listID,
                cueID: next.cueID,
                numberDisplay: next.numberDisplay,
                name: next.name,
                sectionLabel: next.sectionLabel
            ),
            songTitle: song.songTitle.isEmpty ? (songStatusFallback.isEmpty ? nil : songStatusFallback) : song.songTitle,
            songEntryIndex: song.entryIndex,
            locked: remoteHost.sessions.configSnapshot.lockedToViewer,
            role: .operatorRole,
            activeChannelCount: active,
            outputStatusLine: outputStatusLine,
            masterIntensity: engine.globalShowControl.masterIntensity,
            blackout: engine.globalShowControl.blackout
        )
    }
}
