import AuroraUI
import SwiftUI

/// Bottom status strip — uses shared shell health (UI-02 C4).
struct AuroraAppStatusBar: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let health = AuroraShellHealthSnapshot.build(
            engineRunning: appModel.performance.engineRunning,
            output: appModel.output.presentationSnapshot(),
            midiStatus: appModel.midiStatus
        )
        let items: [AuroraStatusBarItem] = [
            .init(
                id: "engine",
                label: appModel.performance.engineRunning
                    ? String(format: "Engine %.0f Hz", appModel.performance.frameRateHz)
                    : "Engine",
                level: health.engine
            ),
            .init(id: "output", label: shortOutput(health.output), level: health.output),
            .init(id: "midi", label: "MIDI", level: health.midi),
            .init(
                id: "fx",
                label: "\(appModel.session.project.fixtures.count) fixtures",
                level: .healthy
            ),
        ]

        AuroraStatusBar(
            items: items,
            trailing: appModel.statusMessage.isEmpty
                ? "Frame \(appModel.performance.frameIndex)"
                : appModel.statusMessage
        )
    }

    private func shortOutput(_ level: AuroraHealthLevel) -> String {
        switch level {
        case .healthy: return "Output OK"
        case .warning: return "Output warn"
        case .failed: return "Output fail"
        case .disabled, .unknown: return "Output off"
        }
    }
}
