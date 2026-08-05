import AuroraEngine
import AuroraModel
import SwiftUI

/// Live DMX channel view from engine snapshots (full universe, pickable).
public struct UniverseMonitorPanel: View {
    public var snapshot: EngineFrameSnapshot
    /// Show universes available for picking (from project).
    public var universes: [Universe]
    public var defaultUniverseNumber: UInt16

    @State private var selectedUniverseNumber: UInt16?

    public init(
        snapshot: EngineFrameSnapshot,
        universes: [Universe] = [],
        defaultUniverseNumber: UInt16 = 1
    ) {
        self.snapshot = snapshot
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

    /// Full DMX frame for the selected universe (padded to channelCount).
    private var levels: [UInt8] {
        let raw = snapshot.universeLevels[universeNumber] ?? []
        if raw.count >= channelCount { return Array(raw.prefix(channelCount)) }
        return raw + Array(repeating: 0, count: channelCount - raw.count)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Universe Monitor")
                    .font(.headline)
                Spacer()
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

            if snapshot.universeLevels[universeNumber] == nil && levels.allSatisfy({ $0 == 0 }) {
                Text("No live data for this universe — patch fixtures and set levels / GO.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView([.vertical, .horizontal]) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 16),
                    spacing: 4
                ) {
                    ForEach(0..<channelCount, id: \.self) { i in
                        let v = levels[i]
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
                        .help("Ch \(i + 1): \(v)")
                    }
                }
                .padding(4)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedUniverseNumber == nil {
                selectedUniverseNumber = universes.first?.number ?? defaultUniverseNumber
            }
        }
        .onChange(of: universes.map(\.number)) { _, numbers in
            if let selected = selectedUniverseNumber, !numbers.contains(selected) {
                selectedUniverseNumber = numbers.first ?? defaultUniverseNumber
            }
        }
    }
}
