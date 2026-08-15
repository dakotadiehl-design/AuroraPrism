import Foundation

// MARK: - C4.3 single-render eligibility (pure, testable)

/// Pure helpers for the Stage Edit transform rendering contract:
/// an actively transformed element is rendered exactly once (transient path),
/// never simultaneously in the committed and transient layers.
public enum StageEditRenderEligibility: Sendable {
    /// Whether `elementID` should appear in the committed Stage object/fixture layer.
    public static func shouldRenderInCommittedLayer(
        elementID: UUID,
        transientElementIDs: Set<UUID>
    ) -> Bool {
        !transientElementIDs.contains(elementID)
    }

    /// Inverse of committed eligibility for the active transform target set.
    public static func shouldRenderInTransientLayer(
        elementID: UUID,
        transientElementIDs: Set<UUID>
    ) -> Bool {
        transientElementIDs.contains(elementID)
    }

    /// Mutual exclusion: never both true for the same id.
    public static func isSingleRenderInvariantHeld(
        elementID: UUID,
        transientElementIDs: Set<UUID>
    ) -> Bool {
        let c = shouldRenderInCommittedLayer(elementID: elementID, transientElementIDs: transientElementIDs)
        let t = shouldRenderInTransientLayer(elementID: elementID, transientElementIDs: transientElementIDs)
        return c != t
    }
}

/// Builds the set of layout-object IDs that must leave the committed layer.
public enum StageEditTransientTargets: Sendable {
    public static func layoutObjectIDs(
        activeTransform: StageTransformInteraction,
        moveDragIDs: Set<UUID>,
        resizeObjectID: UUID?,
        rotateObjectID: UUID?,
        toolbarRotationPreviewIDs: Set<UUID>
    ) -> Set<UUID> {
        var ids = Set<UUID>()
        switch activeTransform {
        case .move(let id), .resize(let id), .rotate(let id):
            ids.insert(id)
        case .aim, .pan, .none:
            break
        }
        ids.formUnion(moveDragIDs)
        if let resizeObjectID { ids.insert(resizeObjectID) }
        if let rotateObjectID { ids.insert(rotateObjectID) }
        ids.formUnion(toolbarRotationPreviewIDs)
        return ids
    }

    public static func fixtureIDs(
        activeTransform: StageTransformInteraction,
        moveDragFixtureIDs: Set<UUID>,
        aimFixtureID: UUID?
    ) -> Set<UUID> {
        var ids = Set<UUID>()
        if case .move(let id) = activeTransform { ids.insert(id) }
        if case .aim(let id) = activeTransform { ids.insert(id) }
        ids.formUnion(moveDragFixtureIDs)
        if let aimFixtureID { ids.insert(aimFixtureID) }
        return ids
    }
}
