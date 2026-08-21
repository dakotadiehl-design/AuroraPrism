import Foundation

// MARK: - Shared physical truth

public enum FixturePhysicalForm: String, Codable, Sendable, Hashable, CaseIterable {
    case generic, par, fresnel, profile, linearBar, strip, panel, movingHead, scanner
    case multiHeadBar, blinder, strobe, laser, atmospheric, effect, projector, practical
}

public enum FixturePhysicalTopologyKind: String, Codable, Sendable, Hashable, CaseIterable {
    case unknown, single, linear, grid, variableRows, ring, rings, array, cluster, multiHead, noBeam, compositional, custom
}

public enum FixtureOpticalBehavior: String, Codable, Sendable, Hashable, CaseIterable {
    case wash, spot, beam, profile, pixel, blinder, strobe, laser, atmospheric, effect, decorative, none
}

public enum FixtureMovementKind: String, Codable, Sendable, Hashable, CaseIterable {
    case `static`, panTilt, scannerMirror, multiHead, unknown
}

public enum FixturePhysicalComponentRole: String, Codable, Sendable, Hashable, CaseIterable {
    case chassis, emitterArray, primaryOptic, pixelRing, movingHead, strobeArray, atmosphericOutlet, laserAperture, other
}

public struct FixturePhysicalEmitter: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var shape: FixtureElementShape
    public var opticalBehaviors: Set<FixtureOpticalBehavior>

    public init(id: String, name: String, x: Double, y: Double, width: Double = 0.12, height: Double = 0.5, shape: FixtureElementShape = .circle, opticalBehaviors: Set<FixtureOpticalBehavior> = [.wash]) {
        self.id = id; self.name = name; self.x = x; self.y = y
        self.width = width; self.height = height; self.shape = shape
        self.opticalBehaviors = opticalBehaviors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.12
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0.5
        shape = (try? c.decodeIfPresent(FixtureElementShape.self, forKey: .shape)) ?? .circle
        opticalBehaviors = (try? c.decodeIfPresent(Set<FixtureOpticalBehavior>.self, forKey: .opticalBehaviors)) ?? []
    }
    private enum CodingKeys: String, CodingKey { case id, name, x, y, width, height, shape, opticalBehaviors }
}

public struct FixturePhysicalComponentGroup: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var role: FixturePhysicalComponentRole
    public var topology: FixturePhysicalTopologyKind
    public var rows: Int?
    public var columns: Int?
    public var emitterIDs: [String]
    public var movement: FixtureMovementKind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var provenance: FixtureMetadataSource

    public init(id: String, role: FixturePhysicalComponentRole, topology: FixturePhysicalTopologyKind, rows: Int? = nil, columns: Int? = nil, emitterIDs: [String] = [], movement: FixtureMovementKind = .static, x: Double = 0.5, y: Double = 0.5, width: Double = 1, height: Double = 1, provenance: FixtureMetadataSource = .explicit) {
        self.id = id; self.role = role; self.topology = topology
        self.rows = rows; self.columns = columns; self.emitterIDs = emitterIDs; self.movement = movement
        self.x = x; self.y = y; self.width = width; self.height = height; self.provenance = provenance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        role = try c.decode(FixturePhysicalComponentRole.self, forKey: .role)
        topology = (try? c.decodeIfPresent(FixturePhysicalTopologyKind.self, forKey: .topology)) ?? .unknown
        rows = try c.decodeIfPresent(Int.self, forKey: .rows)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns)
        emitterIDs = try c.decodeIfPresent([String].self, forKey: .emitterIDs) ?? []
        movement = try c.decodeIfPresent(FixtureMovementKind.self, forKey: .movement) ?? .static
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 1
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 1
        provenance = try c.decodeIfPresent(FixtureMetadataSource.self, forKey: .provenance) ?? .legacy
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, topology, rows, columns, emitterIDs, movement, x, y, width, height, provenance
    }
}

public enum FixtureMetadataSource: String, Codable, Sendable, Hashable {
    case explicit, imported, inferred, legacy, fallback
}

