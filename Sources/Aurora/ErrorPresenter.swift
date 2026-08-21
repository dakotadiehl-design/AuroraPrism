import AppKit
import AuroraDiagnostics
import Foundation

/// AppKit presenter. Displays only human fields. Does not log.
enum ErrorPresenter {
    @MainActor
    static func present(_ report: PrismErrorReport, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = report.userTitle
        var informative = report.userMessage
        if let recovery = report.recoverySuggestion, !recovery.isEmpty {
            informative += "\n\n" + recovery
        }
        informative += "\n\nReference ID: \(PrismLogSanitizer.publicReference(for: report.correlationID))"
        informative += "\nCopy Support Summary copies the error code and this reference ID. It does not copy file contents, PINs, or raw system dumps."
        alert.informativeText = informative
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy Support Summary")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.supportSummary, forType: .string)
        }
    }

    @MainActor
    static func present(
        error: Error,
        context: PrismErrorContext,
        style: NSAlert.Style = .warning
    ) {
        let report = PrismErrorReporting.report(error: error, context: context)
        present(report, style: style)
    }
}
