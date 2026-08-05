import SwiftUI

public struct ConsolePanel: View {
    public var lines: [String]
    public var midiLines: [String]
    public var outputStatus: String

    public init(lines: [String], midiLines: [String] = [], outputStatus: String = "") {
        self.lines = lines
        self.midiLines = midiLines
        self.outputStatus = outputStatus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Console").font(.headline)
            Text(outputStatus)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Divider()
            Text("Log")
                .font(.caption.weight(.semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Divider()
            Text("MIDI")
                .font(.caption.weight(.semibold))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(midiLines.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
            .frame(maxHeight: 100)
        }
        .padding(8)
    }
}
