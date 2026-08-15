import AuroraModel
import Foundation

/// Pure routing helpers for Patch fixture lifecycle (testable without AppKit).
public enum PatchFixtureLifecycle {
    public enum DeleteKeyAction: Equatable, Sendable {
        /// Clear DMX assignment only.
        case unpatch(fixtureIDs: [UUID])
        /// No-op (already unpatched, empty selection, or text field owns the key).
        case ignore
    }

    public enum ContextMenuAction: Equatable, Sendable {
        case inspect
        case repatch
        case unpatch
        case deleteFixture
    }

    /// Delete/Backspace on the Universe canvas.
    /// Never routes to permanent deletion — that requires the explicit Delete Fixture… menu path.
    public static func deleteKeyAction(
        isTextEditing: Bool,
        selectedFixtureIDs: [UUID],
        project: ShowProject
    ) -> DeleteKeyAction {
        if isTextEditing { return .ignore }
        let patched = selectedFixtureIDs.filter { id in
            project.fixtures.first(where: { $0.id == id })?.isPatched == true
        }
        if patched.isEmpty { return .ignore }
        return .unpatch(fixtureIDs: patched)
    }

    /// Ordered context-menu actions for the current selection.
    public static func contextMenuActions(
        selectedFixtureIDs: [UUID],
        project: ShowProject
    ) -> [ContextMenuAction] {
        guard !selectedFixtureIDs.isEmpty else { return [] }
        let fixtures = selectedFixtureIDs.compactMap { id in
            project.fixtures.first(where: { $0.id == id })
        }
        guard !fixtures.isEmpty else { return [] }

        var actions: [ContextMenuAction] = [.inspect]
        if fixtures.count == 1 {
            actions.append(.repatch)
        }
        if fixtures.contains(where: \.isPatched) {
            actions.append(.unpatch)
        }
        actions.append(.deleteFixture)
        return actions
    }

    /// Whether bulk delete is allowed for the selection (always true if fixtures exist;
    /// destructive confirmation is a UI concern).
    public static func canDeleteFixtures(
        selectedFixtureIDs: [UUID],
        project: ShowProject
    ) -> Bool {
        selectedFixtureIDs.contains { id in
            project.fixtures.contains(where: { $0.id == id })
        }
    }

    /// Whether bulk unpatch applies (at least one selected fixture is patched).
    public static func canUnpatchFixtures(
        selectedFixtureIDs: [UUID],
        project: ShowProject
    ) -> Bool {
        selectedFixtureIDs.contains { id in
            project.fixtures.first(where: { $0.id == id })?.isPatched == true
        }
    }
}
