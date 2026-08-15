import AuroraOutput
import AuroraUI
import Foundation

/// Single semantic health mapping for toolbar, status bar, and Perform (UI-02 C4 / ST-01).
struct AuroraShellHealthSnapshot: Equatable, Sendable {
    var engine: AuroraHealthLevel
    var output: AuroraHealthLevel
    var midi: AuroraHealthLevel
    /// Omit from UI when nil (no truthful aggregate network contract yet).
    var network: AuroraHealthLevel?

    static func build(
        engineRunning: Bool,
        output: OutputPresentationSnapshot,
        midi: MIDIHealthSnapshot
    ) -> AuroraShellHealthSnapshot {
        let midiLevel: AuroraHealthLevel
        switch midi.state {
        case .off: midiLevel = .disabled
        case .ready: midiLevel = .healthy
        case .warning: midiLevel = .warning
        case .failed: midiLevel = .failed
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
            midi: midiLevel,
            network: nil
        )
    }

    /// Back-compat string path — prefer structured `MIDIHealthSnapshot`.
    static func build(
        engineRunning: Bool,
        output: OutputPresentationSnapshot,
        midiStatus: String
    ) -> AuroraShellHealthSnapshot {
        build(
            engineRunning: engineRunning,
            output: output,
            midi: MIDIHealthSnapshot.fromLegacyStatusString(midiStatus)
        )
    }
}
