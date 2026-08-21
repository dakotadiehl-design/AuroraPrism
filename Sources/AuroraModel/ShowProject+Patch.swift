import Foundation

public extension ShowProject {
    func definition(id: UUID) -> FixtureDefinition? {
        fixtureDefinitions.first { $0.id == id }
    }

    func physicalFixture(id: UUID) -> FixturePhysicalDefinition? {
        physicalFixtureDefinitions?.first { $0.id == id }
    }

    func physicalFixture(for definition: FixtureDefinition) -> FixturePhysicalDefinition? {
        if let id = definition.physicalFixtureID {
            if let physical = physicalFixture(id: id) ?? definition.portablePhysicalDefinition {
                return completedImportedPixelTopology(physical, for: definition)
            }
        }
        if let portable = definition.portablePhysicalDefinition {
            return completedImportedPixelTopology(portable, for: definition)
        }
        return legacySharedPhysicalFixture(for: definition)
    }

    /// Older fixture-library imports can preserve an authoritative strip/array layout
    /// without materializing its apertures. Complete that shared physical record from
    /// a sibling personality that has explicit RGB-family element ownership. This is
    /// topology recovery, not DMX inference: physical ids are newly namespaced and no
    /// channel or control identity is rewritten.
    private func completedImportedPixelTopology(
        _ physical: FixturePhysicalDefinition,
        for definition: FixtureDefinition
    ) -> FixturePhysicalDefinition {
        guard physical.emitters.isEmpty else { return physical }
        let importedTopology = importedPixelTopology(from: physical.sourceMetadata["beamLayoutClass"])
        let declaredBeamCount = physical.sourceMetadata["numberOfBeams"].flatMap(Int.init)
        let linearPhysicalForm = physical.form == .linearBar || physical.form == .strip || physical.form == .multiHeadBar
        guard let topology = importedTopology ?? ((declaredBeamCount ?? 0) > 1 && linearPhysicalForm ? .linear : nil)
        else { return physical }

        let siblings = fixtureDefinitions.filter { candidate in
            if let physicalID = definition.physicalFixtureID {
                return candidate.physicalFixtureID == physicalID
            }
            return candidate.manufacturer.compare(definition.manufacturer, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && candidate.model.compare(definition.model, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard let source = siblings
            .compactMap({ candidate -> (FixtureDefinition, [String])? in
                let ids = orderedRGBEmitterElementIDs(in: candidate)
                return ids.count > 1 ? (candidate, ids) : nil
            })
            .max(by: { $0.1.count < $1.1.count })
        else { return physical }

        // An undefined imported layout may be completed only when two independent
        // pieces of explicit data agree: the archive's beam count and the
        // personality's RGB-owned control-element count.
        if importedTopology == nil, source.1.count != declaredBeamCount { return physical }

        let count = source.1.count
        let columns = topology == .linear ? count : max(1, Int(ceil(sqrt(Double(count)))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let emitters = source.1.enumerated().map { index, _ in
            let x = topology == .linear
                ? (Double(index) + 0.5) / Double(count)
                : (Double(index % columns) + 0.5) / Double(columns)
            let y = topology == .linear
                ? 0.5
                : (Double(index / columns) + 0.5) / Double(rows)
            return FixturePhysicalEmitter(
                id: "physical-pixel-\(index)", name: "Pixel \(index + 1)",
                x: x, y: y,
                width: topology == .linear ? min(0.12, 0.72 / Double(count)) : min(0.3, 0.72 / Double(columns)),
                height: topology == .linear ? 0.52 : min(0.3, 0.72 / Double(rows)),
                opticalBehaviors: [.wash, .pixel]
            )
        }
        var completed = physical
        completed.form = topology == .linear ? .linearBar : .panel
        completed.aspectRatio = topology == .linear ? max(3.2, Double(count) * 0.45) : physical.aspectRatio
        completed.emitters = emitters
        completed.componentGroups = [
            .init(
                id: "imported-pixel-array", role: .emitterArray, topology: topology,
                rows: rows,
                columns: columns,
                emitterIDs: emitters.map(\.id), provenance: .imported
            ),
        ]
        completed.opticalBehaviors.formUnion([.wash, .pixel])
        completed.sourceMetadata["topologyCompletedFrom"] = importedTopology == nil
            ? "declared-beam-count+explicit-rgb-element-ownership"
            : "explicit-rgb-element-ownership"
        return completed
    }

    private func importedPixelTopology(from layoutClass: String?) -> FixturePhysicalTopologyKind? {
        switch layoutClass?.lowercased() {
        case "lxstripbeamlayout": return .linear
        case "lxarraybeamlayout": return .array
        default: return nil
        }
    }

    /// Preserves first-channel order. Requiring an RGB triplet per owned element keeps
    /// HSIC and repeated-but-unowned channel modes out of this compatibility path.
    private func orderedRGBEmitterElementIDs(in definition: FixtureDefinition) -> [String] {
        var order: [String] = []
        var attributes: [String: Set<String>] = [:]
        for channel in definition.channels {
            guard let elementID = channel.elementID else { continue }
            if attributes[elementID] == nil { order.append(elementID) }
            attributes[elementID, default: []].insert(channel.attribute.lowercased())
        }
        return order.filter { id in
            let owned = attributes[id] ?? []
            return owned.isSuperset(of: ["colorr", "colorg", "colorb"])
        }
    }

    /// Adapts explicit, pre-physical-metadata Prism cell semantics without rewriting
    /// channel ownership. All personalities for the same product see one topology;
    /// repeated channel patterns alone are deliberately never considered.
    private func legacySharedPhysicalFixture(for definition: FixtureDefinition) -> FixturePhysicalDefinition? {
        let productDefinitions = fixtureDefinitions.filter {
            $0.manufacturer.compare(definition.manufacturer, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
            $0.model.compare(definition.model, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if let source = productDefinitions
            .filter({ ($0.cellBlock?.cellCount ?? 0) > 1 })
            .max(by: { ($0.cellBlock?.cellCount ?? 0) < ($1.cellBlock?.cellCount ?? 0) }),
           let block = source.cellBlock {
            return makeLegacyCellPhysicalFixture(definition: definition, productDefinitions: productDefinitions, block: block)
        }

        // Some early imports preserved explicit programmer ownership but predate
        // physical metadata. Recover a shared linear topology only when (a) several
        // stable owned elements exist, (b) every one owns an emitter channel, and
        // (c) weak form-factor language says the product is linear. Channel repetition
        // itself is never inspected and physical IDs remain independent.
        let linearWords = ["bar", "batten", "strip", "band"]
        let productWords = "\(definition.model) \(definition.category)".lowercased()
        guard linearWords.contains(where: productWords.contains),
              let ownedSource = productDefinitions
                .filter({ $0.elements.count > 1 && explicitlyOwnedEmitterElements(in: $0).count == $0.elements.count })
                .max(by: { $0.elements.count < $1.elements.count }) else { return nil }
        let owned = ownedSource.elements
        let emitters = owned.enumerated().map { index, element in
            FixturePhysicalEmitter(
                id: "legacy-physical-\(index)", name: element.name,
                x: (Double(index) + 0.5) / Double(owned.count), y: 0.5,
                width: min(0.2, 0.72 / Double(owned.count)), height: 0.52,
                opticalBehaviors: [.wash, .pixel]
            )
        }
        let sharedID = productDefinitions.map(\.id).sorted { $0.uuidString < $1.uuidString }.first ?? definition.id
        return FixturePhysicalDefinition(
            id: sharedID, manufacturer: definition.manufacturer, model: definition.model,
            form: .linearBar, aspectRatio: max(3.2, Double(owned.count) * 1.05),
            emitters: emitters,
            componentGroups: [.init(id: "legacy-explicit-elements", role: .emitterArray, topology: .linear, emitterIDs: emitters.map(\.id), provenance: .legacy)],
            opticalBehaviors: [.wash, .pixel], movement: .static, source: .legacy,
            sourceMetadata: ["adaptedFrom": "explicit-element-ownership", "formInference": "model-name-low-confidence"]
        )
    }

    private func makeLegacyCellPhysicalFixture(definition: FixtureDefinition, productDefinitions: [FixtureDefinition], block: FixtureCellBlock) -> FixturePhysicalDefinition {
        let count = Int(block.cellCount)
        let semantic = block.cellLabelPrefix.lowercased()
        let isPhysicalHead = semantic.contains("head") || semantic.contains("pod")
        let emitters = (0..<count).map { index in
            FixturePhysicalEmitter(
                id: "legacy-physical-\(index)",
                name: "\(block.cellLabelPrefix) \(index + 1)",
                x: (Double(index) + 0.5) / Double(count), y: 0.5,
                width: min(0.22, 0.78 / Double(count)), height: isPhysicalHead ? 0.68 : 0.48,
                opticalBehaviors: [.wash]
            )
        }
        let sharedID = productDefinitions.map(\.id).sorted { $0.uuidString < $1.uuidString }.first ?? definition.id
        return FixturePhysicalDefinition(
            id: sharedID,
            manufacturer: definition.manufacturer,
            model: definition.model,
            form: isPhysicalHead ? .multiHeadBar : .linearBar,
            aspectRatio: isPhysicalHead ? max(3.2, Double(count) * 0.72) : max(3, Double(count) * 0.55),
            emitters: emitters,
            componentGroups: [
                .init(id: "legacy-explicit-cells", role: isPhysicalHead ? .primaryOptic : .emitterArray, topology: isPhysicalHead ? .multiHead : .linear, emitterIDs: emitters.map(\.id), provenance: .legacy)
            ],
            opticalBehaviors: [.wash],
            movement: .static,
            source: .legacy,
            sourceMetadata: ["adaptedFrom": "FixtureCellBlock", "cellLabelPrefix": block.cellLabelPrefix]
        )
    }

    private func explicitlyOwnedEmitterElements(in definition: FixtureDefinition) -> Set<String> {
        Set(definition.channels.compactMap { channel in
            guard isPhysicalEmitterAttribute(channel.attribute) else { return nil }
            return channel.elementID
        })
    }

    private func isPhysicalEmitterAttribute(_ attribute: String) -> Bool {
        let value = attribute.lowercased()
        return value == "colorr" || value == "colorg" || value == "colorb"
            || value == "colorw" || value == "colorww" || value == "colorcw"
            || value == "colorwarmwhite" || value == "colorcoolwhite"
            || value == "colora" || value == "coloruv" || value == "colorlime"
            || value == "colorcyan" || value == "colorm" || value == "colory"
    }

    func visualizationDescriptor(for definition: FixtureDefinition) -> FixtureVisualizationDescriptor {
        definition.resolvedVisualization(physical: physicalFixture(for: definition))
    }

    func universe(id: UUID) -> Universe? {
        universes.first { $0.id == id }
    }

    /// Channel footprint for a patched fixture (calculated including multi-cell, else 1).
    func channelCount(for fixture: PatchedFixture) -> UInt16 {
        guard let def = definition(id: fixture.definitionId) else { return 1 }
        return max(def.channelCount, def.calculatedFootprint)
    }

    /// Inclusive DMX span for a fixture within its universe, if patched.
    func dmxSpan(for fixture: PatchedFixture) -> ClosedRange<UInt16>? {
        guard fixture.isPatched else { return nil }
        let count = channelCount(for: fixture)
        guard count >= 1 else { return nil }
        let end = fixture.endAddress(channelCount: count)
        return fixture.address...end
    }

    /// Fixtures currently occupying DMX address space.
    var patchedFixtures: [PatchedFixture] {
        fixtures.filter(\.isPatched)
    }

    /// Fixtures present in the show but without a DMX assignment.
    var unpatchedFixtures: [PatchedFixture] {
        fixtures.filter { !$0.isPatched }
    }

    /// All pairwise patch overlaps in the project.
    func patchConflicts() -> [PatchOverlap] {
        overlappingPatchRanges()
    }

    /// Whether `fixture` can be placed without overlap and within universe capacity.
    /// - Parameter ignoringFixtureID: exclude an existing fixture (for repatch in place).
    func canPlace(fixture: PatchedFixture, ignoringFixtureID: UUID? = nil) -> Bool {
        guard fixture.isPatched else { return false }
        guard let universe = universe(id: fixture.universeId) else { return false }
        let count = channelCount(for: fixture)
        guard count >= 1 else { return false }
        let end = fixture.endAddress(channelCount: count)
        guard end <= universe.channelCount else { return false }

        for other in fixtures where other.id != ignoringFixtureID
            && other.isPatched
            && other.universeId == fixture.universeId
        {
            let otherCount = channelCount(for: other)
            let otherEnd = other.endAddress(channelCount: otherCount)
            if fixture.address <= otherEnd && other.address <= end {
                return false
            }
        }
        return true
    }

    /// First 1-based start address in the universe that fits `channelCount` without overlap.
    /// Uses `Int` math throughout to avoid UInt16 overflow traps on corrupt data (PRE-UI-6).
    func nextFreeAddress(in universeId: UUID, channelCount requested: UInt16) -> UInt16? {
        guard let universe = universe(id: universeId), requested >= 1 else { return nil }
        let capacity = Int(universe.channelCount)
        let need = Int(requested)
        guard need <= capacity else { return nil }

        let occupied: [(start: Int, end: Int)] = fixtures
            .filter { $0.universeId == universeId && $0.isPatched }
            .map { f in
                let c = Int(channelCount(for: f))
                let start = Int(f.address)
                let end = Int(f.endAddress(channelCount: UInt16(clamping: c)))
                return (start, end)
            }
            .sorted { $0.start < $1.start }

        var candidate = 1
        for (start, end) in occupied {
            if candidate + need - 1 < start {
                return UInt16(candidate)
            }
            if end + 1 > candidate {
                candidate = end + 1
            }
        }
        if candidate + need - 1 <= capacity {
            return UInt16(candidate)
        }
        return nil
    }
}
