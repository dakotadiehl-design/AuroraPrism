import Foundation

public protocol PrismDiagnosableError: Error {
    var prismErrorCode: String { get }
    var userTitle: String { get }
    var userMessage: String { get }
    var recoverySuggestion: String? { get }
    var technicalDetails: String { get }
    var prismCategory: PrismLogCategory { get }
    var prismSeverity: PrismLogLevel { get }
}

public extension PrismDiagnosableError {
    var userTitle: String { "Prism Couldn't Complete That Action" }
    var recoverySuggestion: String? { "Try again. If it keeps happening, copy the technical details and send them with your support request." }
    var technicalDetails: String { String(reflecting: self) }
    var prismSeverity: PrismLogLevel { .error }
}

public struct PrismErrorContext: Sendable {
    public var operation: String
    public var userVisibleObject: String?
    public var category: PrismLogCategory?
    public var fallbackTitle: String
    public var fallbackMessage: String
    public var recoverySuggestion: String?
    public var eventCode: String?

    public init(
        operation: String,
        userVisibleObject: String? = nil,
        category: PrismLogCategory? = nil,
        fallbackTitle: String,
        fallbackMessage: String,
        recoverySuggestion: String? = nil,
        eventCode: String? = nil
    ) {
        self.operation = operation
        self.userVisibleObject = userVisibleObject
        self.category = category
        self.fallbackTitle = fallbackTitle
        self.fallbackMessage = fallbackMessage
        self.recoverySuggestion = recoverySuggestion
        self.eventCode = eventCode
    }

    public static func projectOpen(objectLabel: String? = nil) -> PrismErrorContext {
        PrismErrorContext(
            operation: "open show",
            userVisibleObject: objectLabel,
            category: .projectDocument,
            fallbackTitle: "Prism Couldn't Open the Show",
            fallbackMessage: "Prism couldn't open this show.",
            recoverySuggestion: "Choose another file, or contact support with the reference ID.",
            eventCode: "project.document.open_failed"
        )
    }

    public static func projectSave(objectLabel: String? = nil) -> PrismErrorContext {
        PrismErrorContext(
            operation: "save show",
            userVisibleObject: objectLabel,
            category: .projectDocument,
            fallbackTitle: "Prism Couldn't Save the Show",
            fallbackMessage: "Prism couldn't save this show.",
            recoverySuggestion: "Try saving to another location, or contact support with the reference ID.",
            eventCode: "project.document.save_failed"
        )
    }

    public static func projectImport(objectLabel: String? = nil) -> PrismErrorContext {
        PrismErrorContext(
            operation: "import",
            userVisibleObject: objectLabel,
            category: .projectDocument,
            fallbackTitle: "Prism Couldn't Import That File",
            fallbackMessage: "Prism couldn't import that file.",
            recoverySuggestion: "Choose another file, or contact support with the reference ID.",
            eventCode: "project.document.import_failed"
        )
    }

    public static func command(operation: String, category: PrismLogCategory = .projectDocument) -> PrismErrorContext {
        let code: String
        switch category {
        case .uiPatch:
            code = operation.contains("rename") ? "patch.rename.failed" : "ui.patch.command_failed"
        case .uiStage:
            code = operation.contains("media") ? "ui.stage.media_failed" : "ui.stage.layout_commit_failed"
        case .fixtureLibrary:
            code = operation.contains("save") ? "fixture.library.save_failed" : "fixture.library.failed"
        case .fixtureImport:
            code = "fixture.import.failed"
        case .fixtureLightkey:
            code = "fixture.lightkey.import_failed"
        case .engineEffects:
            code = "engine.effects.update_failed"
        default:
            code = "project.command.failed"
        }
        return PrismErrorContext(
            operation: operation,
            category: category,
            fallbackTitle: "Prism Couldn't Complete That Action",
            fallbackMessage: "That change couldn't be applied.",
            recoverySuggestion: "Undo if needed, then try the action again.",
            eventCode: code
        )
    }
}

public struct PrismErrorReport: Sendable, Equatable, Identifiable {
    public var id: UUID { correlationID }
    public let code: String
    public let userTitle: String
    public let userMessage: String
    public let recoverySuggestion: String?
    public let technicalDescription: String
    public let underlyingChain: [String]
    public let category: PrismLogCategory
    public let severity: PrismLogLevel
    public let metadata: [String: PrismLogValue]
    public let correlationID: UUID

    public init(
        code: String,
        userTitle: String,
        userMessage: String,
        recoverySuggestion: String?,
        technicalDescription: String,
        underlyingChain: [String],
        category: PrismLogCategory,
        severity: PrismLogLevel,
        metadata: [String: PrismLogValue] = [:],
        correlationID: UUID = UUID()
    ) {
        self.code = code
        self.userTitle = userTitle
        self.userMessage = userMessage
        self.recoverySuggestion = recoverySuggestion
        self.technicalDescription = technicalDescription
        self.underlyingChain = underlyingChain
        self.category = category
        self.severity = severity
        self.metadata = metadata
        self.correlationID = correlationID
    }

    public var supportSummary: String {
        PrismLogSanitizer.supportSummary(for: self)
    }
}
