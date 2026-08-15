import AuroraModel
import Foundation

/// Human-readable and CSV patch export (P0-C).
public enum PatchReport {
    public static func csv(project: ShowProject) -> String {
        var lines = ["Universe,Address,End,Name,Manufacturer,Model,Mode,Channels,FixtureID"]
        let sorted = project.fixtures.sorted { a, b in
            let ua = project.universe(id: a.universeId)?.number ?? 0
            let ub = project.universe(id: b.universeId)?.number ?? 0
            if ua != ub { return ua < ub }
            return a.address < b.address
        }
        for fx in sorted {
            let u = project.universe(id: fx.universeId)
            let def = project.definition(id: fx.definitionId)
            let ch = project.channelCount(for: fx)
            let end = fx.endAddress(channelCount: ch)
            let row = [
                "\(u?.number ?? 0)",
                "\(fx.address)",
                "\(end)",
                csvEscape(fx.name),
                csvEscape(def?.manufacturer ?? ""),
                csvEscape(def?.model ?? ""),
                csvEscape(def?.modeName ?? ""),
                "\(ch)",
                fx.id.uuidString,
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func humanReadable(project: ShowProject) -> String {
        var out = "Aurora Patch Report — \(project.metadata.name)\n"
        out += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        for u in project.universes.sorted(by: { $0.number < $1.number }) {
            out += "Universe \(u.number): \(u.name)  [\(u.protocolHint.rawValue)]\n"
            let fxs = project.fixtures.filter { $0.universeId == u.id }.sorted { $0.address < $1.address }
            if fxs.isEmpty {
                out += "  (empty)\n"
            }
            for fx in fxs {
                let def = project.definition(id: fx.definitionId)
                let ch = project.channelCount(for: fx)
                let end = fx.endAddress(channelCount: ch)
                let model = def.map { "\($0.manufacturer) \($0.model)" } ?? "missing profile"
                let namePad = fx.name.padding(toLength: 24, withPad: " ", startingAt: 0)
                out += String(format: "  %03d–%03d  %@  %@\n", fx.address, end, namePad, model)
            }
            out += "\n"
        }
        let conflicts = project.patchConflicts()
        if !conflicts.isEmpty {
            out += "WARNINGS: \(conflicts.count) patch overlap(s)\n"
        }
        return out
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
