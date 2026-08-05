import SwiftUI

public enum AuroraTransportKind: Sendable {
    case go
    case back
    case stop
    case pause
    case blackout
    case release

    public var title: String {
        switch self {
        case .go: return "GO"
        case .back: return "BACK"
        case .stop: return "STOP"
        case .pause: return "PAUSE"
        case .blackout: return "B/O"
        case .release: return "REL"
        }
    }

    public var systemImage: String? {
        switch self {
        case .go: return "play.fill"
        case .back: return "backward.fill"
        case .stop: return "stop.fill"
        case .pause: return "pause.fill"
        case .blackout: return "lightbulb.slash"
        case .release: return "arrow.uturn.backward"
        }
    }
}

/// Professional transport — green GO dominant; red blackout/stop.
public struct AuroraTransportButton: View {
    public var kind: AuroraTransportKind
    public var isEnabled: Bool
    public var useIcon: Bool
    public var action: () -> Void

    @Environment(\.auroraDensity) private var density
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(
        kind: AuroraTransportKind,
        isEnabled: Bool = true,
        useIcon: Bool = true,
        action: @escaping () -> Void
    ) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.useIcon = useIcon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if useIcon, let img = kind.systemImage, kind == .go || kind == .back || kind == .pause || kind == .stop {
                    Image(systemName: img)
                        .font(.system(size: kind == .go ? 18 : 12, weight: .bold))
                } else {
                    Text(kind.title)
                        .font(.system(size: kind == .go ? 12 : 9, weight: .bold))
                        .tracking(0.5)
                }
            }
            .foregroundStyle(foreground)
            .frame(width: side, height: side)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AuroraMetrics.radiusTransport, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraMetrics.radiusTransport, style: .continuous)
                    .strokeBorder(isFocused ? AuroraColor.focusRing : border, lineWidth: isFocused ? 2 : 0.5)
            )
            .shadow(color: kind == .go ? AuroraColor.goGreen.opacity(0.35) : .clear, radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel(kind.title)
    }

    private var side: CGFloat {
        if kind == .go {
            return density == .performance ? 56 : 48
        }
        return density == .performance ? 44 : 36
    }

    private var foreground: Color {
        switch kind {
        case .go: return AuroraColor.textOnGo
        case .blackout, .stop: return AuroraColor.textPrimary
        default: return AuroraColor.textPrimary
        }
    }

    private var background: Color {
        let hover = isHovered && isEnabled
        switch kind {
        case .go:
            return hover ? AuroraColor.goGreenBright : AuroraColor.goGreen
        case .blackout, .stop:
            return hover ? AuroraColor.critical.opacity(0.85) : AuroraColor.critical.opacity(0.65)
        case .back, .pause, .release:
            return hover ? AuroraColor.surfaceRaised : AuroraColor.surfaceRaised.opacity(0.9)
        }
    }

    private var border: Color {
        switch kind {
        case .go: return Color.white.opacity(0.12)
        case .blackout, .stop: return AuroraColor.critical.opacity(0.4)
        default: return AuroraColor.separatorStrong
        }
    }
}
