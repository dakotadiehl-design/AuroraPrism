import Foundation

/// Fan / align helpers for multi-fixture programmer edits.
public enum ProgrammerGeometry {
    /// Same value for every fixture id (order irrelevant).
    public static func align(fixtureIDs: [UUID], value: Double) -> [UUID: Double] {
        let v = min(1, max(0, value))
        var result: [UUID: Double] = [:]
        for id in fixtureIDs {
            result[id] = v
        }
        return result
    }

    /// Linear fan from `start` to `end` across ordered fixture ids.
    public static func fan(fixtureIDs: [UUID], start: Double, end: Double) -> [UUID: Double] {
        guard !fixtureIDs.isEmpty else { return [:] }
        if fixtureIDs.count == 1 {
            return [fixtureIDs[0]: min(1, max(0, start))]
        }
        var result: [UUID: Double] = [:]
        let last = Double(fixtureIDs.count - 1)
        for (i, id) in fixtureIDs.enumerated() {
            let t = Double(i) / last
            let v = start + (end - start) * t
            result[id] = min(1, max(0, v))
        }
        return result
    }
}
