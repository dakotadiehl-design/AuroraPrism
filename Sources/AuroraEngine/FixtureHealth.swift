import AuroraModel
import AuroraOutput
import Foundation

/// Per-fixture control-chain health (A4 / P0-L+).
public struct FixtureHealthReport: Equatable, Sendable, Identifiable {
    public var id: UUID { fixtureID }
    public var fixtureID: UUID
    public var fixtureName: String
    public var issues: [String]
    public var notes: [String]

    public var isHealthy: Bool { issues.isEmpty }

    public init(fixtureID: UUID, fixtureName: String, issues: [String] = [], notes: [String] = []) {
        self.fixtureID = fixtureID
        self.fixtureName = fixtureName
        self.issues = issues
        self.notes = notes
    }
}

public enum FixtureHealth {
    public static func report(
        project: ShowProject,
        output: OutputPresentationSnapshot,
        artNetEnabled: Bool,
        sacnEnabled: Bool,
        localDMXEnabled: Bool
    ) -> [FixtureHealthReport] {
        let overlaps = Set(project.patchConflicts().flatMap { [$0.first, $0.second] })
        return project.fixtures.map { fx in
            var issues: [String] = []
            var notes: [String] = []
            guard let def = project.definition(id: fx.definitionId) else {
                issues.append("Fixture profile missing")
                return FixtureHealthReport(fixtureID: fx.id, fixtureName: fx.name, issues: issues)
            }
            notes.append("Profile valid (\(def.displayName))")
            if project.universe(id: fx.universeId) == nil {
                issues.append("Universe missing")
            } else if let u = project.universe(id: fx.universeId) {
                switch u.protocolHint {
                case .none:
                    notes.append("Universe \(u.number) has no output route")
                case .artNet:
                    if !artNetEnabled { issues.append("Art-Net not enabled") }
                    else { notes.append("Routed Art-Net") }
                case .sACN:
                    if !sacnEnabled { issues.append("sACN not enabled") }
                    else { notes.append("Routed sACN") }
                case .local:
                    if !localDMXEnabled { notes.append("Local DMX not running") }
                    else { notes.append("Routed Local DMX") }
                case .mirror:
                    notes.append("Routed mirror")
                }
                let end = fx.endAddress(channelCount: project.channelCount(for: fx))
                if end > u.channelCount {
                    issues.append("Footprint past universe capacity")
                }
            }
            if overlaps.contains(fx.id) {
                issues.append("Patch overlap")
            }
            if !fx.isPatched {
                notes.append("Unpatched (no DMX address)")
            }
            switch output.aggregate {
            case .failed:
                notes.append("Output aggregate failed")
            case .disabled:
                notes.append("No physical output active")
            default:
                break
            }
            notes.append("Physical device status unknown")
            return FixtureHealthReport(
                fixtureID: fx.id,
                fixtureName: fx.name,
                issues: issues,
                notes: notes
            )
        }
    }
}
