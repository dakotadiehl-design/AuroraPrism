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

    /// Merge using a precompiled show (engine hot path).
    public static func merge(
        compiled: CompiledShow,
        look: ActiveLook,
        channelCount: Int = 512
    ) -> [UInt16: [UInt8]] {
        var result: [UInt16: [UInt8]] = [:]

        for (number, count) in compiled.channelCountByUniverse {
            result[number] = Array(repeating: 0, count: max(count, channelCount))
        }

        for fixture in compiled.fixtures {
            if result[fixture.universeNumber] == nil {
                result[fixture.universeNumber] = Array(repeating: 0, count: channelCount)
            }
            guard var buffer = result[fixture.universeNumber] else { continue }
            let attrs = look.fixtureAttributes[fixture.id] ?? [:]
            writeCompiledFixture(fixture, attributes: attrs, into: &buffer)
            result[fixture.universeNumber] = buffer
        }

        return result
    }

    /// Convenience: compile then merge (tests / one-shot callers).
    public static func merge(
        project: ShowProject,
        look: ActiveLook,
        channelCount: Int = 512
    ) -> [UInt16: [UInt8]] {
        merge(compiled: .compile(project), look: look, channelCount: channelCount)
    }

    /// Apply compiled attribute writes for one fixture into a universe buffer.
    /// Applies virtual dimmer scaling when `intensity` is authored but no physical dimmer channel exists (C.E. 1.1).
    public static func writeCompiledFixture(
        _ fixture: CompiledFixture,
        attributes: [String: Double],
        into buffer: inout [UInt8]
    ) {
        let resolved = resolveOutputAttributes(attributes, for: fixture)
        let base = Int(fixture.baseAddress)
        for write in fixture.attributeWrites {
            let raw = resolved[write.attribute]
            let normalized: Double?
            if let raw {
                normalized = write.invert ? (1.0 - raw) : raw
            } else {
                normalized = nil
            }

            switch write.kind {
            case .eightBit(let offset, let defaultValue):
                let value: UInt8
                if let normalized {
                    value = dmxValue(normalized: normalized)
                } else {
                    value = defaultValue
                }
                writeByte(value, baseAddress: base, offset: offset, into: &buffer)

            case .sixteenBit(let coarseOffset, let fineOffset, let coarseDefault, let fineDefault):
                if let normalized {
                    let (c, f) = split16(dmx16Value(normalized: normalized))
                    writeByte(c, baseAddress: base, offset: coarseOffset, into: &buffer)
                    writeByte(f, baseAddress: base, offset: fineOffset, into: &buffer)
                } else {
                    writeByte(coarseDefault, baseAddress: base, offset: coarseOffset, into: &buffer)
                    writeByte(fineDefault, baseAddress: base, offset: fineOffset, into: &buffer)
                }
            }
        }
    }

    /// Output-resolution attribute map: virtual dimmer scales physical emitters without rewriting Programmer stores.
    public static func resolveOutputAttributes(
        _ attributes: [String: Double],
        for fixture: CompiledFixture
    ) -> [String: Double] {
        let physical = Set(fixture.attributeWrites.map(\.attribute))
        let hasPhysicalDimmer = physical.contains { GlobalShowControl.isDimmerAttribute($0) }
        guard !hasPhysicalDimmer else { return attributes }

        // Virtual dimmer: scale all light-producing emitters by authored intensity (default 1 if unset).
        let scale = attributes["intensity"]
            ?? attributes["dimmer"]
            ?? attributes["dim"]
            ?? 1.0
        guard scale < 0.999999 else {
            // Still strip soft authoring keys from consideration (they are never written).
            return attributes
        }
        var next = attributes
        for key in attributes.keys {
            if ColorAuthoringAttribute.isAuthoring(key) { continue }
            if ColorEmitterKind.isPhysicalEmitter(key) {
                next[key] = (attributes[key] ?? 0) * scale
            }
        }
        return next
    }

    /// Legacy path: compile channel defs on the fly (kept for unit tests of write planning).
    public static func writeFixtureChannels(
        channels: [ChannelDef],
        attributes: [String: Double],
        baseAddress: Int,
        into buffer: inout [UInt8],
        panInvert: Bool = false,
        tiltInvert: Bool = false
    ) {
        let definition = FixtureDefinition(
            manufacturer: "",
            model: "",
            channels: channels,
            panInvert: panInvert,
            tiltInvert: tiltInvert
        )
        let writes = CompiledShow.compileAttributeWrites(definition: definition)
        let fixture = CompiledFixture(
            id: UUID(),
            universeNumber: 1,
            baseAddress: UInt16(baseAddress),
            definitionId: UUID(),
            attributeWrites: writes
        )
        // baseAddress in writeFixtureChannels is already 1-based fixture address;
        // CompiledFixture.baseAddress is the same. But writeCompiledFixture uses
        // fixture.baseAddress — callers pass address as baseAddress (1-based).
        // Old API used baseAddress as fixture address; writeByte used baseAddress + offset - 2.
        // CompiledFixture uses baseAddress as fixture address. Good.
        // Wait: old writeFixtureChannels took baseAddress as Int fixture address.
        // New CompiledFixture.baseAddress is UInt16 fixture address.
        // But if someone passes baseAddress that was already computed... old tests use fixture.address.
        writeCompiledFixture(fixture, attributes: attributes, into: &buffer)
    }

    private static func writeByte(
        _ value: UInt8,
        baseAddress: Int,
        offset: UInt16,
        into buffer: inout [UInt8]
    ) {
        // address 1, offset 1 → index 0
        let index = baseAddress + Int(offset) - 2
        guard index >= 0, index < buffer.count else { return }
        buffer[index] = value
    }
}
