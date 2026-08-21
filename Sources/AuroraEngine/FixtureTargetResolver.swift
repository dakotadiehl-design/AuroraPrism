import AuroraModel
import Foundation

/// Translates UI-level attributes into the concrete keys already understood by the
/// compiler (`colorR@0`, `intensity@3`, ...).
public enum FixtureTargetResolver {
    public static func concreteAttribute(
        _ attribute: String,
        target: FixtureTarget,
        project: ShowProject
    ) -> String? {
        guard target.elementID != nil else { return attribute }
        guard let fixture = project.fixtures.first(where: { $0.id == target.fixtureID }),
              let definition = project.definition(id: fixture.definitionId)
        else { return nil }

        let base = attribute.split(separator: "@").first.map(String.init) ?? attribute
        if let block = definition.cellBlock,
           let cellIndex = target.cellIndex,
           cellIndex >= 0, cellIndex < Int(block.cellCount) {
            let cellAttributes = Set(block.channels.map(\.attribute))
            if ColorAuthoringAttribute.isAuthoring(base) || cellAttributes.contains(base) {
                return "\(base)@\(cellIndex)"
            }
            return base
        }
        guard let elementID = target.elementID else { return base }
        if ColorAuthoringAttribute.isAuthoring(base) {
            return "\(base)@\(elementID)"
        }
        let owned = definition.channels.contains { $0.elementID == elementID && $0.attribute == base }
        let shared = definition.channels.contains { $0.elementID == nil && $0.attribute == base }
        if owned { return "\(base)@\(elementID)" }
        return shared ? base : nil
    }

    public static func batch(
        targets: [FixtureTarget],
        attributes: [String: Double],
        project: ShowProject
    ) -> [UUID: [String: Double]] {
        var result: [UUID: [String: Double]] = [:]
        for target in targets {
            if target.elementID == nil,
               let fixture = project.fixtures.first(where: { $0.id == target.fixtureID }),
               let definition = project.definition(id: fixture.definitionId),
                !definition.elements.isEmpty {
                for element in definition.elements {
                    append(
                        attributes,
                        target: FixtureTarget(fixtureID: target.fixtureID, elementID: element.id),
                        project: project,
                        to: &result
                    )
                }
            } else {
                append(attributes, target: target, project: project, to: &result)
            }
        }
        return result
    }

    private static func append(
        _ attributes: [String: Double],
        target: FixtureTarget,
        project: ShowProject,
        to result: inout [UUID: [String: Double]]
    ) {
        for (attribute, value) in attributes {
            guard let concrete = concreteAttribute(attribute, target: target, project: project) else { continue }
            result[target.fixtureID, default: [:]][concrete] = value
        }
    }
}
