import AuroraUI
import XCTest

final class ValueFaderGeometryTests: XCTestCase {

    private let standard = ValueFaderMetrics.forDensity(.standard)
    private let compact = ValueFaderMetrics.forDensity(.compact)
    private let performance = ValueFaderMetrics.forDensity(.performance)

    func testResponsiveChannelHeightGrowsButIsCapped() {
        let base = standard.channelHeight
        XCTAssertEqual(
            ProgrammerColorFaderLayout.responsiveChannelHeight(
                availableHeight: base + 48,
                baseChannelHeight: base,
                basePanelHeight: base + 48
            ),
            base
        )
        XCTAssertEqual(
            ProgrammerColorFaderLayout.responsiveChannelHeight(
                availableHeight: base + 148,
                baseChannelHeight: base,
                basePanelHeight: base + 48
            ),
            base + 38,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ProgrammerColorFaderLayout.responsiveChannelHeight(
                availableHeight: 2_000,
                baseChannelHeight: base,
                basePanelHeight: base + 48
            ),
            base + 72
        )
    }

    func testChannelHeightIsTravelPlusThumb() {
        XCTAssertEqual(standard.channelHeight, standard.thumbTravelHeight + standard.thumbHeight)
        XCTAssertEqual(standard.channelHeight, 190, accuracy: 0.001)
        XCTAssertEqual(performance.channelHeight, 224, accuracy: 0.001)
        XCTAssertEqual(compact.channelHeight, compact.thumbTravelHeight + compact.thumbHeight)
    }

    func testCompactDoesNotShrinkGrabTarget() {
        XCTAssertGreaterThanOrEqual(compact.controlWidth, standard.controlWidth)
        XCTAssertGreaterThanOrEqual(compact.thumbWidth, standard.thumbWidth)
        XCTAssertGreaterThanOrEqual(compact.thumbHeight, standard.thumbHeight)
        XCTAssertGreaterThanOrEqual(compact.thumbTravelHeight, 120)
        XCTAssertLessThanOrEqual(compact.thumbTravelHeight, standard.thumbTravelHeight)
    }

    func testPerformanceIsLarger() {
        XCTAssertGreaterThan(performance.controlWidth, standard.controlWidth)
        XCTAssertGreaterThan(performance.thumbWidth, standard.thumbWidth)
        XCTAssertGreaterThan(performance.thumbTravelHeight, standard.thumbTravelHeight)
    }

    func testEndpointsMapWithoutClipping() {
        let h = standard.channelHeight
        let th = standard.thumbHeight
        let y1 = ValueFaderGeometry.thumbCenterY(value: 1, channelHeight: h, thumbHeight: th)
        let y0 = ValueFaderGeometry.thumbCenterY(value: 0, channelHeight: h, thumbHeight: th)
        let yMid = ValueFaderGeometry.thumbCenterY(value: 0.5, channelHeight: h, thumbHeight: th)

        XCTAssertEqual(y1, th / 2, accuracy: 0.01)
        XCTAssertEqual(y0, h - th / 2, accuracy: 0.01)
        XCTAssertEqual(yMid, h / 2, accuracy: 0.5)

        // Thumb fully inside channel
        XCTAssertGreaterThanOrEqual(y1 - th / 2, -0.01)
        XCTAssertLessThanOrEqual(y0 + th / 2, h + 0.01)
    }

