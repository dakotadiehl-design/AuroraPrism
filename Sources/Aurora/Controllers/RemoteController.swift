import AuroraEngine
import AuroraModel
import AuroraRemote
import Foundation

/// Web/TCP remote lifecycle and session policy (Stage C).
@MainActor
final class RemoteController: ObservableObject {
    let remoteHost = RemoteHost()
    private(set) var remoteWeb: RemoteWebServer?
    @Published private(set) var remoteStatus: String = "Remote: off"

    private var remoteSnapshotTimer: Timer?

    func stopAll() {
        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = nil
        remoteHost.stop()
        remoteWeb?.stop()
        remoteWeb = nil
    }

    func setRemoteEnabled(
        _ enabled: Bool,
        pin: String? = nil,
        onAction: @escaping @Sendable (RemoteShowAction) -> Void,
        makeSnapshot: @escaping () -> RemoteSnapshot,
        onLog: (String) -> Void
    ) {
        var config = remoteHost.sessions.configSnapshot
        config.enabled = enabled
        if enabled {
            let chosen = (pin?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            config.pin = chosen ?? RemoteHostConfig.generatePIN()
        }
        remoteHost.sessions.updateConfig(config)
        if enabled {
            remoteHost.setActionHandler(onAction)
            let web = RemoteWebServer(sessions: remoteHost.sessions, port: 8743)
            web.setActionHandler(onAction)
            remoteWeb = web
            do {
                try remoteHost.start()
                try web.start()
                let activePIN = remoteHost.sessions.configSnapshot.pin
                remoteStatus = "Remote TCP :\(config.port) · Web :8743 · PIN \(activePIN)"
                onLog("Remote TCP \(config.port) + web 8743 · PIN \(activePIN)")
                startRemoteSnapshotTimer(makeSnapshot: makeSnapshot)
            } catch {
                remoteStatus = "Remote: error"
                onLog("Remote start failed: \(error.localizedDescription)")
            }
        } else {
            remoteSnapshotTimer?.invalidate()
            remoteSnapshotTimer = nil
            remoteHost.stop()
            remoteWeb?.stop()
            remoteWeb = nil
            remoteStatus = "Remote: off"
            onLog("Remote stopped")
        }
        objectWillChange.send()
    }

    private func startRemoteSnapshotTimer(makeSnapshot: @escaping () -> RemoteSnapshot) {
        remoteSnapshotTimer?.invalidate()
        remoteSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let snap = makeSnapshot()
                self.remoteHost.setSnapshotProvider { snap }
                self.remoteWeb?.setSnapshotProvider { snap }
                self.remoteHost.broadcastSnapshot()
            }
        }
    }

    func setLockedToViewer(_ locked: Bool) {
        remoteHost.sessions.setLockedToViewer(locked)
        remoteStatus = locked ? "Remote: locked (viewer)" : "Remote: operators allowed"
        objectWillChange.send()
    }

    func kickAll(onAction: @escaping @Sendable (RemoteShowAction) -> Void, onLog: (String) -> Void) {
        let ids = remoteHost.sessions.kickAll()
        if remoteHost.sessions.configSnapshot.enabled, let web = remoteWeb {
            web.stop()
            let fresh = RemoteWebServer(sessions: remoteHost.sessions, port: web.port)
            fresh.setActionHandler(onAction)
            remoteWeb = fresh
            try? fresh.start()
        }
        onLog("Kicked \(ids.count) remote client(s)")
        objectWillChange.send()
    }

    func makeRemoteSnapshot(
        project: ShowProject,
        engine: LightingEngine,
        song: SongPerformanceSnapshot,
        songStatusFallback: String
    ) -> RemoteSnapshot {
        let engineSnap = engine.currentSnapshot()
        let pb = engineSnap.playback
        // UI-GATE-4: total active channels across all universes (matches PerformanceSnapshot).
        let active = PerformanceSnapshot.activeChannelTotals(universeLevels: engineSnap.universeLevels).channels
        var cueName: String?
        if pb.cueIndex >= 0,
           let list = project.cueLists.first(where: { $0.id == pb.listID })
            ?? project.cueLists.first,
           list.cues.indices.contains(pb.cueIndex) {
            cueName = list.cues[pb.cueIndex].name
        }
        return RemoteSnapshot(
            showName: project.metadata.name,
            engineRunning: engine.isRunning,
            cueIndex: pb.cueIndex,
            cueName: cueName,
            songTitle: song.songTitle.isEmpty ? (songStatusFallback.isEmpty ? nil : songStatusFallback) : song.songTitle,
            songEntryIndex: song.entryIndex,
            locked: remoteHost.sessions.configSnapshot.lockedToViewer,
            role: .operatorRole,
            activeChannelCount: active
        )
    }
}
