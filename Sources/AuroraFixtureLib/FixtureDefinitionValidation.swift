import AuroraModel
import Foundation

/// Validation rules for personalities loaded from seed or user import.
public enum FixtureDefinitionValidation {
    public static func validate(_ definition: FixtureDefinition) throws {
        if definition.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FixtureLibraryError.definitionInvalid("manufacturer is empty")
        }
        if definition.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FixtureLibraryError.definitionInvalid("model is empty")
        }
        if definition.channelCount == 0 {
            throw FixtureLibraryError.definitionInvalid("channelCount must be > 0")
        }
        if definition.channels.isEmpty {
            throw FixtureLibraryError.definitionInvalid("channels must not be empty")
        }

        var seenOffsets = Set<UInt16>()
        for channel in definition.channels {
            guard channel.offset >= 1, channel.offset <= definition.channelCount else {
                throw FixtureLibraryError.definitionInvalid(
                    "channel offset \(channel.offset) out of range 1…\(definition.channelCount)"
                )
            }
            if seenOffsets.contains(channel.offset) {
                throw FixtureLibraryError.definitionInvalid("duplicate channel offset \(channel.offset)")
            }
            seenOffsets.insert(channel.offset)
            if channel.attribute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FixtureLibraryError.definitionInvalid("channel attribute is empty at offset \(channel.offset)")
            }
        }
    }
}
