import AuroraEngine
import AuroraModel
import SwiftUI

/// Live DMX channel view with semantic attribution (P0-L).
public struct UniverseMonitorPanel: View {
    public var snapshot: EngineFrameSnapshot
    public var project: ShowProject
    public var universes: [Universe]
    public var defaultUniverseNumber: UInt16

    @State private var selectedUniverseNumber: UInt16?
    @State private var showAttribution = true
    @State private var onlyActive = false

    public init(
        snapshot: EngineFrameSnapshot,
        project: ShowProject = .empty(),
        universes: [Universe] = [],
        defaultUniverseNumber: UInt16 = 1
    ) {
        self.snapshot = snapshot
        self.project = project
        self.universes = universes
        self.defaultUniverseNumber = defaultUniverseNumber
    }

    /// Compatibility initializer used by older call sites.
    public init(
        snapshot: EngineFrameSnapshot,
        universes: [Universe] = [],
        defaultUniverseNumber: UInt16 = 1
    ) {
        self.snapshot = snapshot
        self.project = .empty()
        self.universes = universes
        self.defaultUniverseNumber = defaultUniverseNumber
    }

    private var universeNumber: UInt16 {
        if let selectedUniverseNumber { return selectedUniverseNumber }
        if let first = universes.first?.number { return first }
        return defaultUniverseNumber
    }

    private var channelCount: Int {
        if let u = universes.first(where: { $0.number == universeNumber }) {
            return Int(u.channelCount)
        }
        return 512
    }

    private var levels: [UInt8] {
        let raw = snapshot.universeLevels[universeNumber] ?? []
        if raw.count >= channelCount { return Array(raw.prefix(channelCount)) }
        return raw + Array(repeating: 0, count: channelCount - raw.count)
    }

    private var attributions: [DMXChannelAttribution] {
        DMXChannelAttributionBuilder.attributes(
            project: project,
            universeNumber: universeNumber,
            levels: levels
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Universe Monitor")
                    .font(.headline)
                Spacer()
                Toggle("Attrib", isOn: $showAttribution)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Toggle("Active", isOn: $onlyActive)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                if universes.isEmpty {
                    Text("U\(universeNumber)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Universe", selection: Binding(
                        get: { universeNumber },
                        set: { selectedUniverseNumber = $0 }
                    )) {
                        ForEach(universes) { u in
                            Text("\(u.number) — \(u.name.isEmpty ? "Universe" : u.name)")
                                .tag(u.number)
                        }
                    }
                    .frame(maxWidth: 220)
                }
            }

            Text(
                "Frame \(snapshot.frameIndex) · \(levels.filter { $0 > 0 }.count)/\(channelCount) ch active · \(String(format: "%.0f", snapshot.frameRateHz)) Hz"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if showAttribution {
                attributionList
            } else {
                gridView
            }
        }
        .padding(8)
    }

    private var attributionList: some View {
        let rows = onlyActive ? attributions.filter { $0.value > 0 || !$0.isUnused } : attributions
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                Text("Ch   Val  Fixture                 Parameter")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(String(
                        format: "%03d  %3d  %-22@  %@",
                        row.channel,
                        row.value,
                        (row.fixtureName ?? "—") as NSString,
                        (row.parameter ?? (row.isUnused ? "unused" : "")) as NSString
                    ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(row.value > 0 ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gridView: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 16),
                spacing: 4
            ) {
                ForEach(0..<channelCount, id: \.self) { i in
                    let v = levels[i]
                    let attr = i < attributions.count ? attributions[i] : nil
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(Double(v) / 255.0))
                            .frame(height: 28)
                            .overlay(
                                Text(v > 0 ? "\(v)" : "")
                                    .font(.system(size: 7).monospaced())
                                    .foregroundStyle(.white.opacity(0.9))
                            )
                        Text("\(i + 1)")
                            .font(.system(size: 8).monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .help(attr?.summary ?? "Ch \(i + 1): \(v)")
                }
            }
        }
    }
}
