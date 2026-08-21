import AuroraDesignSystem
import AuroraUI
import SwiftUI

/// Document-aware host for the dedicated Prism Effects workspace.
///
/// The complete three-column authoring surface will replace the compatibility
/// panel as FX-5 lands. Establishing this scene now gives the workspace one stable
/// window identity and prevents Effects from becoming another main-workspace tab.
struct EffectsEngineWindowRoot: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        EffectsPanel(
            orderedSelectionFixtureIDs: appModel.session.selection.snapshot.orderedFixtureIDs,
            effects: appModel.engine.effects,
            fixtureGroups: appModel.session.project.groups,
            onChanged: {
                appModel.commitEffectsToProject()
                appModel.notifyUI()
            },
            onApplyToProgrammer: { look in
                appModel.engine.programmer.setMany(look.fixtureAttributes)
                appModel.notifyUI()
            },
            evaluatePreview: { effect, time in
                appModel.engine.evaluateEffectPreview(effect, time: time)
            },
            stagePlacements: appModel.session.project.stageLayout.fixtures,
            orderedSelectionTargets: appModel.session.selection.snapshot.orderedFixtureTargets,
            onPrivatePreviewChanged: { appModel.setEffectsStagePreview($0) },
            onShowInMainStageChanged: { appModel.setEffectsStagePreviewEnabled($0) }
        )
        .frame(minWidth: 1_100, minHeight: 700)
        .background(AuroraColor.surfaceBase)
        .preferredColorScheme(.dark)
    }
}
