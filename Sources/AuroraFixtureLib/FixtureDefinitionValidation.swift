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
        let footprint = definition.calculatedFootprint
        if footprint == 0 {
            throw FixtureLibraryError.definitionInvalid("channelCount must be > 0")
        }
        // Multi-cell fixtures may have empty header channels and only a cellBlock.
        let hasCells = (definition.cellBlock?.cellCount ?? 0) > 0
            && !(definition.cellBlock?.channels.isEmpty ?? true)
        if definition.channels.isEmpty && !hasCells {
            throw FixtureLibraryError.definitionInvalid("channels must not be empty")
        }

        var seenOffsets = Set<UInt16>()
        for channel in definition.channels {
            guard channel.offset >= 1, channel.offset <= footprint else {
                throw FixtureLibraryError.definitionInvalid(
                    "channel offset \(channel.offset) out of range 1…\(footprint)"
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
        if let block = definition.cellBlock, block.cellCount > 0 {
            if block.channels.isEmpty {
                throw FixtureLibraryError.definitionInvalid("cellBlock channels must not be empty")
            }
            var cellOffsets = Set<UInt16>()
            for channel in block.channels {
                if cellOffsets.contains(channel.offset) {
                    throw FixtureLibraryError.definitionInvalid("duplicate cell channel offset \(channel.offset)")
                }
                cellOffsets.insert(channel.offset)
            }
        }
    }
}
