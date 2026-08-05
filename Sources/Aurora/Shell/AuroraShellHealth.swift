import AuroraOutput
import AuroraUI
import Foundation

/// Single semantic health mapping for toolbar, status bar, and Perform (UI-02 C4).
struct AuroraShellHealthSnapshot: Equatable, Sendable {
    var engine: AuroraHealthLevel
    var output: AuroraHealthLevel
    var midi: AuroraHealthLevel
    /// Omit from UI when nil (no truthful aggregate network contract yet).
    var network: AuroraHealthLevel?

    static func build(
        engineRunning: Bool,
        output: OutputPresentationSnapshot,
        midiStatus: String
    ) -> AuroraShellHealthSnapshot {
        let midiLower = midiStatus.lowercased()
        let midi: AuroraHealthLevel
        if midiLower.contains("error") || midiLower.contains("fail") {
            midi = .warning
        } else if midiLower.contains("off") || midiLower.isEmpty {
            midi = .disabled
        } else {
            midi = .healthy
        }

        let out: AuroraHealthLevel
        switch output.aggregate {
        case .healthy: out = .healthy
        case .warning: out = .warning
        case .failed: out = .failed
        case .disabled: out = .disabled
        }

        return AuroraShellHealthSnapshot(
            engine: engineRunning ? .healthy : .disabled,
            output: out,
            midi: midi,
            network: nil
        )
    }
}