/// One physical product shared by every DMX personality for that product.
public struct FixturePhysicalDefinition: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var schemaVersion: Int
    public var id: UUID
    public var manufacturer: String
    public var model: String
    public var form: FixturePhysicalForm
    public var width: Double?
    public var height: Double?
    public var depth: Double?
    public var aspectRatio: Double?
    public var emitters: [FixturePhysicalEmitter]
    public var componentGroups: [FixturePhysicalComponentGroup]
    public var opticalBehaviors: Set<FixtureOpticalBehavior>
    public var movement: FixtureMovementKind
    public var beamShape: Int?
    public var beamType: Int?
    public var beamSpreadDegrees: Double?
    public var source: FixtureMetadataSource
    public var sourceMetadata: [String: String]

    public init(schemaVersion: Int = 1, id: UUID = UUID(), manufacturer: String, model: String, form: FixturePhysicalForm = .generic, width: Double? = nil, height: Double? = nil, depth: Double? = nil, aspectRatio: Double? = nil, emitters: [FixturePhysicalEmitter] = [], componentGroups: [FixturePhysicalComponentGroup] = [], opticalBehaviors: Set<FixtureOpticalBehavior> = [], movement: FixtureMovementKind = .unknown, beamShape: Int? = nil, beamType: Int? = nil, beamSpreadDegrees: Double? = nil, source: FixtureMetadataSource = .explicit, sourceMetadata: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.id = id; self.manufacturer = manufacturer; self.model = model; self.form = form
        self.width = width; self.height = height; self.depth = depth; self.aspectRatio = aspectRatio
        self.emitters = emitters; self.componentGroups = componentGroups
        self.opticalBehaviors = opticalBehaviors; self.movement = movement
        self.beamShape = beamShape; self.beamType = beamType; self.beamSpreadDegrees = beamSpreadDegrees
        self.source = source; self.sourceMetadata = sourceMetadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try c.decode(UUID.self, forKey: .id)
        manufacturer = try c.decode(String.self, forKey: .manufacturer)
        model = try c.decode(String.self, forKey: .model)
        form = (try? c.decodeIfPresent(FixturePhysicalForm.self, forKey: .form)) ?? .generic
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        depth = try c.decodeIfPresent(Double.self, forKey: .depth)
        aspectRatio = try c.decodeIfPresent(Double.self, forKey: .aspectRatio)
        emitters = try c.decodeIfPresent([FixturePhysicalEmitter].self, forKey: .emitters) ?? []
        componentGroups = try c.decodeIfPresent([FixturePhysicalComponentGroup].self, forKey: .componentGroups) ?? []
        opticalBehaviors = try c.decodeIfPresent(Set<FixtureOpticalBehavior>.self, forKey: .opticalBehaviors) ?? []
        movement = (try? c.decodeIfPresent(FixtureMovementKind.self, forKey: .movement)) ?? .unknown
        beamShape = try c.decodeIfPresent(Int.self, forKey: .beamShape)
        beamType = try c.decodeIfPresent(Int.self, forKey: .beamType)
        beamSpreadDegrees = try c.decodeIfPresent(Double.self, forKey: .beamSpreadDegrees)
        source = try c.decodeIfPresent(FixtureMetadataSource.self, forKey: .source) ?? .legacy
        sourceMetadata = try c.decodeIfPresent([String: String].self, forKey: .sourceMetadata) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, manufacturer, model, form, width, height, depth, aspectRatio
        case emitters, componentGroups, opticalBehaviors, movement, beamShape, beamType, beamSpreadDegrees, source, sourceMetadata
    }
}

// MARK: - Personality-specific control graph

public struct FixtureControlElement: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum FixtureEmitterCombinationRule: String, Codable, Sendable, Hashable, CaseIterable {
    case direct, additive, maximum, average, master, component, customFallback
}

/// Explicit many-to-many relationship. Neither side's identity is derived from the other.
public struct FixtureEmitterMapping: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var controlElementIDs: Set<String>
    public var physicalEmitterIDs: Set<String>
    public var combination: FixtureEmitterCombinationRule

    public init(id: String, controlElementIDs: Set<String>, physicalEmitterIDs: Set<String>, combination: FixtureEmitterCombinationRule = .direct) {
        self.id = id; self.controlElementIDs = controlElementIDs
        self.physicalEmitterIDs = physicalEmitterIDs; self.combination = combination
    }
}

