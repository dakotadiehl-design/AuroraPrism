import AuroraModel
import Foundation

/// Builds per-universe DMX from patch + a single `ActiveLook` (home/default + look).
public enum MergeStub {
    /// Scales normalized 0…1 to 8-bit DMX.
    public static func dmxValue(normalized: Double) -> UInt8 {
        let clamped = min(1, max(0, normalized))
        return UInt8(clamped * 255.0 + 0.5)
    }

    /// Merge into universe-number-keyed channel arrays.
    public static func merge(
        project: ShowProject,
        look: ActiveLook,
        channelCount: Int = 512
    ) -> [UInt16: [UInt8]] {
        var result: [UInt16: [UInt8]] = [:]

        for universe in project.universes {
            let count = Int(universe.channelCount)
            result[universe.number] = Array(repeating: 0, count: max(count, channelCount))
        }

        // Ensure universes referenced only by fixtures still exist.
        for fixture in project.fixtures {
            guard let universe = project.universe(id: fixture.universeId) else { continue }
            if result[universe.number] == nil {
                result[universe.number] = Array(repeating: 0, count: channelCount)
            }
        }

        for fixture in project.fixtures {
            guard let universe = project.universe(id: fixture.universeId) else { continue }
            guard let definition = project.definition(id: fixture.definitionId) else { continue }
            guard var buffer = result[universe.number] else { continue }

            let attrs = look.fixtureAttributes[fixture.id] ?? [:]
            let baseAddress = Int(fixture.address) // 1-based

            for channel in definition.channels {
                let index = baseAddress + Int(channel.offset) - 2 // address + offset - 1 - 1
                // channel.offset is 1-based within fixture; DMX index = address + offset - 2? 
                // address 1, offset 1 → index 0: index = address - 1 + offset - 1 = address + offset - 2. Yes.
                guard index >= 0, index < buffer.count else { continue }

                if let normalized = attrs[channel.attribute] {
                    buffer[index] = dmxValue(normalized: normalized)
                } else {
                    buffer[index] = channel.defaultValue
                }
            }

            result[universe.number] = buffer
        }

        return result
    }
}
