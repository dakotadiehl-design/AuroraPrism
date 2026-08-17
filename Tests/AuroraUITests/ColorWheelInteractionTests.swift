import CoreGraphics
import XCTest
@testable import AuroraUI

final class ColorWheelInteractionTests: XCTestCase {
    func testActiveSelectorRetainsOwnershipAcrossAnotherSelector() {
        XCTAssertEqual(
            ColorWheelInteraction.lockedTarget(
                active: .brightness,
                startTarget: .whiteBalance
            ),
            .brightness
        )
    }

    func testMouseDownChoosesSelectorWhenNothingOwnsDrag() {
        XCTAssertEqual(
            ColorWheelInteraction.lockedTarget(
                active: nil,
                startTarget: .whiteBalance
            ),
            .whiteBalance
        )
    }

    func testDirectHandleHitWinsOverBroadCharacterRingRegion() {
        let target = ColorWheelInteraction.dragTarget(
            at: CGPoint(x: 170, y: 120),
            size: 240,
            brightnessAngle: 0,
            whiteBalanceAngle: 180,
            characterRadius: 50,
            characterInnerRadius: 45,
            characterOuterRadius: 75,
            innerSaturationRadius: 76,
            outerRadius: 120
        )
        XCTAssertEqual(target, .brightness)
    }

    func testCenterDoesNotAcquireASelector() {
        let target = ColorWheelInteraction.dragTarget(
            at: CGPoint(x: 120, y: 120),
            size: 240,
            brightnessAngle: 0,
            whiteBalanceAngle: 180,
            characterRadius: 50,
            characterInnerRadius: 45,
            characterOuterRadius: 75,
            innerSaturationRadius: 76,
            outerRadius: 120
        )
        XCTAssertNil(target)
    }
}
