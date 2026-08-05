import CoreGraphics

/// UI-01C metrics — tight technical chrome, softer creative objects.
public enum AuroraMetrics {
    public static let radiusNone: CGFloat = 0
    public static let radiusTight: CGFloat = 3
    public static let radiusControl: CGFloat = 5
    public static let radiusSoft: CGFloat = 8
    public static let radiusTransport: CGFloat = 8
    public static let radiusPanel: CGFloat = 6

    public static let cornerRadiusSmall: CGFloat = radiusTight
    public static let cornerRadiusMedium: CGFloat = radiusControl
    public static let cornerRadiusLarge: CGFloat = radiusSoft

    public static let controlHeightCompact: CGFloat = 20
    public static let controlHeightStandard: CGFloat = 24
    public static let controlHeightPerformance: CGFloat = 40

    public static let rowHeightCompact: CGFloat = 22
    public static let rowHeightStandard: CGFloat = 26
    public static let rowHeightPerformance: CGFloat = 44
    public static let tableRowHeight: CGFloat = 24
    public static let tableHeaderHeight: CGFloat = 22

    public static let panelHeaderHeight: CGFloat = 28
    public static let toolbarHeight: CGFloat = 38
    public static let tabHeight: CGFloat = 26
    public static let statusBarHeight: CGFloat = 22

    public static let iconButtonSize: CGFloat = 24
    public static let iconPointSize: CGFloat = 11
    public static let statusDotSize: CGFloat = 6
    public static let statusDotEmphasis: CGFloat = 8

    public static let paletteTileWidth: CGFloat = 56
    public static let paletteSwatchHeight: CGFloat = 36
    public static let paletteTileSize: CGFloat = 56
    public static let colorChipSize: CGFloat = 18
    public static let beamIconSize: CGFloat = 28
    public static let lookTileWidth: CGFloat = 72
    public static let lookTileHeight: CGFloat = 48
    public static let presetTileMinWidth: CGFloat = 88
    public static let fixtureChipHeight: CGFloat = 36

    public static let faderTrackWidth: CGFloat = 8
    public static let faderThumbWidth: CGFloat = 20
    public static let faderThumbHeight: CGFloat = 8
    public static let faderThumbSize: CGFloat = 14
    public static let faderHeight: CGFloat = 140
    public static let faderWidth: CGFloat = 48
    public static let masterTrackHeight: CGFloat = 6
    public static let masterHeight: CGFloat = 36

    public static let colorWheelSize: CGFloat = 128
    public static let positionPadSize: CGFloat = 112
    public static let beamWellSize: CGFloat = 56

    public static let transportGOMinWidth: CGFloat = 56
    public static let transportSecondaryMinWidth: CGFloat = 48
    public static let transportMinHeight: CGFloat = 48
    public static let transportIconSize: CGFloat = 44

    public static let focusRingWidth: CGFloat = 1.5
    public static let railWidth: CGFloat = 3
    public static let hairline: CGFloat = 1
}
