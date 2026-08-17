import AuroraModel
import AuroraMusical
import Foundation

/// Single conversion path between persisted show meter and Musical Engine meter.
public enum MusicalMeterBridge {
    public static func musical(from show: ShowMusicalMeter) throws -> MusicalMeter {
        try MusicalMeter(
            numerator: show.numerator,
            denominator: show.denominator,
            beatGrouping: show.beatGrouping
        )
    }

    public static func show(from musical: MusicalMeter) -> ShowMusicalMeter {
        ShowMusicalMeter.must(
            numerator: musical.numerator,
            denominator: musical.denominator,
            beatGrouping: musical.beatGrouping
        )
    }
}
