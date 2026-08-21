import AuroraDesignSystem
import AuroraEngine
import AuroraModel
import SwiftUI

/// Dedicated live monitor for a complete universe or one fixture personality.
public struct DMXOutputMonitorPanel: View {
    public var snapshot: EngineFrameSnapshot
    public var project: ShowProject

    @State private var fixtureID: UUID?
    @State private var universeNumber: UInt16?
    @State private var search = ""

    public init(snapshot: EngineFrameSnapshot, project: ShowProject, initialFixtureID: UUID? = nil) {
        self.snapshot = snapshot
        self.project = project
        _fixtureID = State(initialValue: initialFixtureID)
    }

    private var sortedUniverses: [Universe] { project.universes.sorted { $0.number < $1.number } }
    private var sortedFixtures: [PatchedFixture] {
        project.fixtures.filter(\.isPatched).sorted { lhs, rhs in
            let lu = project.universes.first(where: { $0.id == lhs.universeId })?.number ?? 0
            let ru = project.universes.first(where: { $0.id == rhs.universeId })?.number ?? 0
            return (lu, lhs.address, lhs.name) < (ru, rhs.address, rhs.name)
        }
    }
    private var selectedFixture: PatchedFixture? {
        fixtureID.flatMap { id in project.fixtures.first(where: { $0.id == id }) }
    }
    private var selectedUniverse: UInt16 {
        if let fixture = selectedFixture,
           let universe = project.universes.first(where: { $0.id == fixture.universeId }) { return universe.number }
        return universeNumber ?? sortedUniverses.first?.number ?? 1
    }
    private var levels: [UInt8] { snapshot.universeLevels[selectedUniverse] ?? [] }
    private var rows: [DMXMonitorRow] {
        let all = DMXMonitorRowBuilder.rows(
            project: project,
            universeNumber: selectedUniverse,
            fixtureID: fixtureID,
            levels: levels
        )
        guard !search.isEmpty else { return all }
        return all.filter { $0.searchText.localizedCaseInsensitiveContains(search) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            header
            Divider()
            if rows.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No DMX Channels" : "No Results",
                    systemImage: "waveform.path.ecg",
                    description: Text(search.isEmpty ? "Patch a fixture or choose a universe to inspect output." : "Try a different search.")
                )
            } else {
                channelList
            }
        }
        .background(AuroraColor.surfaceBase)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $fixtureID) {
                Text("Entire Universe").tag(UUID?.none)
                if !sortedFixtures.isEmpty { Divider() }
                ForEach(sortedFixtures) { fixture in
                    Text(fixture.name).tag(Optional(fixture.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 280)

            if fixtureID == nil {
                Picker("Universe", selection: Binding(
                    get: { selectedUniverse },
                    set: { universeNumber = $0 }
                )) {
                    ForEach(sortedUniverses) { universe in
                        Text("Universe \(universe.number) — \(universe.name)").tag(universe.number)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            Spacer()
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
        }
        .padding(10)
    }

    private var header: some View {
        HStack {
            if let fixture = selectedFixture {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fixture.name).font(.headline)
                    if let definition = project.definition(id: fixture.definitionId) {
                        Text("\(definition.manufacturer) \(definition.model) · \(definition.modeName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("U\(selectedUniverse) · \(fixture.address)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            } else {
                Text("Universe \(selectedUniverse)").font(.headline)
                Spacer()
                Text("\(rows.filter { $0.value > 0 }.count) active · Frame \(snapshot.frameIndex)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                HStack {
                    Text("CHANNEL").frame(width: 82, alignment: .leading)
                    Text("PROPERTY")
                    Spacer()
                    Text("OUTPUT").frame(width: 64, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)

                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.channelLabel)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .frame(width: 82, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.property)
                            if let fixtureName = row.fixtureName, fixtureID == nil {
                                Text(fixtureName).font(.caption2).foregroundStyle(.secondary)
                            }
                            if let function = row.functionName {
                                Text(function).font(.caption2).foregroundStyle(AuroraColor.accentBright)
                            }
                        }
                        Spacer()
                        Text("\(row.value)")
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(row.channel.isMultiple(of: 2) ? Color.white.opacity(0.035) : Color.clear)
                }
            }
        }
    }
}

public struct DMXMonitorRow: Identifiable, Equatable, Sendable {
    public var id: Int { channel }
    public var channel: Int
    public var relativeChannel: Int?
    public var value: UInt8
    public var property: String
    public var fixtureName: String?
    public var functionName: String?

    public var channelLabel: String {
        relativeChannel.map { "\($0)  (\(channel))" } ?? "\(channel)"
    }
    fileprivate var searchText: String { "\(channel) \(property) \(fixtureName ?? "") \(functionName ?? "")" }
}

public enum DMXMonitorRowBuilder {
    public static func rows(
        project: ShowProject,
        universeNumber: UInt16,
        fixtureID: UUID?,
        levels: [UInt8]
    ) -> [DMXMonitorRow] {
        if let fixtureID, let fixture = project.fixtures.first(where: { $0.id == fixtureID }) {
            return fixtureRows(project: project, fixture: fixture, levels: levels)
        }
        let universe = project.universes.first(where: { $0.number == universeNumber })
        let count = Int(universe?.channelCount ?? 512)
        let attrs = DMXChannelAttributionBuilder.attributes(project: project, universeNumber: universeNumber, levels: levels)
        return (0..<count).map { index in
            let attr = index < attrs.count ? attrs[index] : DMXChannelAttribution(channel: index + 1, value: 0)
            return DMXMonitorRow(channel: index + 1, relativeChannel: nil, value: attr.value,
                                 property: attr.parameter ?? "Unused", fixtureName: attr.fixtureName, functionName: nil)
        }
    }

    private static func fixtureRows(project: ShowProject, fixture: PatchedFixture, levels: [UInt8]) -> [DMXMonitorRow] {
        guard let definition = project.definition(id: fixture.definitionId) else { return [] }
        var channels: [(Int, ChannelDef, String?)] = definition.channels.map { (Int($0.offset), $0, nil) }
        if let block = definition.cellBlock {
            let base = Int(definition.channels.map(\.offset).max() ?? 0)
            for cell in 0..<Int(block.cellCount) {
                for channel in block.channels {
                    channels.append((base + cell * Int(block.channelsPerCell) + Int(channel.offset), channel, "\(block.cellLabelPrefix) \(cell + 1)"))
                }
            }
        }
        let byOffset = Dictionary(channels.map { ($0.0, ($0.1, $0.2)) }, uniquingKeysWith: { first, _ in first })
        return (1...Int(definition.channelCount)).map { offset in
            let absolute = Int(fixture.address) + offset - 1
            let value = levels.indices.contains(absolute - 1) ? levels[absolute - 1] : 0
            let item = byOffset[offset]
            let channel = item?.0
            let baseName = channel?.name.isEmpty == false ? channel!.name : (channel?.attribute ?? "Channel \(offset)")
            let property = item?.1.map { "\(baseName) (\($0))" } ?? baseName
            let function = channel?.dmxFunctions.first(where: { value >= $0.dmxMin && value <= $0.dmxMax })?.name
            return DMXMonitorRow(channel: absolute, relativeChannel: offset, value: value,
                                 property: property, fixtureName: fixture.name, functionName: function)
        }
    }
}
