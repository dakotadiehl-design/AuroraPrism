import SwiftUI

/// UI-01C typography — dense professional hierarchy matching render pack.
public enum AuroraTypography {
    public static let windowTitle = Font.system(size: 13, weight: .semibold, design: .default)
    public static let workspaceTitle = Font.system(size: 12, weight: .semibold, design: .default)
    public static let panelTitle = Font.system(size: 11, weight: .semibold, design: .default)
    public static let sectionHeading = Font.system(size: 10, weight: .semibold, design: .default)
    public static let body = Font.system(size: 11, weight: .regular, design: .default)
    public static let secondary = Font.system(size: 11, weight: .regular, design: .default)
    public static let controlLabel = Font.system(size: 9, weight: .semibold, design: .default)
    public static let compactLabel = Font.system(size: 9, weight: .medium, design: .default)
    public static let metadata = Font.system(size: 9, weight: .regular, design: .default)
    public static let status = Font.system(size: 9, weight: .semibold, design: .default)
    public static let tab = Font.system(size: 10, weight: .medium, design: .default)
    public static let tableHeader = Font.system(size: 9, weight: .semibold, design: .default)
    public static let tableCell = Font.system(size: 11, weight: .regular, design: .default)

    public static let primaryValue = Font.system(size: 12, weight: .semibold, design: .default).monospacedDigit()
    public static let secondaryValue = Font.system(size: 10, weight: .medium, design: .default).monospacedDigit()
    public static let faderValue = Font.system(size: 13, weight: .bold, design: .default).monospacedDigit()
    public static let cueNumber = Font.system(size: 11, weight: .semibold, design: .monospaced)
    public static let timingReadout = Font.system(size: 10, weight: .medium, design: .default).monospacedDigit()

    /// Perform Mode giant cue numeral.
    public static let performCueNumber = Font.system(size: 56, weight: .semibold, design: .default).monospacedDigit()
    public static let performancePrimary = Font.system(size: 22, weight: .semibold, design: .default)
    public static let performanceSecondary = Font.system(size: 13, weight: .medium, design: .default)

    public static let wordmark = Font.system(size: 13, weight: .bold, design: .default)
    public static let numericReadout = primaryValue
}