// MARK: - Resolution

public enum FixtureVisualizationConfidence: String, Codable, Sendable, Hashable, CaseIterable {
    case explicit, high, medium, low, fallback
}

public struct FixtureVisualizationDiagnostic: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var message: String
    public init(id: String, message: String) { self.id = id; self.message = message }
}

public struct FixtureVisualizationDescriptor: Codable, Equatable, Sendable, Hashable {
    public var physicalFixtureID: UUID
    public var form: FixturePhysicalForm
    public var aspectRatio: Double
    public var emitters: [FixturePhysicalEmitter]
    public var componentGroups: [FixturePhysicalComponentGroup]
    public var opticalBehaviors: Set<FixtureOpticalBehavior>
    public var movement: FixtureMovementKind
    public var indicators: [FixtureVisualIndicator]
    public var confidence: FixtureVisualizationConfidence
    public var evidence: [FixtureVisualizationDiagnostic]
    public var warnings: [FixtureVisualizationDiagnostic]

    public init(
        physicalFixtureID: UUID,
        form: FixturePhysicalForm,
        aspectRatio: Double,
        emitters: [FixturePhysicalEmitter],
        componentGroups: [FixturePhysicalComponentGroup],
        opticalBehaviors: Set<FixtureOpticalBehavior>,
        movement: FixtureMovementKind,
        indicators: [FixtureVisualIndicator],
        confidence: FixtureVisualizationConfidence,
        evidence: [FixtureVisualizationDiagnostic],
        warnings: [FixtureVisualizationDiagnostic]
    ) {
        self.physicalFixtureID = physicalFixtureID
        self.form = form
        self.aspectRatio = aspectRatio
        self.emitters = emitters
        self.componentGroups = componentGroups
        self.opticalBehaviors = opticalBehaviors
        self.movement = movement
        self.indicators = indicators
        self.confidence = confidence
        self.evidence = evidence
        self.warnings = warnings
    }

    public var physicalTopologySignature: String {
        let emitterPart = emitters.sorted { $0.id < $1.id }.map { "\($0.id):\($0.x):\($0.y):\($0.width):\($0.height):\($0.shape.rawValue)" }.joined(separator: "|")
        let groupPart = componentGroups.sorted { $0.id < $1.id }.map {
            "\($0.id):\($0.role.rawValue):\($0.topology.rawValue):\($0.rows ?? -1):\($0.columns ?? -1):\($0.x):\($0.y):\($0.width):\($0.height):\($0.movement.rawValue):\($0.emitterIDs.joined(separator: ",")):\($0.provenance.rawValue)"
        }.joined(separator: "|")
        return "\(form.rawValue)#\(aspectRatio)#\(emitterPart)#\(groupPart)"
    }
}

public enum FixtureVisualizationResolver {
    public static var cacheResolutionCount: Int { FixtureVisualizationDescriptorCache.shared.resolutionCount }
    public static func resetCacheForTesting() { FixtureVisualizationDescriptorCache.shared.reset() }
    public static func resolveCached(definition: FixtureDefinition, physical: FixturePhysicalDefinition?) -> FixtureVisualizationDescriptor {
        let fingerprint = visualizationFingerprint(definition: definition, physical: physical)
        return FixtureVisualizationDescriptorCache.shared.value(for: fingerprint) {
            resolve(definition: definition, physical: physical)
        }
    }

