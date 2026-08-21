import Foundation

/// A programmable target within one physical patched fixture.
/// `elementID == nil` means the complete fixture; cell ids are stable across loads.
public struct FixtureTarget: Codable, Equatable, Sendable, Hashable {
    public var fixtureID: UUID
    public var elementID: String?

    public init(fixtureID: UUID, elementID: String? = nil) {
        self.fixtureID = fixtureID
        self.elementID = elementID
    }

    public static func cell(fixtureID: UUID, index: Int) -> FixtureTarget {
        FixtureTarget(fixtureID: fixtureID, elementID: FixtureElement.cellID(index: index))
    }

    public var cellIndex: Int? {
        guard let elementID else { return nil }
        return FixtureElement.cellIndex(from: elementID)
    }
}

/// Derived visual/programming description for a repeated fixture cell.
/// The first pass derives these from `FixtureCellBlock`; explicit custom geometry can
/// be added later without changing target identity.
public struct FixtureElement: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var index: Int
    public var name: String

    public init(id: String, index: Int, name: String) {
        self.id = id
        self.index = index
        self.name = name
    }

    public static func cellID(index: Int) -> String { "cell-\(index)" }

    public static func cellIndex(from id: String) -> Int? {
        guard id.hasPrefix("cell-") else { return nil }
        return Int(id.dropFirst("cell-".count))
    }
}

public enum FixtureVisualRole: String, Codable, Sendable, Hashable, CaseIterable {
    case pointLight, linearLight, matrixLight, movingLight, atmospheric, strobe, blinder, practical, generic
}

public enum FixtureElementShape: String, Codable, Sendable, Hashable, CaseIterable {
    case circle, rectangle, roundedRectangle
}

public enum FixtureElementLayout: String, Codable, Sendable, Hashable, CaseIterable {
    case row, column, grid, custom
}

public enum FixtureVisualIndicatorKind: String, Codable, Sendable, Hashable, CaseIterable {
    case atmosphereCloud, fan, fluid, genericLevel
}

public enum FixtureVisualProvenance: String, Codable, Sendable, Hashable {
    case manuallyAuthored, imported, inferred
}

public struct FixtureVisualElement: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var shape: FixtureElementShape

    public init(id: String, name: String, x: Double, y: Double, width: Double = 0.12, height: Double = 0.5, shape: FixtureElementShape = .circle) {
        self.id = id; self.name = name; self.x = x; self.y = y
        self.width = width; self.height = height; self.shape = shape
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
    }

    private enum CodingKeys: String, CodingKey { case id, name, x, y, width, height, shape }
}

public struct FixtureVisualIndicator: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var kind: FixtureVisualIndicatorKind
    public var attribute: String
    public var minimum: Double
    public var maximum: Double

    public init(id: String, kind: FixtureVisualIndicatorKind, attribute: String, minimum: Double = 0, maximum: Double = 1) {
        self.id = id; self.kind = kind; self.attribute = attribute
        self.minimum = minimum; self.maximum = maximum
    }
}

public struct FixtureVisualDefinition: Codable, Equatable, Sendable, Hashable {
    public var schemaVersion: Int
    public var role: FixtureVisualRole
    public var bodyAspectRatio: Double
    public var layout: FixtureElementLayout
    public var gridColumns: Int?
    public var elements: [FixtureVisualElement]
    public var indicators: [FixtureVisualIndicator]
    public var provenance: FixtureVisualProvenance
    public var form: FixturePhysicalForm?
    public var topology: FixturePhysicalTopologyKind?
    public var rows: Int?
    public var columns: Int?
    public var opticalBehaviors: Set<FixtureOpticalBehavior>?
    public var movement: FixtureMovementKind?
    public var componentGroups: [FixturePhysicalComponentGroup]?

