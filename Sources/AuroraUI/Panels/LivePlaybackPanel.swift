import AppKit
import AuroraEngine
import SwiftUI

/// Large on-screen transport for live operators.
public struct LivePlaybackPanel: View {
    public var snapshot: EngineFrameSnapshot
    public var onGo: () -> Void
    public var onStop: () -> Void
    public var onBack: () -> Void
    public var isBlind: Bool
    public var isHighlight: Bool
    public var onBlind: (Bool) -> Void
    public var onHighlight: (Bool) -> Void

    public init(
        snapshot: EngineFrameSnapshot,
        onGo: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onBack: @escaping () -> Void,
        isBlind: Bool = false,
        isHighlight: Bool = false,
        onBlind: @escaping (Bool) -> Void = { _ in },
        onHighlight: @escaping (Bool) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.onGo = onGo
        self.onStop = onStop
        self.onBack = onBack
        self.isBlind = isBlind
        self.isHighlight = isHighlight
        self.onBlind = onBlind
        self.onHighlight = onHighlight
    }

    private var pb: PlaybackSnapshot { snapshot.playback }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(cueTitle)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(phaseLabel)
                    .font(.title3.monospaced())
                    .foregroundStyle(.secondary)
                if pb.phase == .fade {
                    ProgressView(value: pb.fadeProgress)
                        .padding(.horizontal, 40)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            HStack(spacing: 16) {
                Button(action: onBack) {
                    label("BACK", systemImage: "backward.fill")
                }
                .buttonStyle(LiveTransportButtonStyle(color: .secondary))
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button(action: onGo) {
                    label("GO", systemImage: "play.fill")
                }
                .buttonStyle(LiveTransportButtonStyle(color: .green))
                .keyboardShortcut(.space, modifiers: [])
                .keyboardShortcut(.return, modifiers: [])

                Button(action: onStop) {
                    label("STOP", systemImage: "stop.fill")
                }
                .buttonStyle(LiveTransportButtonStyle(color: .red))
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24)

            HStack(spacing: 20) {
                Toggle("Blind", isOn: Binding(get: { isBlind }, set: onBlind))
                Toggle("Highlight", isOn: Binding(get: { isHighlight }, set: onHighlight))
            }
            .toggleStyle(.switch)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var cueTitle: String {
        if pb.cueIndex < 0 {
            return "No cue"
        }
        let name = pb.cueName.isEmpty ? "Cue \(pb.cueIndex + 1)" : pb.cueName
        return "#\(pb.cueIndex + 1)  \(name)"
    }

    private var phaseLabel: String {
        switch pb.phase {
        case .idle: return "IDLE"
        case .delay: return "DELAY"
        case .fade: return String(format: "FADE %.0f%%", pb.fadeProgress * 100)
        case .active: return "ACTIVE"
        }
    }

    private func label(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title)
            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
    }
}

private struct LiveTransportButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
