import SwiftUI

/// Short state transitions only — no decorative continuous motion in work UI.
public enum AuroraAnimation {
    public static let selection = Animation.easeInOut(duration: 0.12)
    public static let press = Animation.easeOut(duration: 0.08)
    public static let health = Animation.easeInOut(duration: 0.2)
    public static let panel = Animation.easeInOut(duration: 0.18)

    /// Prefer reduced-motion when the system requests it.
    public static func selection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : selection
    }
}
