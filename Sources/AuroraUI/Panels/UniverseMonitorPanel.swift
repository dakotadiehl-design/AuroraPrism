import AuroraEngine
import SwiftUI

/// Live DMX channel view from engine snapshots.
public struct UniverseMonitorPanel: View {
    public var snapshot: EngineFrameSnapshot
    public var universeNumber: UInt16

    public init(snapshot: EngineFrameSnapshot, universeNumber: UInt16 = 1) {
        self.snapshot = snapshot
        self.universeNumber = universeNumber
    }

    private var levels: [UInt8] {
        snapshot.universeLevels[universeNumber] ?? []
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Universe \(universeNumber)")
                .font(.headline)
            Text("Frame \(snapshot.frameIndex) · \(levels.filter { $0 > 0 }.count) ch active")
                .font(.caption)
                .foregroundStyle(.secondary)

            if levels.isEmpty {
                Text("No data — patch fixtures and set levels / GO.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 16), spacing: 4) {
                        ForEach(0..<min(levels.count, 128), id: \.self) { i in
                            let v = levels[i]
                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green.opacity(Double(v) / 255.0))
                                    .frame(height: 28)
                                Text("\(i + 1)")
                                    .font(.system(size: 8).monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
