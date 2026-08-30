import AuroraEngine
import AuroraModel
import SwiftUI

/// The single renderer-selection seam for fixture artwork. Geometry, interaction,
/// optical origins, and physical-control mapping remain shared by both styles.
public struct StageFixtureGlyph: View {
    public var style: StageGlyphStyle
    public var descriptor: FixtureVisualizationDescriptor
    public var geometry: FixtureGlyphGeometry
    public var liveEmitters: [FixtureElementPreviewState]
    public var selectedEmitterIDs: Set<String>
    public var affectedEmitterIDs: Set<String>
    public var wholeSelected: Bool
    public var atmosphericLevel: Double
    public var detailLevel: Int

    public init(
        style: StageGlyphStyle,
        descriptor: FixtureVisualizationDescriptor,
        geometry: FixtureGlyphGeometry,
        liveEmitters: [FixtureElementPreviewState] = [],
        selectedEmitterIDs: Set<String> = [],
        affectedEmitterIDs: Set<String> = [],
        wholeSelected: Bool = false,
        atmosphericLevel: Double = 0,
        detailLevel: Int = 1
    ) {
        self.style = style
        self.descriptor = descriptor
        self.geometry = geometry
        self.liveEmitters = liveEmitters
        self.selectedEmitterIDs = selectedEmitterIDs
        self.affectedEmitterIDs = affectedEmitterIDs
        self.wholeSelected = wholeSelected
        self.atmosphericLevel = atmosphericLevel
        self.detailLevel = detailLevel
    }

    public var body: some View {
        switch style {
        case .legacyV1:
            FixtureGlyphRenderer(
                descriptor: descriptor,
                geometry: geometry,
                liveEmitters: liveEmitters,
                selectedEmitterIDs: selectedEmitterIDs,
                affectedEmitterIDs: affectedEmitterIDs,
                wholeSelected: wholeSelected,
                atmosphericLevel: atmosphericLevel
            )
        case .prismV3:
            PrismV3FixtureGlyphRenderer(
                descriptor: descriptor,
                geometry: geometry,
                liveEmitters: liveEmitters,
                selectedEmitterIDs: selectedEmitterIDs,
                affectedEmitterIDs: affectedEmitterIDs,
                wholeSelected: wholeSelected,
                atmosphericLevel: atmosphericLevel,
                detailLevel: detailLevel
            )
        }
    }
}
