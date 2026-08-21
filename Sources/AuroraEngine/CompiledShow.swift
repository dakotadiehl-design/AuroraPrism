import AuroraModel
import Foundation

/// One compiled attribute write for a patched fixture (8-bit or 16-bit coarse/fine).
public struct CompiledAttributeWrite: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case eightBit(offset: UInt16, defaultValue: UInt8)
        case sixteenBit(
            coarseOffset: UInt16,
            fineOffset: UInt16,
            coarseDefault: UInt8,
            fineDefault: UInt8
        )
    }

    public let attribute: String
    public let kind: Kind
    /// When true, normalized value is inverted (`1 - v`) before DMX encode (pan/tilt invert).
    public let invert: Bool
    /// Ranges reserved for reset/lamp/service commands. Normal Programmer and playback
    /// writes are moved to the nearest safe value before reaching DMX output.
    public let protectedRanges: [ClosedRange<UInt8>]
    /// Optional local DMX range used by one semantic function of a compound channel.
    public let activeRange: ClosedRange<UInt8>?
    /// Range-specific views must not write a default when their attribute is untouched,
    /// because another semantic view may own the same physical channel.
    public let writesDefaultWhenUnowned: Bool

    public init(
        attribute: String,
        kind: Kind,
        invert: Bool = false,
        protectedRanges: [ClosedRange<UInt8>] = [],
        activeRange: ClosedRange<UInt8>? = nil,
        writesDefaultWhenUnowned: Bool = true
    ) {
        self.attribute = attribute
        self.kind = kind
        self.invert = invert
        self.protectedRanges = protectedRanges
        self.activeRange = activeRange
        self.writesDefaultWhenUnowned = writesDefaultWhenUnowned
    }

    public func safeEightBitValue(_ proposed: UInt8) -> UInt8 {
        guard let blocked = protectedRanges.first(where: { $0.contains(proposed) }) else { return proposed }
        let below = blocked.lowerBound > 0 ? blocked.lowerBound - 1 : nil
        let above = blocked.upperBound < 255 ? blocked.upperBound + 1 : nil
        switch (below, above) {
        case let (lower?, upper?):
            return proposed - lower <= upper - proposed ? lower : upper
        case let (lower?, nil): return lower
        case let (nil, upper?): return upper
        case (nil, nil): return 0
        }
    }

    public func eightBitValue(normalized: Double) -> UInt8 {
        let clamped = min(1, max(0, normalized))
        let proposed: UInt8
        if let activeRange {
            let width = Double(Int(activeRange.upperBound) - Int(activeRange.lowerBound))
            proposed = UInt8((Double(activeRange.lowerBound) + clamped * width).rounded())
        } else {
            proposed = UInt8((clamped * 255).rounded())
        }
        return safeEightBitValue(proposed)
    }
}

/// Patch + channel plan for one fixture in the compiled show.
public struct CompiledFixture: Sendable, Equatable {
    public let id: UUID
    public let universeNumber: UInt16
    /// 1-based DMX start address.
    public let baseAddress: UInt16
    public let definitionId: UUID
    public let attributeWrites: [CompiledAttributeWrite]
    /// Attribute → home/default normalized value (from personality defaults when available).
    public let homeValues: [String: Double]
    /// Attribute → highlight normalized value from personality.
    public let highlightValues: [String: Double]

    public init(
        id: UUID,
        universeNumber: UInt16,
        baseAddress: UInt16,
        definitionId: UUID,
        attributeWrites: [CompiledAttributeWrite],
        homeValues: [String: Double] = [:],
        highlightValues: [String: Double] = [:]
    ) {
        self.id = id
        self.universeNumber = universeNumber
        self.baseAddress = baseAddress
        self.definitionId = definitionId
        self.attributeWrites = attributeWrites
        self.homeValues = homeValues
        self.highlightValues = highlightValues
    }
}

/// Immutable runtime representation of a show for the engine frame path.
///
/// Built from editable `ShowProject` on load/update so the 40 Hz path uses indexes
/// and channel write plans instead of linear model lookups (P1-12).
public struct CompiledShow: Sendable, Equatable {
    public let universeByID: [UUID: Universe]
    public let universeByNumber: [UInt16: Universe]
    public let fixtureByID: [UUID: PatchedFixture]
    public let definitionByID: [UUID: FixtureDefinition]
    public let groupByID: [UUID: Group]
    /// Fixtures with valid universe + definition only.
    public let fixtures: [CompiledFixture]
    /// Universe number → channel count used for buffer allocation.
    public let channelCountByUniverse: [UInt16: Int]

    public static let empty = CompiledShow(
        universeByID: [:],
        universeByNumber: [:],
        fixtureByID: [:],
        definitionByID: [:],
        groupByID: [:],
        fixtures: [],
        channelCountByUniverse: [:]
    )

