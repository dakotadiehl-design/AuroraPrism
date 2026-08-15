import AuroraDiagnostics
import Foundation

/// Subsystem events, console lines, and project-issue presentation (Stage C / DIAG-01).
@MainActor
final class DiagnosticsController: ObservableObject {
    let store: DiagnosticsStore
    @Published private(set) var consoleLog: [String] = []
    @Published private(set) var validationIssueCount: Int = 0
    /// Semantic operator-facing diagnostics projection.
    @Published private(set) var snapshot: DiagnosticsSnapshot = .empty

    private let maxConsole = 200
    private var refreshTimer: Timer?
    private var builder: (() -> DiagnosticsSnapshot)?

    init(store: DiagnosticsStore = DiagnosticsStore()) {
        self.store = store
    }

    func publishSnapshot(_ snap: DiagnosticsSnapshot) {
        snapshot = snap
    }

    /// DIAG-01: periodic refresh of semantic snapshot (throttled).
    func startLiveUpdates(interval: TimeInterval = 0.4, builder: @escaping () -> DiagnosticsSnapshot) {
        self.builder = builder
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // Immediate first paint.
        tick()
    }

    func stopLiveUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Immediate refresh after important transitions (MIDI hotplug, output toggle, etc.).
    func refreshNow() {
        tick()
    }

    private func tick() {
        guard let builder else { return }
        let next = builder()
        // Avoid @Published churn when only generatedAt (or nothing) changed —
        // cascade into AppModel was redrawing Settings TabView icons.
        if next == snapshot { return }
        if next.semanticallyEqual(to: snapshot) { return }
        snapshot = next
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
