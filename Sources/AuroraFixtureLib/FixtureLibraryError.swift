import AuroraDiagnostics
import Foundation

public enum FixtureLibraryError: Error, Equatable, Sendable {
    case resourceMissing(String)
    case catalogInvalid(String)
    case definitionInvalid(String)
    case decodingFailed(String)
}

extension FixtureLibraryError: LocalizedError, PrismDiagnosableError {
    public var errorDescription: String? { userMessage }
    public var prismErrorCode: String {
        switch self {
        case .resourceMissing: return "fixture.library.resource_missing"
        case .catalogInvalid: return "fixture.library.catalog_invalid"
        case .definitionInvalid: return "fixture.library.definition_invalid"
        case .decodingFailed: return "fixture.library.decode_failed"
        }
    }
    public var userTitle: String {
        switch self {
        case .definitionInvalid: return "Prism Couldn't Save the Fixture Profile"
        case .decodingFailed: return "Prism Couldn't Read the Fixture Definition"
        case .resourceMissing, .catalogInvalid: return "Prism Couldn't Load the Fixture Library"
        }
    }
    public var userMessage: String {
        switch self {
        case .definitionInvalid(let reason):
            return "The fixture profile is invalid: \(reason)."
        case .resourceMissing:
            return "A required fixture-library resource is missing."
        case .catalogInvalid:
            return "The fixture-library catalog is invalid."
        case .decodingFailed:
            return "The fixture definition could not be decoded."
        }
    }
    public var recoverySuggestion: String? {
        switch self {
        case .definitionInvalid:
            return "Correct the highlighted fixture identity, channel, or DMX range and try again."
        case .decodingFailed:
            return "Check that the file is a supported Prism fixture definition and try again."
        case .resourceMissing, .catalogInvalid:
            return "Restart Prism. If this keeps happening, reinstall or restore the built-in library."
        }
    }
    public var technicalDetails: String { String(reflecting: self) }
    public var prismCategory: PrismLogCategory { .fixtureLibrary }
    public var prismSeverity: PrismLogLevel { .error }
}
