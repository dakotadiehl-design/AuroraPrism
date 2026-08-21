import AuroraDiagnostics
import SwiftUI

public struct ConsolePanel: View {
    public var events: [PrismLogEvent]
    public var showTimestamps: Bool
    public var outputStatus: String
    public var onClear: () -> Void

    @State private var textFilter = ""
    @State private var levelFilter: PrismLogLevel? = nil
    @State private var groupFilter: PrismLogCategoryGroup? = nil
    @State private var expanded: Set<UUID> = []

    public init(
        events: [PrismLogEvent],
        showTimestamps: Bool = true,
        outputStatus: String = "",
        onClear: @escaping () -> Void = {}
    ) {
        self.events = events
        self.showTimestamps = showTimestamps
        self.outputStatus = outputStatus
        self.onClear = onClear
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Console").font(.headline)
                Spacer()
                Button("Clear Console View", action: onClear)
                    .controlSize(.small)
            }
            Text("Clearing this view does not erase macOS logs.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(outputStatus)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            filterBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered.suffix(200)) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .padding(8)
    }

    private var filterBar: some View {
        HStack {
            TextField("Filter", text: $textFilter)
                .textFieldStyle(.roundedBorder)
            Picker("Level", selection: $levelFilter) {
                Text("All levels").tag(Optional<PrismLogLevel>.none)
                ForEach(PrismLogLevel.settingsChoices, id: \.self) { level in
                    Text(level.settingsLabel).tag(Optional(level))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
            Picker("Group", selection: $groupFilter) {
                Text("All groups").tag(Optional<PrismLogCategoryGroup>.none)
                ForEach(PrismLogCategoryGroup.allCases, id: \.self) { group in
                    Text(group.displayName).tag(Optional(group))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
        }
        .font(.caption)
    }

    private var filtered: [PrismLogEvent] {
        events.filter { event in
            if let levelFilter, event.level < levelFilter { return false }
            if let groupFilter, event.category.group != groupFilter { return false }
            if !textFilter.isEmpty {
                let hay = "\(event.code) \(event.humanMessage) \(event.technicalMessage ?? "")"
                if hay.range(of: textFilter, options: .caseInsensitive) == nil { return false }
            }
            return true
        }
    }

    @ViewBuilder
    private func eventRow(_ event: PrismLogEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if expanded.contains(event.id) {
                    expanded.remove(event.id)
                } else {
                    expanded.insert(event.id)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if showTimestamps {
                        Text(Self.timestampFormatter.string(from: event.timestamp))
                            .foregroundStyle(.tertiary)
                    }
                    Text(event.level.rawValue.uppercased())
                        .foregroundStyle(color(for: event.level))
                    Text(event.humanMessage)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if expanded.contains(event.id) {
                Text("code=\(event.code)  category=\(event.category.rawValue)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let technical = event.technicalMessage, !technical.isEmpty {
                    Text(technical)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func color(for level: PrismLogLevel) -> Color {
        switch level {
        case .error, .fault: return .red
        case .warning: return .orange
        case .notice: return .primary
        default: return .secondary
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
