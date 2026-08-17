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
    public static let auroraButtonRadius: CGFloat = 6
    public static let auroraButtonShellInset: CGFloat = 2
    public static let auroraButtonIndicatorWidth: CGFloat = 18
    public static let auroraButtonIndicatorHeight: CGFloat = 1.5
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

    // MARK: Option C value-thumb fader (vertical only)
    // Travel = thumb-center travel. Channel height = travel + thumbHeight.

    public static let valueFaderWidth: CGFloat = 72
    /// Narrow console rail; the larger value thumb intentionally overhangs both sides.
    public static let valueFaderChannelWidth: CGFloat = 28
    public static let valueFaderTrackWidth: CGFloat = 12
    public static let valueFaderThumbWidth: CGFloat = 64
    public static let valueFaderThumbHeight: CGFloat = 30
    public static let valueFaderThumbRadius: CGFloat = 8
    public static let valueFaderTravel: CGFloat = 160
    public static let valueFaderTravelCompact: CGFloat = 140
    public static let valueFaderTickInset: CGFloat = 4
    public static let valueFaderFocusRingWidth: CGFloat = 2

    public static let valueFaderWidthPerformance: CGFloat = 80
    public static let valueFaderChannelWidthPerformance: CGFloat = 32
    public static let valueFaderTrackWidthPerformance: CGFloat = 14
    public static let valueFaderThumbWidthPerformance: CGFloat = 72
    public static let valueFaderThumbHeightPerformance: CGFloat = 34
    public static let valueFaderThumbRadiusPerformance: CGFloat = 9
    public static let valueFaderTravelPerformance: CGFloat = 190
    public static let valueFaderTickInsetPerformance: CGFloat = 5

    public static var valueFaderChannelHeight: CGFloat {
        valueFaderTravel + valueFaderThumbHeight
    }
    public static var valueFaderChannelHeightPerformance: CGFloat {
        valueFaderTravelPerformance + valueFaderThumbHeightPerformance
    }
    public static var valueFaderChannelHeightCompact: CGFloat {
        valueFaderTravelCompact + valueFaderThumbHeight
    }

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
