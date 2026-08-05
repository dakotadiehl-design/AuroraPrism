import AuroraDiagnostics
import Foundation

/// Subsystem events, console lines, and project-issue presentation (Stage C).
@MainActor
final class DiagnosticsController: ObservableObject {
    let store: DiagnosticsStore
    @Published private(set) var consoleLog: [String] = []
    @Published private(set) var validationIssueCount: Int = 0

    private let maxConsole = 200

    init(store: DiagnosticsStore = DiagnosticsStore()) {
        self.store = store
    }

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)"
        consoleLog.append(line)
        if consoleLog.count > maxConsole {
            consoleLog.removeFirst(consoleLog.count - maxConsole)
        }
        store.info(message, subsystem: .app)
        objectWillChange.send()
    }

    func setValidationIssueCount(_ count: Int) {
        validationIssueCount = count
    }
}
