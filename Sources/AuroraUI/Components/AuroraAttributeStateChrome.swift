import SwiftUI

/// Attribute state markers aligned to render legend.
public enum AuroraAttributeVisualState: String, Sendable, CaseIterable {
    case untouched
    case programmerOwned
    case inherited
    case paletteReferenced
    case mixed
    case unavailable

    public var label: String {
        switch self {
        case .untouched: return "·"
        case .programmerOwned: return "P"
        case .inherited: return "T"
        case .paletteReferenced: return "R"
        case .mixed: return "M"
        case .unavailable: return "∅"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .untouched: return "untouched"
        case .programmerOwned: return "programmer owned"
        case .inherited: return "inherited or tracked"
        case .paletteReferenced: return "palette referenced"
        case .mixed: return "mixed"
        case .unavailable: return "unavailable"
        }
    }

    public var color: Color {
        switch self {
        case .untouched: return AuroraColor.textTertiary
        case .programmerOwned: return AuroraColor.stateOwned
        case .inherited: return AuroraColor.stateTracking
        case .paletteReferenced: return AuroraColor.statePaletteRef
        case .mixed: return AuroraColor.stateMixed
        case .unavailable: return AuroraColor.stateUnavailable
        }
    }

    public var legendTitle: String {
        switch self {
        case .untouched: return "Untouched"
        case .programmerOwned: return "Programmer Owned"
        case .inherited: return "Inherited (Tracking)"
        case .paletteReferenced: return "Palette Reference"
        case .mixed: return "Mixed Values"
        case .unavailable: return "Unavailable"
        }
    }
}

public struct AuroraAttributeStateChrome: View {
    public var state: AuroraAttributeVisualState

    public init(state: AuroraAttributeVisualState) {
        self.state = state
    }

    public var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
            )
            .accessibilityLabel(state.accessibilityLabel)
            .help(state.legendTitle)
    }
}

public struct AuroraAttributeStateLegend: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(
                [
                    AuroraAttributeVisualState.programmerOwned,
                    .inherited,
                    .paletteReferenced,
                    .mixed,
                    .unavailable,
                ],
                id: \.self
            ) { state in
                HStack(spacing: 4) {
                    AuroraAttributeStateChrome(state: state)
                    Text(state.legendTitle)
                        .font(AuroraTypography.metadata)
                        .foregroundStyle(AuroraColor.textTertiary)
                }
            }
        }
    }
}
