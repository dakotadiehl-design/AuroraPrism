import AuroraModel
import Foundation

/// Builds per-universe DMX from patch + a single `ActiveLook` (home/default + look).
public enum MergeStub {
    /// Scales normalized 0…1 to 8-bit DMX.
    public static func dmxValue(normalized: Double) -> UInt8 {
        let clamped = min(1, max(0, normalized))
        return UInt8(clamped * 255.0 + 0.5)
    }

    /// Scales normalized 0…1 to 16-bit DMX (0…65535).
    public static func dmx16Value(normalized: Double) -> UInt16 {
        let clamped = min(1, max(0, normalized))
        return UInt16(clamped * 65535.0 + 0.5)
    }

    /// High / low bytes of a 16-bit DMX value (coarse = MSB, fine = LSB).
    public static func split16(_ value: UInt16) -> (coarse: UInt8, fine: UInt8) {
        (UInt8(value >> 8), UInt8(value & 0xFF))
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

            writeFixtureChannels(
                channels: definition.channels,
                attributes: attrs,
                baseAddress: baseAddress,
                into: &buffer
            )

            result[universe.number] = buffer
        }

        return result
    }

    /// Compiles channel defs + normalized attributes into a DMX buffer.
    public static func writeFixtureChannels(
        channels: [ChannelDef],
        attributes: [String: Double],
        baseAddress: Int,
        into buffer: inout [UInt8]
    ) {
        // Group by attribute so coarse/fine pairs share one 16-bit encoding.
        var byAttribute: [String: [ChannelDef]] = [:]
        for channel in channels {
            byAttribute[channel.attribute, default: []].append(channel)
        }

        var writtenOffsets = Set<Int>()

        for (attribute, group) in byAttribute {
            let coarse = group.first(where: { $0.resolution == .coarse })
            let fine = group.first(where: { $0.resolution == .fine })

            if let coarse, let fine, let normalized = attributes[attribute] {
                let raw16 = dmx16Value(normalized: normalized)
                let (c, f) = split16(raw16)
                writeByte(c, channel: coarse, baseAddress: baseAddress, into: &buffer, written: &writtenOffsets)
                writeByte(f, channel: fine, baseAddress: baseAddress, into: &buffer, written: &writtenOffsets)
                // Any extra channels for the same attribute fall through below.
            }

            for channel in group {
                let index = dmxIndex(baseAddress: baseAddress, offset: channel.offset)
                guard !writtenOffsets.contains(index) else { continue }

                if let normalized = attributes[attribute] {
                    // Unpaired coarse/fine or eight-bit: independent 8-bit encode.
                    writeByte(
                        dmxValue(normalized: normalized),
                        channel: channel,
                        baseAddress: baseAddress,
                        into: &buffer,
                        written: &writtenOffsets
                    )
                } else {
                    writeByte(
                        channel.defaultValue,
                        channel: channel,
                        baseAddress: baseAddress,
                        into: &buffer,
                        written: &writtenOffsets
                    )
                }
            }
        }
    }

    private static func dmxIndex(baseAddress: Int, offset: UInt16) -> Int {
        // address 1, offset 1 → index 0
        baseAddress + Int(offset) - 2
    }

    private static func writeByte(
        _ value: UInt8,
        channel: ChannelDef,
        baseAddress: Int,
        into buffer: inout [UInt8],
        written: inout Set<Int>
    ) {
        let index = dmxIndex(baseAddress: baseAddress, offset: channel.offset)
        guard index >= 0, index < buffer.count else { return }
        buffer[index] = value
        written.insert(index)
    }
}
