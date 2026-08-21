#if os(macOS)
import AppKit
#endif
import AuroraDiagnostics
import SwiftUI

public func prismUserMessage(_ error: Error, fallback: String = "That change couldn't be applied.") -> String {
    PrismErrorReporting.userFacingMessage(for: error, fallback: fallback)
}

@discardableResult
public func prismReportCommandFailure(
    _ error: Error,
    operation: String,
    category: PrismLogCategory = .projectDocument,
    logger: (any PrismLogging)? = nil
) -> String {
    PrismErrorReporting.statusMessage(for: error, operation: operation, category: category, logger: logger)
}

public struct PrismErrorAlertModifier: ViewModifier {
    @Binding var report: PrismErrorReport?

    public func body(content: Content) -> some View {
        content.alert(
            report?.userTitle ?? "Prism Couldn't Complete That Action",
            isPresented: Binding(
                get: { report != nil },
                set: { if !$0 { report = nil } }
            )
        ) {
            Button("OK", role: .cancel) { report = nil }
            Button("Copy Support Summary") {
                guard let report else { return }
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.supportSummary, forType: .string)
                #endif
            }
        } message: {
            VStack(alignment: .leading, spacing: 6) {
                Text(report?.userMessage ?? "")
                if let recovery = report?.recoverySuggestion {
                    Text(recovery)
                }
                if let report {
                    Text("Reference ID: \(PrismLogSanitizer.publicReference(for: report.correlationID))")
                    Text("Copy Support Summary copies the error code and reference ID only.")
                        .font(.caption)
                }
            }
        }
    }
}

public extension View {
    func prismErrorAlert(item: Binding<PrismErrorReport?>) -> some View {
        modifier(PrismErrorAlertModifier(report: item))
    }
}