    public static func resolve(definition: FixtureDefinition, physical: FixturePhysicalDefinition?) -> FixtureVisualizationDescriptor {
        if let override = definition.visual, override.provenance == .manuallyAuthored {
            let emitters = override.elements.enumerated().map { index, element in
                FixturePhysicalEmitter(
                    id: "override-physical-\(index)",
                    name: element.name,
                    x: element.x,
                    y: element.y,
                    width: element.width,
                    height: element.height,
                    shape: element.shape,
                    opticalBehaviors: inferredOptics(definition)
                )
            }
            return FixtureVisualizationDescriptor(
                physicalFixtureID: physical?.id ?? definition.physicalFixtureID ?? definition.id,
                form: override.form ?? formForLegacyVisual(override),
                aspectRatio: override.bodyAspectRatio,
                emitters: emitters,
                componentGroups: override.componentGroups ?? (emitters.isEmpty ? [] : [.init(id: "override", role: .emitterArray, topology: override.topology ?? (override.layout == .grid ? .grid : .linear), rows: override.rows, columns: override.columns, emitterIDs: emitters.map(\.id))]),
                opticalBehaviors: override.opticalBehaviors ?? inferredOptics(definition),
                movement: override.movement ?? (definition.hasPanTilt ? .panTilt : .static),
                indicators: override.indicators,
                confidence: .explicit,
                evidence: [.init(id: "visualization-override", message: "A user-authored visualization override is active.")],
                warnings: []
            )
        }
        if let physical {
            let sanitizedEmitters = physical.emitters.map(sanitizeEmitter)
            let layoutClass = physical.sourceMetadata["beamLayoutClass"]
            let resolvedForm = enrichedForm(physical: physical, definition: definition, layoutClass: layoutClass)
            var sanitizedGroups = physical.componentGroups.map(sanitizeGroup)
            if sanitizedGroups.isEmpty, let topology = topologyForImportedClass(layoutClass) {
                sanitizedGroups = [.init(id: "imported-layout", role: topology == .noBeam ? .atmosphericOutlet : .emitterArray, topology: topology, emitterIDs: sanitizedEmitters.map(\.id), provenance: .imported)]
            }
            if resolvedForm == .multiHeadBar {
                sanitizedGroups = sanitizedGroups.map { group in
                    var copy = group; copy.role = .movingHead; copy.topology = .multiHead; copy.movement = .multiHead; return copy
                }
            } else if resolvedForm == .movingHead {
                sanitizedGroups = sanitizedGroups.map { group in
                    var copy = group; copy.movement = .panTilt; return copy
                }
            } else if resolvedForm == .scanner {
                sanitizedGroups = sanitizedGroups.map { group in
                    var copy = group; copy.movement = .scannerMirror; return copy
                }
            }
            var evidence = [FixtureVisualizationDiagnostic(id: "shared-physical", message: "Resolved from shared physical fixture metadata.")]
            if physical.source == .imported {
                evidence.append(.init(id: "imported-physical", message: "Physical metadata was preserved by an importer."))
            }
            let nameHeuristic = physical.sourceMetadata["formInference"] == "model-name-low-confidence"
            if nameHeuristic {
                evidence.append(.init(id: "name-heuristic", message: "Form used a low-confidence fixture/model name heuristic."))
            }
            for group in sanitizedGroups where group.topology != .unknown {
                evidence.append(.init(
                    id: "physical-topology-\(group.id)",
                    message: "Physical component “\(group.id)” uses \(group.topology.rawValue) topology with \(group.emitterIDs.count) component(s)."
                ))
            }
            return FixtureVisualizationDescriptor(
                physicalFixtureID: physical.id,
                form: resolvedForm,
                aspectRatio: sanitizedAspect(physical.aspectRatio.flatMap { $0 == 1 && resolvedForm != physical.form ? nil : $0 } ?? inferredAspect(form: resolvedForm, emitters: sanitizedEmitters)),
                emitters: sanitizedEmitters,
                componentGroups: sanitizedGroups,
                opticalBehaviors: physical.opticalBehaviors,
                movement: physical.movement == .unknown ? (definition.hasPanTilt ? .panTilt : .static) : physical.movement,
                indicators: inferredIndicators(definition),
                confidence: physical.source == .explicit ? .explicit : (nameHeuristic ? .low : .high),
                evidence: evidence,
                warnings: physicalWarnings(physical)
            )
        }

        // Backward-compatible fallback. Control ownership is supporting evidence only;
        // it never supplies physical emitter identities.
        let legacy = definition.visual
        let form = legacy.map(formForLegacyVisual) ?? inferredForm(definition)
        let usedNameHeuristic = legacy == nil && nameHeuristicForm(definition) != nil
        let emitters = legacy?.elements.enumerated().map { index, element in
            FixturePhysicalEmitter(id: "legacy-physical-\(index)", name: element.name, x: element.x, y: element.y, width: element.width, height: element.height, shape: element.shape)
        } ?? []
        return FixtureVisualizationDescriptor(
            physicalFixtureID: definition.physicalFixtureID ?? definition.id,
            form: form,
            aspectRatio: max(0.2, legacy?.bodyAspectRatio ?? inferredAspect(form: form, emitters: emitters)),
            emitters: emitters,
            componentGroups: emitters.isEmpty ? [] : [.init(id: "legacy-emitters", role: .emitterArray, topology: legacy?.layout == .grid ? .grid : .linear, emitterIDs: emitters.map(\.id))],
            opticalBehaviors: inferredOptics(definition),
            movement: definition.hasPanTilt ? .panTilt : .static,
            indicators: legacy?.indicators ?? inferredIndicators(definition),
            confidence: legacy == nil ? .low : .medium,
            evidence: [.init(id: usedNameHeuristic ? "name-heuristic" : (legacy == nil ? "semantic-fallback" : "legacy-visual"), message: usedNameHeuristic ? "Form used a low-confidence fixture/model name heuristic." : (legacy == nil ? "Resolved from fixture semantics and clean fallback rules." : "Adapted legacy visualization metadata."))],
            warnings: physical == nil ? [.init(id: "missing-physical", message: "No shared physical fixture metadata is available.")] : []
        )
    }

