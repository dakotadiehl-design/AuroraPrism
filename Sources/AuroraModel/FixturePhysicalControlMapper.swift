import Foundation

public enum FixturePhysicalControlDisposition: Equatable, Sendable {
    case controls(Set<String>)
    case wholeFixture
    case inspectionOnly
}

public struct FixturePhysicalControlResolution: Equatable, Sendable {
    public var disposition: FixturePhysicalControlDisposition
    public var affectedPhysicalEmitterIDs: Set<String>
    public var independentlyControllable: Bool

    public init(disposition: FixturePhysicalControlDisposition, affectedPhysicalEmitterIDs: Set<String>, independentlyControllable: Bool) {
        self.disposition = disposition
        self.affectedPhysicalEmitterIDs = affectedPhysicalEmitterIDs
        self.independentlyControllable = independentlyControllable
    }
}

/// Maps physical interaction to personality-specific programmer ownership. It is
/// intentionally separate from glyph geometry and never manufactures DMX controls.
public enum FixturePhysicalControlMapper {
    public static func resolve(
        physicalEmitterID: String,
        descriptor: FixtureVisualizationDescriptor,
        definition: FixtureDefinition
    ) -> FixturePhysicalControlResolution {
        let matching = definition.emitterMappings.filter { $0.physicalEmitterIDs.contains(physicalEmitterID) }
        if !matching.isEmpty {
            let controls = Set(matching.flatMap(\.controlElementIDs))
            let affected = Set(definition.emitterMappings.filter { !$0.controlElementIDs.isDisjoint(with: controls) }.flatMap(\.physicalEmitterIDs))
            return .init(disposition: .controls(controls), affectedPhysicalEmitterIDs: affected, independentlyControllable: affected == [physicalEmitterID])
        }

        // FixtureCellBlock is an explicit Prism ownership model. Positional adaptation
        // is safe only when its declared element count equals the physical count.
        let elements = definition.elements
        if elements.count == descriptor.emitters.count,
           let index = descriptor.emitters.firstIndex(where: { $0.id == physicalEmitterID }) {
            return .init(disposition: .controls([elements[index].id]), affectedPhysicalEmitterIDs: [physicalEmitterID], independentlyControllable: true)
        }

        if !definition.channels.isEmpty || definition.cellBlock != nil {
            return .init(disposition: .wholeFixture, affectedPhysicalEmitterIDs: Set(descriptor.emitters.map(\.id)), independentlyControllable: false)
        }
        return .init(disposition: .inspectionOnly, affectedPhysicalEmitterIDs: [physicalEmitterID], independentlyControllable: false)
    }
}
