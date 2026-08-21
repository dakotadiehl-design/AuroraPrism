import AuroraDiagnostics
import Foundation

/// Subsystem events, console lines, and project-issue presentation (Stage C / DIAG-01).
@MainActor
final class DiagnosticsController: ObservableObject {
    let store: DiagnosticsStore
    let memorySink: InMemoryPrismLogSink
    @Published private(set) var consoleEvents: [PrismLogEvent] = []
    @Published private(set) var validationIssueCount: Int = 0
    /// Semantic operator-facing diagnostics projection.
    @Published private(set) var snapshot: DiagnosticsSnapshot = .empty

    private let maxConsole = 200
    private var refreshTimer: Timer?
    private var builder: (() -> DiagnosticsSnapshot)?

    init(store: DiagnosticsStore = DiagnosticsStore(), memorySink: InMemoryPrismLogSink = .shared) {
        self.store = store
        self.memorySink = memorySink
    }

    /// Compatibility formatted lines (timestamp added at presentation time).
    var consoleLog: [String] {
        consoleEvents.suffix(maxConsole).map(\.humanMessage)
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
        let latest = memorySink.snapshot(limit: maxConsole)
        if latest.map(\.id) != consoleEvents.map(\.id) {
            consoleEvents = latest
        }
        guard let builder else { return }
        let next = builder()
        // Avoid @Published churn when only generatedAt (or nothing) changed —
        // cascade into AppModel was redrawing Settings TabView icons.
        if next == snapshot { return }
        if next.semanticallyEqual(to: snapshot) { return }
        snapshot = next
    }

    func clearConsoleView() {
        memorySink.clear()
        consoleEvents = []
    }

    /// Compatibility console line. Prefer `PrismLog` for new call sites.
    func log(_ message: String) {
        log(message, subsystem: .app, severity: .info)
    }

    func log(
        _ message: String,
        subsystem: DiagnosticSubsystem,
        severity: DiagnosticSeverity = .info,
        code: String? = nil
    ) {
        let category: PrismLogCategory
        switch subsystem {
        case .app: category = .appLifecycle
        case .engine: category = .engineShow
        case .output: category = .outputRouting
        case .midi: category = .controlMIDI
        case .remote: category = .remoteHost
        case .project: category = .projectDocument
        case .resolution: category = .projectValidation
        }
        let level: PrismLogLevel
        switch severity {
        case .debug: level = .debug
        case .info: level = .info
        case .warning: level = .warning
        case .error: level = .error
        }
        PrismLog.shared.log(
            PrismLogEvent(
                level: level,
                category: category,
                code: code ?? "compat.\(subsystem.rawValue)",
                humanMessage: message
            )
        )
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
            PrismLog.info(
                .projectValidation,
                "project.validation.summary",
                "This show has validation issues.",
                metadata: ["count": .count(count)]
            )
        }
    }
}