    func testPointerRoundTrip() {
        let h = standard.channelHeight
        let th = standard.thumbHeight
        for v in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let y = ValueFaderGeometry.thumbCenterY(value: v, channelHeight: h, thumbHeight: th)
            let back = ValueFaderGeometry.value(fromThumbCenterY: y, channelHeight: h, thumbHeight: th)
            XCTAssertEqual(back, v, accuracy: 0.0001, "round-trip failed for \(v)")
        }
    }

    func testHorizontalPointerRoundTripAndEndpoints() {
        let width: CGFloat = 260
        let thumbWidth: CGFloat = 46
        for v in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let x = ValueFaderGeometry.thumbCenterX(value: v, trackWidth: width, thumbWidth: thumbWidth)
            let back = ValueFaderGeometry.value(fromThumbCenterX: x, trackWidth: width, thumbWidth: thumbWidth)
            XCTAssertEqual(back, v, accuracy: 0.0001)
        }
        XCTAssertEqual(ValueFaderGeometry.thumbCenterX(value: 0, trackWidth: width, thumbWidth: thumbWidth), thumbWidth / 2)
        XCTAssertEqual(ValueFaderGeometry.thumbCenterX(value: 1, trackWidth: width, thumbWidth: thumbWidth), width - thumbWidth / 2)
    }

    func testHorizontalDragPreservesGrabOffset() {
        let width: CGFloat = 260
        let thumbWidth: CGFloat = 46
        let center = ValueFaderGeometry.thumbCenterX(value: 0.5, trackWidth: width, thumbWidth: thumbWidth)
        XCTAssertTrue(ValueFaderGeometry.pointerHitsThumb(pointerX: center + 10, thumbCenterX: center, thumbWidth: thumbWidth))
        let value = ValueFaderGeometry.value(
            fromPointerX: center + 30,
            dragOffset: 10,
            trackWidth: width,
            thumbWidth: thumbWidth
        )
        XCTAssertEqual(value, ValueFaderGeometry.value(fromThumbCenterX: center + 20, trackWidth: width, thumbWidth: thumbWidth), accuracy: 0.0001)
    }

    func testClampOutsideBounds() {
        let h = standard.channelHeight
        let th = standard.thumbHeight
        XCTAssertEqual(
            ValueFaderGeometry.value(fromThumbCenterY: -100, channelHeight: h, thumbHeight: th),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ValueFaderGeometry.value(fromThumbCenterY: h + 100, channelHeight: h, thumbHeight: th),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(ValueFaderGeometry.clamp01(-0.2), 0)
        XCTAssertEqual(ValueFaderGeometry.clamp01(1.4), 1)
    }

    func testUndersizedChannelTravelSafe() {
        let t = ValueFaderGeometry.travel(channelHeight: 10, thumbHeight: 30)
        XCTAssertEqual(t, 1, accuracy: 0.001)
    }

    func testDragOffsetThumbVsSeek() {
        let center: CGFloat = 80
        let th: CGFloat = 30
        // Pointer on thumb
        XCTAssertTrue(ValueFaderGeometry.pointerHitsThumb(pointerY: 85, thumbCenterY: center, thumbHeight: th))
        let offset = ValueFaderGeometry.dragOffset(pointerY: 85, thumbCenterY: center)
        XCTAssertEqual(offset, 5, accuracy: 0.001)

        // Seek outside
        XCTAssertFalse(ValueFaderGeometry.pointerHitsThumb(pointerY: 10, thumbCenterY: center, thumbHeight: th))

        let h = standard.channelHeight
        let withOffset = ValueFaderGeometry.value(
            fromPointerY: 90,
            dragOffset: offset,
            channelHeight: h,
            thumbHeight: th
        )
        let seek = ValueFaderGeometry.value(
            fromPointerY: 90,
            dragOffset: 0,
            channelHeight: h,
            thumbHeight: th
        )
        // Different effective center → different values
        XCTAssertNotEqual(withOffset, seek, accuracy: 0.0001)
    }

    func testMixedFirstKeyboard() {
        XCTAssertEqual(ValueFaderGeometry.mixedFirstKeyboardValue(increment: true), 0.51, accuracy: 0.0001)
        XCTAssertEqual(ValueFaderGeometry.mixedFirstKeyboardValue(increment: false), 0.49, accuracy: 0.0001)
    }

    func testKeyboardSteps() {
        XCTAssertEqual(ValueFaderGeometry.keyboardStep(shift: false, option: false), 0.01, accuracy: 0.00001)
        XCTAssertEqual(ValueFaderGeometry.keyboardStep(shift: true, option: false), 0.001, accuracy: 0.00001)
        XCTAssertEqual(ValueFaderGeometry.keyboardStep(shift: false, option: true), 0.05, accuracy: 0.00001)
        // Option wins when both
        XCTAssertEqual(ValueFaderGeometry.keyboardStep(shift: true, option: true), 0.05, accuracy: 0.00001)
    }

    func testApplyStepClamps() {
        XCTAssertEqual(ValueFaderGeometry.applyStep(current: 0.99, delta: 0.05), 1, accuracy: 0.0001)
        XCTAssertEqual(ValueFaderGeometry.applyStep(current: 0.01, delta: -0.05), 0, accuracy: 0.0001)
    }

    func testEmitterLayoutScrollDetection() {
        let w: CGFloat = 72
        let spacing: CGFloat = 10
        // 3 faders: 3*72 + 2*10 = 236
        XCTAssertFalse(
            ProgrammerColorFaderLayout.emitterRegionNeedsScroll(
                availableWidth: 240,
                emitterCount: 3,
                faderWidth: w,
                spacing: spacing
            )
        )
        XCTAssertTrue(
            ProgrammerColorFaderLayout.emitterRegionNeedsScroll(
                availableWidth: 200,
                emitterCount: 3,
                faderWidth: w,
                spacing: spacing
            )
        )
        XCTAssertEqual(
            ProgrammerColorFaderLayout.emittersContentWidth(emitterCount: 6, faderWidth: w, spacing: spacing),
            6 * 72 + 5 * 10,
            accuracy: 0.001
        )
    }

    func testMinimumProgrammerWidth() {
        let minW = ProgrammerColorFaderLayout.minimumProgrammerWidth(
            dimmerWidth: 72,
            wheelMinWidth: 180,
            faderWidth: 72,
            spacing: 16
        )
        // 72 + 180 + 72 + 32 = 356
        XCTAssertEqual(minW, 356, accuracy: 0.001)
    }

    func testDisplayLabelAbbreviation() {
        XCTAssertEqual(ProgrammerColorFaderLayout.displayLabel("DIMMER"), "DIMMER")
        let long = ProgrammerColorFaderLayout.displayLabel("ULTRAVIOLET CHANNEL", maxChars: 10)
        XCTAssertTrue(long.count <= 12)
        XCTAssertNotEqual(long, "ULTRAVIOLET CHANNEL")
        // Word-aware short form
        let cool = ProgrammerColorFaderLayout.displayLabel("Cool White", maxChars: 8)
        XCTAssertTrue(cool.contains("Cool") || cool.hasSuffix("…"))
    }
}
