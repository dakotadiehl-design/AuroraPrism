import SwiftUI

/// UI-01C tokens tuned to high-fidelity render pack.
/// Fixture/palette/show content colors are data, not brand tokens.
public enum AuroraColor {
    // MARK: Surface hierarchy (app → workspace → panel → control → active)

    /// Near-black application chrome (render shell).
    public static let surfaceBase = Color(red: 0.04, green: 0.04, blue: 0.05)

    /// Continuous modular workspace behind panels.
    public static let surfaceWorkspace = Color(red: 0.06, green: 0.06, blue: 0.075)

    /// Inset elevated panel body.
    public static let surfacePanel = Color(red: 0.09, green: 0.09, blue: 0.11)

    /// Panel title bars / secondary bands.
    public static let surfaceHeader = Color(red: 0.075, green: 0.075, blue: 0.09)

    /// Raised interactive controls, wells, chips background.
    public static let surfaceRaised = Color(red: 0.12, green: 0.12, blue: 0.145)

    /// Deep wells (fader tracks, position pad, color wheel backdrop).
    public static let surfaceWell = Color(red: 0.03, green: 0.03, blue: 0.04)

    /// Tree/cue selection — readable purple wash (not full flood).
    public static let surfaceSelected = Color(red: 0.22, green: 0.14, blue: 0.38).opacity(0.55)

    /// Current / active row.
    public static let surfaceActive = Color(red: 0.18, green: 0.12, blue: 0.32).opacity(0.4)

    public static let separator = Color.white.opacity(0.06)
    public static let separatorStrong = Color.white.opacity(0.11)

    // MARK: Text

    public static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.97)
    public static let textSecondary = Color(red: 0.62, green: 0.62, blue: 0.68)
    public static let textTertiary = Color(red: 0.42, green: 0.42, blue: 0.48)
    public static let textOnAccent = Color.white
    public static let textOnGo = Color.white

    // MARK: Aurora accent (luminous indigo-violet — deliberate, not wallpaper)

    /// Primary brand / selection / BUILD / fader fill.
    public static let accent = Color(red: 0.52, green: 0.38, blue: 0.98)
    public static let accentBright = Color(red: 0.62, green: 0.48, blue: 1.0)
    public static let accentMuted = Color(red: 0.52, green: 0.38, blue: 0.98).opacity(0.22)
    public static let accentOwned = Color(red: 0.62, green: 0.45, blue: 1.0)
    public static let accentSubtle = accentMuted

    // MARK: Attribute-state legend (render board)

    public static let stateOwned = accentOwned
    public static let stateTracking = Color(red: 0.35, green: 0.82, blue: 0.48)
    public static let statePaletteRef = Color(red: 0.95, green: 0.62, blue: 0.22)
    public static let stateMixed = Color(red: 0.92, green: 0.92, blue: 0.94)
    public static let stateUnavailable = Color.white.opacity(0.28)

    // MARK: Transport / health

    public static let goGreen = Color(red: 0.22, green: 0.78, blue: 0.42)
    public static let goGreenBright = Color(red: 0.30, green: 0.88, blue: 0.50)
    public static let success = Color(red: 0.30, green: 0.78, blue: 0.45)
    public static let successMuted = Color(red: 0.30, green: 0.78, blue: 0.45).opacity(0.45)
    public static let warning = Color(red: 0.95, green: 0.70, blue: 0.22)
    public static let warningMuted = Color(red: 0.95, green: 0.70, blue: 0.22).opacity(0.14)
    public static let critical = Color(red: 0.92, green: 0.28, blue: 0.32)
    public static let criticalMuted = Color(red: 0.92, green: 0.28, blue: 0.32).opacity(0.18)
    public static let disabled = Color.white.opacity(0.22)

    public static let masterTrack = Color(red: 0.48, green: 0.36, blue: 0.92)
    public static let masterTrackDim = Color(red: 0.48, green: 0.36, blue: 0.92).opacity(0.35)

    // MARK: Interaction

    public static let focusRing = Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.9)
    public static let hoverOverlay = Color.white.opacity(0.04)
    public static let pressedOverlay = Color.black.opacity(0.25)
    public static let railCurrent = accent
    public static let railNext = Color.white.opacity(0.22)
    public static let railWarning = warning
}
