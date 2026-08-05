import AuroraDiagnostics
import Foundation

/// Subsystem events, console lines, and project-issue presentation (Stage C / PRE-UI-4).
@MainActor
final class DiagnosticsController: ObservableObject {
    let store: DiagnosticsStore
    @Published private(set) var consoleLog: [String] = []
    @Published private(set) var validationIssueCount: Int = 0

    private let maxConsole = 200

    init(store: DiagnosticsStore = DiagnosticsStore()) {
        self.store = store
    }

    /// Compatibility console line (defaults to `.app` subsystem).
    func log(_ message: String) {
        log(message, subsystem: .app, severity: .info)
    }

    func log(
        _ message: String,
        subsystem: DiagnosticSubsystem,
        severity: DiagnosticSeverity = .info,
        code: String? = nil
    ) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  [\(subsystem.rawValue)] \(message)"
        consoleLog.append(line)
        if consoleLog.count > maxConsole {
            consoleLog.removeFirst(consoleLog.count - maxConsole)
        }
        store.record(DiagnosticEvent(
            subsystem: subsystem,
            severity: severity,
            code: code,
            message: message
        ))
        objectWillChange.send()
    }

    func warning(_ message: String, subsystem: DiagnosticSubsystem, code: String? = nil) {
        log(message, subsystem: subsystem, severity: .warning, code: code)
    }

    func error(_ message: String, subsystem: DiagnosticSubsystem, code: String? = nil) {
        log(message, subsystem: subsystem, severity: .error, code: code)
    }

    func setValidationIssueCount(_ count: Int) {
        validationIssueCount = count
        if count > 0 {
            store.warning(
                "\(count) project validation issue(s)",
                subsystem: .project,
                code: "validation-issues"
            )
        }
    }
}