    public init(schemaVersion: Int = 2, role: FixtureVisualRole, bodyAspectRatio: Double = 1, layout: FixtureElementLayout = .row, gridColumns: Int? = nil, elements: [FixtureVisualElement] = [], indicators: [FixtureVisualIndicator] = [], provenance: FixtureVisualProvenance = .manuallyAuthored, form: FixturePhysicalForm? = nil, topology: FixturePhysicalTopologyKind? = nil, rows: Int? = nil, columns: Int? = nil, opticalBehaviors: Set<FixtureOpticalBehavior>? = nil, movement: FixtureMovementKind? = nil, componentGroups: [FixturePhysicalComponentGroup]? = nil) {
        self.schemaVersion = schemaVersion
        self.role = role; self.bodyAspectRatio = max(0.2, bodyAspectRatio)
        self.layout = layout; self.gridColumns = gridColumns; self.elements = elements
        self.indicators = indicators; self.provenance = provenance
        self.form = form; self.topology = topology; self.rows = rows; self.columns = columns
        self.opticalBehaviors = opticalBehaviors; self.movement = movement; self.componentGroups = componentGroups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        role = (try? c.decodeIfPresent(FixtureVisualRole.self, forKey: .role)) ?? .generic
        bodyAspectRatio = max(0.2, try c.decodeIfPresent(Double.self, forKey: .bodyAspectRatio) ?? 1)
        layout = (try? c.decodeIfPresent(FixtureElementLayout.self, forKey: .layout)) ?? .row
        gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns)
        elements = try c.decodeIfPresent([FixtureVisualElement].self, forKey: .elements) ?? []
        indicators = try c.decodeIfPresent([FixtureVisualIndicator].self, forKey: .indicators) ?? []
        provenance = (try? c.decodeIfPresent(FixtureVisualProvenance.self, forKey: .provenance)) ?? .manuallyAuthored
        form = (try? c.decodeIfPresent(FixturePhysicalForm.self, forKey: .form)) ?? nil
        topology = (try? c.decodeIfPresent(FixturePhysicalTopologyKind.self, forKey: .topology)) ?? nil
        rows = try c.decodeIfPresent(Int.self, forKey: .rows)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns)
        opticalBehaviors = try c.decodeIfPresent(Set<FixtureOpticalBehavior>.self, forKey: .opticalBehaviors)
        movement = (try? c.decodeIfPresent(FixtureMovementKind.self, forKey: .movement)) ?? nil
        componentGroups = try c.decodeIfPresent([FixturePhysicalComponentGroup].self, forKey: .componentGroups)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, role, bodyAspectRatio, layout, gridColumns, elements, indicators, provenance
        case form, topology, rows, columns, opticalBehaviors, movement, componentGroups
    }
}

public extension FixtureDefinition {
    /// Personality-local controllable elements. Physical emitters deliberately do
    /// not participate in programmer target identity.
    var elements: [FixtureElement] {
        if !controlElements.isEmpty {
            return controlElements.enumerated().map { FixtureElement(id: $0.element.id, index: $0.offset, name: $0.element.name) }
        }
        if let block = cellBlock {
            return (0..<Int(block.cellCount)).map { index in
                FixtureElement(
                    id: FixtureElement.cellID(index: index),
                    index: index,
                    name: "\(block.cellLabelPrefix) \(index + 1)"
                )
            }
        }
        var seen: Set<String> = []
        return channels.compactMap(\.elementID).filter { seen.insert($0).inserted }.enumerated().map {
            FixtureElement(id: $0.element, index: $0.offset, name: "Element \($0.offset + 1)")
        }
    }


    var resolvedVisual: FixtureVisualDefinition {
        if portablePhysicalDefinition == nil, let visual { return visual }
        let descriptor = resolvedVisualization()
        return FixtureVisualDefinition(
            role: descriptor.legacyRole,
            bodyAspectRatio: descriptor.aspectRatio,
            layout: descriptor.legacyLayout,
            gridColumns: descriptor.componentGroups.first?.columns,
            elements: descriptor.emitters.map {
                FixtureVisualElement(id: $0.id, name: $0.name, x: $0.x, y: $0.y, width: $0.width, height: $0.height, shape: $0.shape)
            },
            indicators: descriptor.indicators,
            provenance: descriptor.confidence == .explicit ? .manuallyAuthored : .inferred
        )
    }

