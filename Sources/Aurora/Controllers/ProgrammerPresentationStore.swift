import AuroraEngine
import AuroraModel
import Foundation

/// Observable **projection** of Programmer state for UI-03 (not a second truth store).
///
/// - Programmer remains authoritative.
/// - This store may be discarded/rebuilt at any time.
/// - No edits are ever applied to the presentation snapshot itself.
@MainActor
final class ProgrammerPresentationStore: ObservableObject {
    @Published private(set) var presentation: ProgrammerAttributePresentation = .empty
    /// Bumps on every refresh so views can re-sync drag drafts after external mutation.
    @Published private(set) var revision: UInt64 = 0

    func refresh(
        orderedFixtureIDs: [UUID],
        project: ShowProject,
        programmer: Programmer
    ) {
        let next = ProgrammerAttributePresentationResolver.resolve(
            orderedFixtureIDs: orderedFixtureIDs,
            project: project,
            programmer: programmer.snapshot()
        )
        // Skip revision/publish when capability presentation is unchanged (Post-C6 / pre-color-engine).
        guard next != presentation else { return }
        presentation = next
        revision &+= 1
    }
}
