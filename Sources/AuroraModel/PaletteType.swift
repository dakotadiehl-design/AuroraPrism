import Foundation

/// Semantic family of a palette (extensible via raw value storage).
public enum PaletteType: String, Codable, Sendable, Hashable, CaseIterable {
    case intensity
    case color
    case position
    case beam
    case gobo
    case general
}
