import SwiftUI

/// Build lower-region operator diagnostics surface (UI-09 / LAYOUT-02).
/// Binds to a pre-built snapshot — does not assemble diagnostics in the view body.
public struct DiagnosticsPanel: View {
    public struct SnapshotView: Equatable, Sendable {
        public var engineRunning: Bool
        public var frameRateHz: Double
        public var outputStatusLine: String
        public var localDMXStatus: String
        public var localDMXEnabled: Bool
        public var localDMXRequested: Bool
        public var localDMXDeviceAvailable: Bool
        public var artNetEnabled: Bool
        public var sacnEnabled: Bool
        public var midiStatus: String
        public var midiState: String
        public var midiSourceCount: Int
        public var remoteStatus: String
        public var remoteActuallyRunning: Bool
        public var remoteClientCount: Int
        public var validationIssueCount: Int
        public var driverRows: [Row]
        public var universeRows: [Row]
        public var consoleTail: [String]
        public var fixtureHealthRows: [Row]
        public var externalControlRows: [Row]

        public struct Row: Equatable, Sendable, Identifiable {
            public var id: String
            public var title: String
            public var detail: String
            public init(id: String, title: String, detail: String) {
                self.id = id
                self.title = title
                self.detail = detail
            }
        }

        public init(
            engineRunning: Bool,
            frameRateHz: Double,
            outputStatusLine: String,
            localDMXStatus: String,
            localDMXEnabled: Bool,
            localDMXRequested: Bool,
            localDMXDeviceAvailable: Bool,
            artNetEnabled: Bool,
            sacnEnabled: Bool,
            midiStatus: String,
            midiState: String,
            midiSourceCount: Int,
            remoteStatus: String,
            remoteActuallyRunning: Bool,
            remoteClientCount: Int,
            validationIssueCount: Int,
            driverRows: [Row],
            universeRows: [Row],
            consoleTail: [String],
            fixtureHealthRows: [Row] = [],
            externalControlRows: [Row] = []
        ) {
            self.engineRunning = engineRunning
            self.frameRateHz = frameRateHz
            self.outputStatusLine = outputStatusLine
            self.localDMXStatus = localDMXStatus
            self.localDMXEnabled = localDMXEnabled
            self.localDMXRequested = localDMXRequested
            self.localDMXDeviceAvailable = localDMXDeviceAvailable
            self.artNetEnabled = artNetEnabled
            self.sacnEnabled = sacnEnabled
            self.midiStatus = midiStatus
            self.midiState = midiState
            self.midiSourceCount = midiSourceCount
            self.remoteStatus = remoteStatus
            self.remoteActuallyRunning = remoteActuallyRunning
            self.remoteClientCount = remoteClientCount
            self.validationIssueCount = validationIssueCount
            self.driverRows = driverRows
            self.universeRows = universeRows
            self.consoleTail = consoleTail
            self.fixtureHealthRows = fixtureHealthRows
            self.externalControlRows = externalControlRows
        }

        public static let empty = SnapshotView(
            engineRunning: false,
            frameRateHz: 0,
            outputStatusLine: "",
            localDMXStatus: "",
            localDMXEnabled: false,
            localDMXRequested: false,
            localDMXDeviceAvailable: false,
            artNetEnabled: false,
            sacnEnabled: false,
            midiStatus: "",
            midiState: "off",
            midiSourceCount: 0,
            remoteStatus: "",
            remoteActuallyRunning: false,
            remoteClientCount: 0,
            validationIssueCount: 0,
            driverRows: [],
            universeRows: [],
            consoleTail: [],
            fixtureHealthRows: [],
            externalControlRows: []
        )
    }

    public var snapshot: SnapshotView

    public init(snapshot: SnapshotView) {
        self.snapshot = snapshot
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("Engine") {
                    Text(snapshot.engineRunning
                         ? String(format: "Running · %.0f Hz", snapshot.frameRateHz)
                         : "Stopped")
                        .font(.body.monospaced())
                }
                section("Output") {
                    Text(snapshot.outputStatusLine.isEmpty ? "—" : snapshot.outputStatusLine)
                        .font(.caption.monospaced())
                    Text("Art-Net \(onOff(snapshot.artNetEnabled)) · sACN \(onOff(snapshot.sacnEnabled))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localDMXLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                section("MIDI") {
                    Text(snapshot.midiStatus)
                        .font(.caption.monospaced())
                    Text("state \(snapshot.midiState) · \(snapshot.midiSourceCount) source(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                section("Remote") {
                    Text(snapshot.remoteStatus)
                        .font(.caption.monospaced())
                    Text(snapshot.remoteActuallyRunning
                         ? "Runtime running · \(snapshot.remoteClientCount) client(s)"
                         : "Runtime stopped · \(snapshot.remoteClientCount) client(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !snapshot.driverRows.isEmpty {
                    section("Drivers") {
                        ForEach(snapshot.driverRows) { row in
                            HStack {
                                Text(row.title)
                                Spacer()
                                Text(row.detail)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption.monospaced())
                        }
                    }
                }
                if !snapshot.universeRows.isEmpty {
                    section("Universe routes") {
                        ForEach(snapshot.universeRows) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.caption.weight(.semibold))
                                Text(row.detail)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                section("Validation") {
                    Text("\(snapshot.validationIssueCount) issue(s)")
                        .font(.caption)
                }
                if !snapshot.fixtureHealthRows.isEmpty {
                    section("Fixture health") {
                        ForEach(snapshot.fixtureHealthRows) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.caption.weight(.semibold))
                                Text(row.detail)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(row.detail.contains("OK") ? .secondary : Color.orange)
                            }
                        }
                    }
                }
                if !snapshot.externalControlRows.isEmpty {
                    section("External control") {
                        ForEach(snapshot.externalControlRows) { row in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title)
                                    .font(.caption2.monospaced())
                                Text(row.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !snapshot.consoleTail.isEmpty {
                    section("Recent log") {
                        ForEach(Array(snapshot.consoleTail.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var localDMXLine: String {
        var parts = [snapshot.localDMXStatus]
        parts.append("requested \(snapshot.localDMXRequested ? "yes" : "no")")
        parts.append("actual \(snapshot.localDMXEnabled ? "yes" : "no")")
        parts.append("device \(snapshot.localDMXDeviceAvailable ? "present" : "absent")")
        return parts.joined(separator: " · ")
    }

    private func onOff(_ v: Bool) -> String { v ? "on" : "off" }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
