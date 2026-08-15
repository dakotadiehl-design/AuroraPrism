import AuroraModel
import Foundation

/// Semantic ownership of a DMX channel for Output Monitor (P0-L).
public struct DMXChannelAttribution: Equatable, Sendable {
    public var channel: Int
    public var value: UInt8
    public var fixtureName: String?
    public var parameter: String?
    public var fixtureID: UUID?

    public var isUnused: Bool { fixtureName == nil }

    public init(
        channel: Int,
        value: UInt8,
        fixtureName: String? = nil,
        parameter: String? = nil,
        fixtureID: UUID? = nil
    ) {
        self.channel = channel
        self.value = value
        self.fixtureName = fixtureName
        self.parameter = parameter
        self.fixtureID = fixtureID
    }

    public var summary: String {
        if let name = fixtureName, let param = parameter {
            return String(format: "%03d %3d  %@  %@", channel, value, name, param)
        }
        if let name = fixtureName {
            return String(format: "%03d %3d  %@", channel, value, name)
        }
        return String(format: "%03d %3d  —", channel, value)
    }
}

public enum DMXChannelAttributionBuilder {
    /// Build attribution for one universe (1-based channel indices).
    public static func attributes(
        project: ShowProject,
        universeNumber: UInt16,
        levels: [UInt8]
    ) -> [DMXChannelAttribution] {
        guard let universe = project.universes.first(where: { $0.number == universeNumber }) else {
            return levels.enumerated().map { DMXChannelAttribution(channel: $0.offset + 1, value: $0.element) }
        }
        let compiled = CompiledShow.compile(project)
        var map: [Int: (String, String, UUID)] = [:]
        for cf in compiled.fixtures where cf.universeNumber == universeNumber {
            let fxName = project.fixtures.first(where: { $0.id == cf.id })?.name ?? "Fixture"
            for write in cf.attributeWrites {
                switch write.kind {
                case .eightBit(let off, _):
                    let abs = Int(cf.baseAddress) + Int(off) - 1
                    if abs >= 1, abs <= 512 {
                        map[abs] = (fxName, write.attribute, cf.id)
                    }
                case .sixteenBit(let coarse, let fine, _, _):
                    let cAbs = Int(cf.baseAddress) + Int(coarse) - 1
                    let fAbs = Int(cf.baseAddress) + Int(fine) - 1
                    if cAbs >= 1, cAbs <= 512 {
                        map[cAbs] = (fxName, write.attribute, cf.id)
                    }
                    if fAbs >= 1, fAbs <= 512 {
                        map[fAbs] = (fxName, "\(write.attribute) fine", cf.id)
                    }
                }
            }
        }
        let count = max(levels.count, Int(universe.channelCount))
        var result: [DMXChannelAttribution] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let ch = i + 1
            let v = i < levels.count ? levels[i] : 0
            if let hit = map[ch] {
                result.append(DMXChannelAttribution(
                    channel: ch,
                    value: v,
                    fixtureName: hit.0,
                    parameter: hit.1,
                    fixtureID: hit.2
                ))
            } else {
                result.append(DMXChannelAttribution(channel: ch, value: v))
            }
        }
        return result
    }
}