    private static func formForLegacyVisual(_ visual: FixtureVisualDefinition) -> FixturePhysicalForm {
        switch visual.role {
        case .pointLight: return .par
        case .linearLight: return .linearBar
        case .matrixLight: return .panel
        case .movingLight: return .movingHead
        case .atmospheric: return .atmospheric
        case .strobe: return .strobe
        case .blinder: return .blinder
        case .practical: return .practical
        case .generic: return .generic
        }
    }

    private static func inferredForm(_ definition: FixtureDefinition) -> FixturePhysicalForm {
        let attrs = Set((definition.channels + (definition.cellBlock?.channels ?? [])).map { $0.attribute.lowercased() })
        if !attrs.isDisjoint(with: ["fog", "fogoutput", "haze", "hazeoutput"]) { return .atmospheric }
        if definition.hasPanTilt { return .movingHead }
        if let nameForm = nameHeuristicForm(definition) { return nameForm }
        return .generic
    }

    private static func nameHeuristicForm(_ definition: FixtureDefinition) -> FixturePhysicalForm? {
        let name = "\(definition.model) \(definition.category)".lowercased()
        if name.contains("bar") || name.contains("batten") || name.contains("strip") || name.contains("band") { return .linearBar }
        if name.contains("blinder") { return .blinder }
        if name.contains("strobe") { return .strobe }
        if name.contains("laser") { return .laser }
        if name.contains("par") { return .par }
        return nil
    }

    private static func inferredOptics(_ definition: FixtureDefinition) -> Set<FixtureOpticalBehavior> {
        let attrs = Set((definition.channels + (definition.cellBlock?.channels ?? [])).map { $0.attribute.lowercased() })
        if !attrs.isDisjoint(with: ["fog", "fogoutput", "haze", "hazeoutput"]) { return [.atmospheric] }
        if attrs.contains(where: { $0.contains("strobe") || $0.contains("shutter") }) { return [.strobe] }
        if attrs.contains(where: { $0.hasPrefix("color") }) { return [.wash] }
        return []
    }

    private static func inferredIndicators(_ definition: FixtureDefinition) -> [FixtureVisualIndicator] {
        let attrs = (definition.channels + (definition.cellBlock?.channels ?? [])).map(\.attribute)
        var result: [FixtureVisualIndicator] = []
        if let fog = attrs.first(where: { ["fog", "fogoutput", "haze", "hazeoutput"].contains($0.lowercased()) }) {
            result.append(.init(id: "atmosphere", kind: .atmosphereCloud, attribute: fog))
        }
        if let fan = attrs.first(where: { ["fan", "fanspeed", "fan_speed"].contains($0.lowercased()) }) {
            result.append(.init(id: "fan", kind: .fan, attribute: fan))
        }
        return result
    }