    public init(
        universeByID: [UUID: Universe],
        universeByNumber: [UInt16: Universe],
        fixtureByID: [UUID: PatchedFixture],
        definitionByID: [UUID: FixtureDefinition],
        groupByID: [UUID: Group],
        fixtures: [CompiledFixture],
        channelCountByUniverse: [UInt16: Int]
    ) {
        self.universeByID = universeByID
        self.universeByNumber = universeByNumber
        self.fixtureByID = fixtureByID
        self.definitionByID = definitionByID
        self.groupByID = groupByID
        self.fixtures = fixtures
        self.channelCountByUniverse = channelCountByUniverse
    }

    /// Compile an editable project into runtime indexes and channel write plans.
    public static func compile(_ project: ShowProject) -> CompiledShow {
        var universeByID: [UUID: Universe] = [:]
        var universeByNumber: [UInt16: Universe] = [:]
        var channelCountByUniverse: [UInt16: Int] = [:]
        universeByID.reserveCapacity(project.universes.count)
        for universe in project.universes {
            universeByID[universe.id] = universe
            universeByNumber[universe.number] = universe
            channelCountByUniverse[universe.number] = Int(universe.channelCount)
        }

        var definitionByID: [UUID: FixtureDefinition] = [:]
        definitionByID.reserveCapacity(project.fixtureDefinitions.count)
        for definition in project.fixtureDefinitions {
            definitionByID[definition.id] = definition
        }

        var fixtureByID: [UUID: PatchedFixture] = [:]
        fixtureByID.reserveCapacity(project.fixtures.count)
        for fixture in project.fixtures {
            fixtureByID[fixture.id] = fixture
        }

        var groupByID: [UUID: Group] = [:]
        groupByID.reserveCapacity(project.groups.count)
        for group in project.groups {
            groupByID[group.id] = group
        }

        var compiledFixtures: [CompiledFixture] = []
        compiledFixtures.reserveCapacity(project.fixtures.count)

        for fixture in project.fixtures {
            // Unpatched fixtures remain in the show but do not occupy DMX output.
            guard fixture.isPatched else { continue }
            guard let universe = universeByID[fixture.universeId] else { continue }
            guard let definition = definitionByID[fixture.definitionId] else { continue }

            if channelCountByUniverse[universe.number] == nil {
                channelCountByUniverse[universe.number] = Int(universe.channelCount)
            }

            let writes = compileAttributeWrites(definition: definition)
            let (homes, highlights) = compileHomeAndHighlight(definition: definition, writes: writes)

            compiledFixtures.append(
                CompiledFixture(
                    id: fixture.id,
                    universeNumber: universe.number,
                    baseAddress: fixture.address,
                    definitionId: definition.id,
                    attributeWrites: writes,
                    homeValues: homes,
                    highlightValues: highlights
                )
            )
        }

        return CompiledShow(
            universeByID: universeByID,
            universeByNumber: universeByNumber,
            fixtureByID: fixtureByID,
            definitionByID: definitionByID,
            groupByID: groupByID,
            fixtures: compiledFixtures,
            channelCountByUniverse: channelCountByUniverse
        )
    }

    /// Build channel write plans from a fixture definition (pairs coarse/fine by attribute).
    /// Expands multi-cell blocks into per-cell attributes `attr@cellN` (A1 / Pass-1 multi-cell).
    public static func compileAttributeWrites(definition: FixtureDefinition) -> [CompiledAttributeWrite] {
        var expanded: [ChannelDef] = definition.channels.map { channel in
            guard let elementID = channel.elementID, !channel.attribute.isEmpty else { return channel }
            var copy = channel
            copy.attribute = "\(channel.attribute)@\(elementID)"
            return copy
        }

        // Expand repeated cell blocks into absolute offsets + per-cell attribute keys.
        if let block = definition.cellBlock, block.cellCount > 0, !block.channels.isEmpty {
            let headerMax = definition.channels.map(\.offset).max() ?? 0
            let base = headerMax // cells start after header channels
            let perCell = block.channelsPerCell
            for cellIndex in 0..<Int(block.cellCount) {
                let cellBase = base + UInt16(cellIndex) * perCell
                for ch in block.channels {
                    var copy = ch
                    // Absolute 1-based offset within fixture footprint.
                    copy.offset = cellBase + ch.offset
                    // Per-cell semantic key: colorR@0, intensity@3, …
                    if !ch.attribute.isEmpty {
                        copy.attribute = "\(ch.attribute)@\(cellIndex)"
                    }
                    expanded.append(copy)
                }
            }
        }

        var byAttribute: [String: [ChannelDef]] = [:]
        for channel in expanded where channel.dmxFunctions.isEmpty
            || !channel.dmxFunctions.allSatisfy(\.isProtected) {
            byAttribute[channel.attribute, default: []].append(channel)
        }

        var writes: [CompiledAttributeWrite] = []
        writes.reserveCapacity(byAttribute.count)

        // Stable order by lowest channel offset in the group.
        let sortedKeys = byAttribute.keys.sorted { a, b in
            let ao = byAttribute[a]?.map(\.offset).min() ?? 0
            let bo = byAttribute[b]?.map(\.offset).min() ?? 0
            if ao != bo { return ao < bo }
            return a < b
        }

        for attribute in sortedKeys {
            guard let group = byAttribute[attribute] else { continue }
            let baseAttr = attribute.split(separator: "@").first.map(String.init) ?? attribute
            let invert = invertFlag(for: baseAttr, definition: definition)
            let coarse = group.first(where: { $0.resolution == .coarse })
            let fine = group.first(where: { $0.resolution == .fine })

            if let coarse, let fine {
                writes.append(
                    CompiledAttributeWrite(
                        attribute: attribute,
                        kind: .sixteenBit(
                            coarseOffset: coarse.offset,
                            fineOffset: fine.offset,
                            coarseDefault: coarse.defaultValue,
                            fineDefault: fine.defaultValue
                        ),
                        invert: invert,
                        protectedRanges: protectedRanges(in: coarse)
                    )
                )
                for channel in group where channel.id != coarse.id && channel.id != fine.id {
                    writes.append(
                        CompiledAttributeWrite(
                            attribute: attribute,
                            kind: .eightBit(offset: channel.offset, defaultValue: channel.defaultValue),
                            invert: invert,
                            protectedRanges: protectedRanges(in: channel)
                        )
                    )
                }
            } else {
                for channel in group {
                    writes.append(
                        CompiledAttributeWrite(
                            attribute: attribute,
                            kind: .eightBit(offset: channel.offset, defaultValue: channel.defaultValue),
                            invert: invert,
                            protectedRanges: protectedRanges(in: channel)
                        )
                    )
                }
            }
        }

        writes.append(contentsOf: compileRangeSpecificWrites(channels: expanded))
        return writes
    }

