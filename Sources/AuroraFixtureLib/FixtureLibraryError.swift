import Foundation

public enum FixtureLibraryError: Error, Equatable, Sendable {
    case resourceMissing(String)
    case catalogInvalid(String)
    case definitionInvalid(String)
    case decodingFailed(String)
}
