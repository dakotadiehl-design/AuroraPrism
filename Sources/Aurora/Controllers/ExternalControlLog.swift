import Combine
import Foundation

/// Structured external-control event for the unified monitor (P0-K).
struct ExternalControlEntry: Equatable, Identifiable, Sendable {
    var id: UUID
    var time: Date
    var source: String
    var event: String
    var mapping: String
    var result: String
    var isError: Bool

    init(
        id: UUID = UUID(),
        time: Date = Date(),
        source: String,
        event: String,
        mapping: String = "—",
        result: String,
        isError: Bool = false
    ) {
        self.id = id
        self.time = time
        self.source = source
        self.event = event
        self.mapping = mapping
        self.result = result
        self.isError = isError
    }
}

@MainActor
final class ExternalControlLog: ObservableObject {
    @Published private(set) var entries: [ExternalControlEntry] = []
    private let maxEntries = 500

    func append(_ entry: ExternalControlEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func record(
        source: String,
        event: String,
        mapping: String = "—",
        result: String,
        isError: Bool = false
    ) {
        append(ExternalControlEntry(
            source: source,
            event: event,
            mapping: mapping,
            result: result,
            isError: isError
        ))
    }

    func clear() {
        entries.removeAll()
    }
}