    private static func inferredAspect(form: FixturePhysicalForm, emitters: [FixturePhysicalEmitter]) -> Double {
        switch form {
        case .linearBar, .strip, .multiHeadBar: return max(2, Double(max(emitters.count, 1)) * 0.8)
        case .panel, .blinder: return 1.4
        default: return 1
        }
    }

    private static func physicalWarnings(_ physical: FixturePhysicalDefinition) -> [FixtureVisualizationDiagnostic] {
        let ids = physical.emitters.map(\.id)
        var warnings: [FixtureVisualizationDiagnostic] = []
        if Set(ids).count != ids.count { warnings.append(.init(id: "duplicate-emitter", message: "Physical metadata contains duplicate emitter identities.")) }
        let known = Set(ids)
        if physical.componentGroups.flatMap(\.emitterIDs).contains(where: { !known.contains($0) }) {
            warnings.append(.init(id: "unknown-group-emitter", message: "A physical component group references an unknown emitter."))
        }
        if let layoutClass = physical.sourceMetadata["beamLayoutClass"],
           ["LXStripBeamLayout", "LXRowsBeamLayout", "LXRingsBeamLayout", "LXArrayBeamLayout", "LXGridBeamLayout"].contains(layoutClass),
           physical.emitters.isEmpty {
            warnings.append(.init(id: "missing-layout-dimensions", message: "Imported \(layoutClass) was preserved, but its emitter dimensions/count were unavailable; Prism is showing a topology hint without inventing a count."))
        }
        if physical.emitters.contains(where: { !$0.x.isFinite || !$0.y.isFinite || !$0.width.isFinite || !$0.height.isFinite || !(0...1).contains($0.x) || !(0...1).contains($0.y) || $0.width <= 0 || $0.height <= 0 }) {
            warnings.append(.init(id: "malformed-geometry", message: "Malformed physical geometry was clamped to safe normalized bounds."))
        }
        if let beamShape = physical.beamShape, !(0...3).contains(beamShape) {
            warnings.append(.init(id: "unknown-beam-shape", message: "Unknown imported beamShape value \(beamShape) was retained."))
        }
        return warnings
    }

    private static func sanitizeEmitter(_ emitter: FixturePhysicalEmitter) -> FixturePhysicalEmitter {
        var result = emitter
        result.x = emitter.x.isFinite ? min(1, max(0, emitter.x)) : 0.5
        result.y = emitter.y.isFinite ? min(1, max(0, emitter.y)) : 0.5
        result.width = emitter.width.isFinite ? min(1, max(0.01, emitter.width)) : 0.1
        result.height = emitter.height.isFinite ? min(1, max(0.01, emitter.height)) : 0.1
        return result
    }

    private static func sanitizeGroup(_ group: FixturePhysicalComponentGroup) -> FixturePhysicalComponentGroup {
        var result = group
        result.x = group.x.isFinite ? min(1, max(0, group.x)) : 0.5
        result.y = group.y.isFinite ? min(1, max(0, group.y)) : 0.5
        result.width = group.width.isFinite ? min(1, max(0.01, group.width)) : 1
        result.height = group.height.isFinite ? min(1, max(0.01, group.height)) : 1
        return result
    }

    private static func sanitizedAspect(_ aspect: Double) -> Double {
        aspect.isFinite ? min(20, max(0.2, aspect)) : 1
    }

    private static func topologyForImportedClass(_ layoutClass: String?) -> FixturePhysicalTopologyKind? {
        switch layoutClass {
        case "LXNoBeamLayout": return .noBeam
        case "LXSingleBeamLayout": return .single
        case "LXStripBeamLayout": return .linear
        case "LXRowsBeamLayout": return .variableRows
        case "LXGridBeamLayout": return .grid
        case "LXRingsBeamLayout": return .rings
        case "LXArrayBeamLayout": return .array
        case "LXHexagonsBeamLayout": return .cluster
        default: return nil
        }
    }