    private static func protectedRanges(in channel: ChannelDef) -> [ClosedRange<UInt8>] {
        channel.dmxFunctions.filter(\.isProtected).map { $0.dmxMin...$0.dmxMax }
    }

    private static func compileRangeSpecificWrites(channels: [ChannelDef]) -> [CompiledAttributeWrite] {
        var writes: [CompiledAttributeWrite] = []
        for channel in channels {
            let protected = protectedRanges(in: channel)
            let functions = channel.dmxFunctions.filter {
                !$0.isProtected && $0.semantic == .attribute && $0.attribute != nil
            }
            let grouped = Dictionary(grouping: functions, by: { $0.attribute! })
            guard grouped.count > 1 || grouped.keys.contains(where: { $0 != channel.attribute }) else { continue }
            for attribute in grouped.keys.sorted() {
                guard let ranges = grouped[attribute],
                      let lower = ranges.map(\.dmxMin).min(),
                      let upper = ranges.map(\.dmxMax).max()
                else { continue }
                writes.append(CompiledAttributeWrite(
                    attribute: attribute,
                    kind: .eightBit(offset: channel.offset, defaultValue: channel.defaultValue),
                    protectedRanges: protected,
                    activeRange: lower...upper,
                    writesDefaultWhenUnowned: false
                ))
            }
        }
        return writes
    }

    private static func invertFlag(for attribute: String, definition: FixtureDefinition) -> Bool {
        switch attribute {
        case "pan": return definition.panInvert
        case "tilt": return definition.tiltInvert
        default: return false
        }
    }

    private static func compileHomeAndHighlight(
        definition: FixtureDefinition,
        writes: [CompiledAttributeWrite]
    ) -> (home: [String: Double], highlight: [String: Double]) {
        var home: [String: Double] = [:]
        var highlight: [String: Double] = [:]

        // Index channels by attribute for 16-bit coarse+fine pairing (UI-FOUNDATION-5).
        var byAttribute: [String: [ChannelDef]] = [:]
        for channel in definition.channels {
            byAttribute[channel.attribute, default: []].append(channel)
        }

        for (attribute, channels) in byAttribute {
            let coarse = channels.first(where: { $0.resolution == .coarse })
            let fine = channels.first(where: { $0.resolution == .fine })
            let eight = channels.first(where: { $0.resolution == .eightBit })

            if let coarse, let fine {
                let home16 = (UInt16(coarse.defaultValue) << 8) | UInt16(fine.defaultValue)
                let high16 = (UInt16(coarse.highlightValue) << 8) | UInt16(fine.highlightValue)
                home[attribute] = Double(home16) / 65535.0
                highlight[attribute] = Double(high16) / 65535.0
            } else if let coarse {
                home[attribute] = Double(coarse.defaultValue) / 255.0
                highlight[attribute] = Double(coarse.highlightValue) / 255.0
            } else if let eight {
                home[attribute] = Double(eight.defaultValue) / 255.0
                highlight[attribute] = Double(eight.highlightValue) / 255.0
            } else if let fine {
                // Fine-only (unusual): treat as low byte of 16-bit scale.
                home[attribute] = Double(fine.defaultValue) / 65535.0
                highlight[attribute] = Double(fine.highlightValue) / 65535.0
            }
        }

        // Ensure every write has at least a home entry of 0 if missing.
        for write in writes {
            if home[write.attribute] == nil { home[write.attribute] = 0 }
            if highlight[write.attribute] == nil { highlight[write.attribute] = 1 }
        }

        return (home, highlight)
    }
}
