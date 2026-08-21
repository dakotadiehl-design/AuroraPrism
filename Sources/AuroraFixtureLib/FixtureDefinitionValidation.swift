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
            for function in channel.dmxFunctions where function.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FixtureLibraryError.definitionInvalid("DMX function name is empty at offset \(channel.offset)")
            }
            for function in channel.dmxFunctions where function.dmxMin > function.dmxMax {
                throw FixtureLibraryError.definitionInvalid(
                    "DMX function range is reversed at offset \(channel.offset): \(function.dmxMin)…\(function.dmxMax)"
                )
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
        let controlIDs = definition.controlElements.map(\.id)
        if Set(controlIDs).count != controlIDs.count {
            throw FixtureLibraryError.definitionInvalid("duplicate controllable element id")
        }
        let declaredControls = Set(controlIDs)
        let channelControls = Set(definition.channels.compactMap(\.elementID))
        if !declaredControls.isEmpty, !channelControls.isSubset(of: declaredControls) {
            throw FixtureLibraryError.definitionInvalid("channel references an unknown controllable element")
        }
        if let physical = definition.portablePhysicalDefinition {
            if let physicalID = definition.physicalFixtureID, physicalID != physical.id {
                throw FixtureLibraryError.definitionInvalid("portable physical definition id does not match physicalFixtureID")
            }
            let emitterIDs = physical.emitters.map(\.id)
            if Set(emitterIDs).count != emitterIDs.count {
                throw FixtureLibraryError.definitionInvalid("duplicate physical emitter id")
            }
            let knownEmitters = Set(emitterIDs)
            let mappingIDs = definition.emitterMappings.map(\.id)
            if Set(mappingIDs).count != mappingIDs.count {
                throw FixtureLibraryError.definitionInvalid("duplicate emitter mapping id")
            }
            for mapping in definition.emitterMappings {
                if mapping.controlElementIDs.isEmpty || mapping.physicalEmitterIDs.isEmpty {
                    throw FixtureLibraryError.definitionInvalid("emitter mapping endpoints must not be empty")
                }
                if !declaredControls.isEmpty, !mapping.controlElementIDs.isSubset(of: declaredControls) {
                    throw FixtureLibraryError.definitionInvalid("emitter mapping references an unknown controllable element")
                }
                if !mapping.physicalEmitterIDs.isSubset(of: knownEmitters) {
                    throw FixtureLibraryError.definitionInvalid("emitter mapping references an unknown physical emitter")
                }
            }
            let mappedControls = Set(definition.emitterMappings.flatMap(\.controlElementIDs))
            if !physical.emitters.isEmpty, !declaredControls.isSubset(of: mappedControls) {
                throw FixtureLibraryError.definitionInvalid("controllable element has no physical emitter mapping")
            }
        }
    }

    /// Strict authoring rule for the native Fixture Creator. Imported personalities may
    /// intentionally contain overlapping selector ranges, so compatibility validation
    /// above preserves them while new hand-authored profiles remain unambiguous.
    public static func validateAuthoredFunctionRanges(_ definition: FixtureDefinition) throws {
        for channel in definition.channels {
            let ordered = channel.dmxFunctions.sorted {
                if $0.dmxMin != $1.dmxMin { return $0.dmxMin < $1.dmxMin }
                return $0.dmxMax < $1.dmxMax
            }
            for pair in zip(ordered, ordered.dropFirst()) where pair.1.dmxMin <= pair.0.dmxMax {
                throw FixtureLibraryError.definitionInvalid(
                    "overlapping DMX function ranges at offset \(channel.offset): \(pair.0.dmxMin)…\(pair.0.dmxMax) and \(pair.1.dmxMin)…\(pair.1.dmxMax)"
                )
            }
        }
    }
}