    func resolvedVisualization(physical: FixturePhysicalDefinition? = nil) -> FixtureVisualizationDescriptor {
        FixtureVisualizationResolver.resolveCached(
            definition: self,
            physical: physical ?? portablePhysicalDefinition
        )
    }
}

public extension FixtureVisualizationDescriptor {
    var legacyRole: FixtureVisualRole {
        switch form {
        case .par, .fresnel, .profile: return .pointLight
        case .linearBar, .strip, .multiHeadBar: return .linearLight
        case .panel: return .matrixLight
        case .movingHead, .scanner: return .movingLight
        case .atmospheric: return .atmospheric
        case .strobe: return .strobe
        case .blinder: return .blinder
        case .practical, .effect: return .practical
        default: return .generic
        }
    }

    var legacyLayout: FixtureElementLayout {
        guard let topology = componentGroups.first?.topology else { return .custom }
        switch topology {
        case .linear: return .row
        case .grid: return .grid
        default: return .custom
        }
    }
}

public enum FixtureVisualInference {
    public static func infer(_ definition: FixtureDefinition) -> FixtureVisualDefinition {
        let ownedIDs = Array(Set(definition.channels.compactMap(\.elementID))).sorted()
        let derived = definition.cellBlock != nil ? definition.elements.map(\.id) : ownedIDs
        let attrs = definition.channels.map(\.attribute) + (definition.cellBlock?.channels.map(\.attribute) ?? [])
        let lower = Set(attrs.map { $0.lowercased() })
        let fogAttribute = attrs.first { ["fogoutput", "fog", "haze", "hazeoutput"].contains($0.lowercased()) }
        let fanAttribute = attrs.first { ["fanspeed", "fan_speed", "fan"].contains($0.lowercased()) }
        let emits = lower.contains { $0.hasPrefix("color") || ["intensity", "dimmer"].contains($0) }
        let role: FixtureVisualRole
        if fogAttribute != nil { role = .atmospheric }
        else if derived.count > 1 { role = .linearLight }
        else if definition.hasPanTilt { role = .movingLight }
        else if emits { role = .pointLight }
        else { role = .generic }

        let layout: FixtureElementLayout = definition.cellBlock != nil && derived.count <= 4 ? .column : .row
        let elements = makeElements(ids: derived, layout: layout)
        var indicators: [FixtureVisualIndicator] = []
        if let fogAttribute { indicators.append(.init(id: "atmosphere", kind: .atmosphereCloud, attribute: fogAttribute)) }
        if let fanAttribute { indicators.append(.init(id: "fan", kind: .fan, attribute: fanAttribute)) }
        return FixtureVisualDefinition(
            role: role,
            bodyAspectRatio: role == .linearLight
                ? (layout == .column ? 0.55 : max(2, Double(max(derived.count, 1)) * 0.8))
                : 1,
            layout: layout,
            elements: elements,
            indicators: indicators,
            provenance: .inferred
        )
    }

    public static func makeElements(ids: [String], layout: FixtureElementLayout) -> [FixtureVisualElement] {
        guard !ids.isEmpty else { return [] }
        return ids.enumerated().map { index, id in
            let t = (Double(index) + 0.5) / Double(ids.count)
            return FixtureVisualElement(
                id: id,
                name: "Element \(index + 1)",
                x: layout == .column ? 0.5 : t,
                y: layout == .column ? t : 0.5,
                width: layout == .column ? 0.58 : min(0.8, 0.78 / Double(ids.count)),
                height: layout == .column ? min(0.8, 0.78 / Double(ids.count)) : 0.58,
                shape: .circle
            )
        }
    }
}