    private static func enrichedForm(physical: FixturePhysicalDefinition, definition: FixtureDefinition, layoutClass: String?) -> FixturePhysicalForm {
        // Early Pass-One imports represented every multi-beam fixture as a linear bar.
        // An undefined imported layout plus real pan/tilt semantics and several preserved
        // physical emitters is the narrow compatibility case that identifies a head bar.
        if physical.source == .imported,
           physical.form == .linearBar,
           (layoutClass == nil || layoutClass == "LXUndefinedBeamLayout"),
           definition.hasPanTilt,
           physical.emitters.count > 1 {
            return .multiHeadBar
        }
        guard physical.form == .generic || physical.sourceMetadata["formInference"] == "layout-default" else { return physical.form }
        let name = "\(physical.model) \(definition.category)".lowercased()
        switch layoutClass {
        case "LXNoBeamLayout": return .atmospheric
        case "LXStripBeamLayout": return .linearBar
        case "LXRowsBeamLayout", "LXGridBeamLayout":
            if name.contains("strobe") || name.contains("jolt") { return .strobe }
            if name.contains("blinder") { return .blinder }
            return .panel
        case "LXRingsBeamLayout": return definition.hasPanTilt ? .movingHead : .par
        case "LXArrayBeamLayout": return definition.hasPanTilt ? .multiHeadBar : .panel
        case "LXSingleBeamLayout":
            if name.contains("scan") { return .scanner }
            return definition.hasPanTilt ? .movingHead : .par
        default: return nameHeuristicForm(definition) ?? .generic
        }
    }

    /// Process-local cache identity derived only from visualization-relevant content.
    /// Fixture/definition UUIDs intentionally do not participate.
    public static func visualizationFingerprint(definition: FixtureDefinition, physical: FixturePhysicalDefinition?) -> String {
        var hasher = Hasher()
        hasher.combine(definition.manufacturer.lowercased())
        hasher.combine(definition.model.lowercased())
        hasher.combine(definition.category.lowercased())
        hasher.combine(definition.hasPanTilt)
        for channel in definition.channels.sorted(by: { $0.offset < $1.offset }) {
            hasher.combine(channel.attribute)
            hasher.combine(channel.elementID)
        }
        hasher.combine(definition.visual)
        if let physical {
            hasher.combine(physical.form)
            hasher.combine(physical.width)
            hasher.combine(physical.height)
            hasher.combine(physical.depth)
            hasher.combine(physical.aspectRatio)
            hasher.combine(physical.emitters)
            hasher.combine(physical.componentGroups)
            hasher.combine(physical.opticalBehaviors)
            hasher.combine(physical.movement)
            hasher.combine(physical.beamShape)
            hasher.combine(physical.beamType)
            hasher.combine(physical.beamSpreadDegrees)
            hasher.combine(physical.source)
            for key in physical.sourceMetadata.keys.sorted() {
                hasher.combine(key)
                hasher.combine(physical.sourceMetadata[key])
            }
        }
        return String(hasher.finalize(), radix: 16)
    }
}

private final class FixtureVisualizationDescriptorCache: @unchecked Sendable {
    static let shared = FixtureVisualizationDescriptorCache()
    private let lock = NSLock()
    private var values: [String: FixtureVisualizationDescriptor] = [:]
    private var misses = 0
    var resolutionCount: Int { lock.lock(); defer { lock.unlock() }; return misses }

    func value(for key: String, make: () -> FixtureVisualizationDescriptor) -> FixtureVisualizationDescriptor {
        lock.lock()
        if let value = values[key] {
            lock.unlock()
            return value
        }
        lock.unlock()
        let value = make()
        lock.lock()
        misses += 1
        if values.count > 512 { values.removeAll(keepingCapacity: true) }
        values[key] = value
        lock.unlock()
        return value
    }

    func reset() {
        lock.lock(); values.removeAll(); misses = 0; lock.unlock()
    }
}
