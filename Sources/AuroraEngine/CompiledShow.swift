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

    public init(attribute: String, kind: Kind, invert: Bool = false) {
        self.attribute = attribute
        self.kind = kind
        self.invert = invert
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
        var expanded: [ChannelDef] = definition.channels

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
        for channel in expanded {
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
                        invert: invert
                    )
                )
                for channel in group where channel.id != coarse.id && channel.id != fine.id {
                    writes.append(
                        CompiledAttributeWrite(
                            attribute: attribute,
                            kind: .eightBit(offset: channel.offset, defaultValue: channel.defaultValue),
                            invert: invert
                        )
                    )
                }
            } else {
                for channel in group {
                    writes.append(
                        CompiledAttributeWrite(
                            attribute: attribute,
                            kind: .eightBit(offset: channel.offset, defaultValue: channel.defaultValue),
                            invert: invert
                        )
                    )
                }
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
