import AuroraEngine
import XCTest

final class ColorMathTests: XCTestCase {
    func testHSVRoundTrip() {
        let rgb = RGBColor(r: 0.2, g: 0.5, b: 0.9)
        let hsv = ColorMath.hsv(from: rgb)
        let back = ColorMath.rgb(from: hsv)
        XCTAssertEqual(back.r, rgb.r, accuracy: 0.02)
        XCTAssertEqual(back.g, rgb.g, accuracy: 0.02)
        XCTAssertEqual(back.b, rgb.b, accuracy: 0.02)
    }

    func testRGBWExtractsWhite() {
        let rgb = RGBColor(r: 0.8, g: 0.6, b: 0.6)
        let rgbw = ColorMath.rgbw(from: rgb)
        XCTAssertEqual(rgbw.w, 0.6, accuracy: 0.001)
        XCTAssertEqual(rgbw.r, 0.2, accuracy: 0.001)
    }

    func testResolvedRGBChangesWithWhiteBalance() {
        let neutral = ColorMath.resolvedRGB(hue: 0, saturation: 1, brightness: 1, whiteBalance: 0)
        let warm = ColorMath.resolvedRGB(hue: 0, saturation: 1, brightness: 1, whiteBalance: 1)
        let cool = ColorMath.resolvedRGB(hue: 0, saturation: 1, brightness: 1, whiteBalance: -1)
        // Warm red should gain warmth (not pure R=1 path only) — green/blue relative shift
        XCTAssertGreaterThan(warm.g + warm.b, 0)
        XCTAssertNotEqual(neutral.r + neutral.g + neutral.b, warm.r + warm.g + warm.b, accuracy: 0.001)
        XCTAssertNotEqual(warm.b, cool.b, accuracy: 0.01)
    }

    func testAuthoringFromRGBNeutralWB() {
        let auth = ColorMath.authoringFromRGB(RGBColor(r: 0, g: 0, b: 1))
        XCTAssertEqual(auth.whiteBalance, 0, accuracy: 0.001)
        XCTAssertGreaterThan(auth.hue, 200)
        XCTAssertLessThan(auth.hue, 280)
    }

    func testProgrammerColorBatchRetainsAuthoringAndRGB() {
        let auth = ColorAuthoringState(hue: 120, saturation: 1, brightness: 0.5, whiteBalance: 0.25)
        let batch = ColorMath.programmerColorBatch(from: auth)
        XCTAssertEqual(batch[ColorAuthoringAttribute.hue] ?? -1, 120, accuracy: 0.01)
        XCTAssertEqual(batch[ColorAuthoringAttribute.whiteBalance] ?? 0, 0.25, accuracy: 0.01)
        XCTAssertNotNil(batch["colorR"])
        XCTAssertNotNil(batch["colorG"])
        XCTAssertNotNil(batch["colorB"])
        XCTAssertNil(batch["colorW"])
    }

    func testClampAuthoringRanges() {
        XCTAssertEqual(ColorMath.clampProgrammerAttribute(ColorAuthoringAttribute.hue, value: 400), 40, accuracy: 0.01)
        XCTAssertEqual(ColorMath.clampProgrammerAttribute(ColorAuthoringAttribute.whiteBalance, value: 2), 1, accuracy: 0.01)
        XCTAssertEqual(ColorMath.clampProgrammerAttribute(ColorAuthoringAttribute.whiteBalance, value: -2), -1, accuracy: 0.01)
        XCTAssertEqual(ColorMath.clampProgrammerAttribute("intensity", value: 1.5), 1, accuracy: 0.01)
    }

    func testBrightnessScalesRGBWithoutChangingHueFamily() {
        let full = ColorMath.resolvedRGB(hue: 0, saturation: 1, brightness: 1, whiteBalance: 0)
        let half = ColorMath.resolvedRGB(hue: 0, saturation: 1, brightness: 0.5, whiteBalance: 0)
        XCTAssertEqual(full.r, 1, accuracy: 0.02)
        XCTAssertEqual(half.r, 0.5, accuracy: 0.05)
        XCTAssertLessThan(half.g, 0.05)
        XCTAssertLessThan(half.b, 0.05)
    }
}
