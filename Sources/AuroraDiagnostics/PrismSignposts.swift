import Foundation
import os.signpost

public enum PrismSignposts {
    public static let subsystem = UnifiedPrismLogger.subsystem
    private static let log = OSLog(subsystem: subsystem, category: .pointsOfInterest)

    public static let projectOpen: StaticString = "project.open"
    public static let projectSave: StaticString = "project.save"
    public static let engineFrame: StaticString = "engine.frame"
    public static let ameIngressToEmission: StaticString = "ame.ingress_to_emission"
    public static let outputStart: StaticString = "output.start"
    public static let outputStop: StaticString = "output.stop"

    public static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    public static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
